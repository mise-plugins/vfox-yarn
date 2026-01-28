--- Post-installation hook

-- os.execute returns 0 in Lua 5.1, true in Lua 5.2+
local function exec_success(result)
    return result == true or result == 0
end

local function download_file(url, output_path)
    -- Detect Windows
    local is_windows = package.config:sub(1, 1) == '\\'
    local stderr_redirect = is_windows and " 2>NUL" or " 2>/dev/null"

    -- Try curl first (more likely to be available on Windows via Git Bash)
    local curl_cmd = "curl -sSL -o " .. output_path .. " " .. url .. stderr_redirect
    local wget_cmd = "wget -q -O " .. output_path .. " " .. url .. stderr_redirect

    if exec_success(os.execute(curl_cmd)) then
        return true
    elseif exec_success(os.execute(wget_cmd)) then
        return true
    end
    return false
end

local function get_target_platform()
    -- Detect platform and architecture for Yarn v6+ binary downloads
    -- Available targets: aarch64-apple-darwin, aarch64-unknown-linux-musl,
    -- i686-unknown-linux-musl, x86_64-unknown-linux-musl
    local is_windows = package.config:sub(1, 1) == '\\'

    if is_windows then
        error("Yarn v6+ does not support Windows binaries at this time.")
    else
        -- Unix-like systems (Linux, macOS, etc.)
        local handle = io.popen("uname -ms 2>/dev/null")
        local result = handle and handle:read("*a") or ""
        if handle then handle:close() end

        if result:match("Darwin arm64") or result:match("Darwin aarch64") then
            return "aarch64-apple-darwin"
        elseif result:match("Darwin") then
            -- Intel macOS is not supported in Yarn v6+
            error("Yarn v6+ only supports ARM64 (Apple Silicon) macOS. Your system is x86_64 Intel.")
        elseif result:match("Linux aarch64") or result:match("Linux arm64") then
            return "aarch64-unknown-linux-musl"
        elseif result:match("Linux i686") or result:match("Linux i386") then
            return "i686-unknown-linux-musl"
        elseif result:match("Linux") then
            -- Default to x86_64 for Linux if not explicitly detected as 32-bit
            return "x86_64-unknown-linux-musl"
        else
            error("Unsupported platform: " .. result)
        end
    end
end

function PLUGIN:PostInstall(ctx)
    -- Get install path - it should be in sdkInfo
    local install_path = nil
    local version = nil

    -- Try to get path from sdkInfo
    if ctx.sdkInfo and ctx.sdkInfo.yarn then
        install_path = ctx.sdkInfo.yarn.path
        version = ctx.sdkInfo.yarn.version
    end

    -- Fallback to environment variable
    if not install_path then
        install_path = os.getenv("MISE_INSTALL_PATH")
    end
    if not version then
        version = os.getenv("MISE_INSTALL_VERSION") or ctx.version
    end

    if not install_path or not version then
        -- For v1, mise handles everything, so this is OK
        return {}
    end

    local major_version = string.sub(version, 1, 1)
    local is_windows = package.config:sub(1, 1) == '\\'

    if major_version == "2" or major_version == "3" or major_version == "4" or major_version == "5" then
        -- Yarn Berry (v2.x+) - download single JS file
        local yarn_url = "https://repo.yarnpkg.com/" .. version .. "/packages/yarnpkg-cli/bin/yarn.js"

        -- Create bin directory (cross-platform)
        local bin_dir = install_path .. "/bin"
        if is_windows then
            os.execute('mkdir "' .. bin_dir .. '" 2>NUL')
        else
            os.execute("mkdir -p " .. bin_dir)
        end

        -- Download yarn.js
        local yarn_js_file = bin_dir .. "/yarn.js"
        if not download_file(yarn_url, yarn_js_file) then
            error("Failed to download Yarn v2+")
        end

        -- Create wrapper script
        if is_windows then
            -- Create yarn.cmd wrapper for Windows
            local yarn_cmd = bin_dir .. "/yarn.cmd"
            local cmd_file = io.open(yarn_cmd, "w")
            if cmd_file then
                cmd_file:write("@echo off\n")
                cmd_file:write('node "%~dp0yarn.js" %*\n')
                cmd_file:close()
            end

            -- Also create yarn without extension for Git Bash
            local yarn_sh = bin_dir .. "/yarn"
            local sh_file = io.open(yarn_sh, "w")
            if sh_file then
                sh_file:write("#!/bin/sh\n")
                sh_file:write('exec node "$(dirname "$0")/yarn.js" "$@"\n')
                sh_file:close()
            end
        else
            -- Create shell wrapper for Unix
            local yarn_file = bin_dir .. "/yarn"
            local wrapper_file = io.open(yarn_file, "w")
            if wrapper_file then
                wrapper_file:write("#!/bin/sh\n")
                wrapper_file:write('exec node "$(dirname "$0")/yarn.js" "$@"\n')
                wrapper_file:close()
            end
            -- Make executable
            os.execute("chmod +x " .. yarn_file)
        end
    elseif major_version ~= "1" then
        -- Yarn ZPM (v6+) - download pre-compiled Rust binary from NPM
        local target = get_target_platform()
        local npm_url = "https://registry.npmjs.org/@yarnpkg/yarn-" ..
            target .. "/-/yarn-" .. target .. "-" .. version .. ".tgz"

        -- Create bin directory
        local bin_dir = install_path .. "/bin"
        os.execute("mkdir -p " .. bin_dir)

        -- Download the binary (tar.gz from NPM or repo)
        local archive_path = bin_dir .. "/yarn.tar.gz"
        if not download_file(npm_url, archive_path) then
            error("Failed to download Yarn " .. version .. " from npm (" .. npm_url .. ")")
        end

        -- Extract the tar.gz file
        if not exec_success(os.execute("tar -xzf " .. archive_path .. " -C " .. bin_dir)) then
            error("Failed to extract Yarn binary. Ensure tar is installed.")
        end

        -- Move /package/yarn to /bin/yarn and clean up
        os.execute("mv " .. bin_dir .. "/package/yarn " .. bin_dir .. "/yarn")
        os.execute("rm -rf " .. bin_dir .. "/package " .. archive_path)
    end

    return {}
end

return PLUGIN
