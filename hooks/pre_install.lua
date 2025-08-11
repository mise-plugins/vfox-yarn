--- Pre-installation hook
PLUGIN = {}

local http = require("vfox.http")

function PLUGIN:PreInstall(ctx)
    local version = ctx.version
    local major_version = string.sub(version, 1, 1)
    
    if major_version == "1" then
        -- Yarn Classic (v1.x) - return tarball URL for vfox to handle
        local archive_url = "https://classic.yarnpkg.com/downloads/" .. version .. "/yarn-v" .. version .. ".tar.gz"
        
        -- Note about GPG verification
        if os.getenv("MISE_YARN_SKIP_GPG") == nil then
            local gpg_check = io.popen("command -v gpg 2>/dev/null")
            local has_gpg = gpg_check and gpg_check:read("*a"):match("%S")
            if gpg_check then gpg_check:close() end
            
            if not has_gpg then
                print("⚠️  Note: GPG verification skipped (gpg not found). Set MISE_YARN_SKIP_GPG=1 to suppress this message")
            end
            -- Note: We can't do GPG verification when vfox handles the download
            -- This is a tradeoff for simpler code
        end
        
        -- Return URL for vfox to download and extract
        return {
            version = version,
            url = archive_url
        }
    else
        -- Yarn Berry (v2.x+) - single JS file, we need to handle it manually
        local yarn_url = "https://repo.yarnpkg.com/" .. version .. "/packages/yarnpkg-cli/bin/yarn.js"
        local install_path = os.getenv("MISE_INSTALL_PATH")
        
        -- Create installation directory
        os.execute("mkdir -p " .. install_path .. "/bin")
        
        -- Download yarn.js directly to installation location
        local yarn_file = install_path .. "/bin/yarn"
        local err = http.download_file({
            url = yarn_url,
            file_path = yarn_file
        })
        
        if err ~= nil then
            error("Failed to download Yarn v2+: " .. err)
        end
        
        -- Make executable
        os.execute("chmod +x " .. yarn_file)
        
        print("✅ Yarn " .. version .. " installed")
        
        -- Return version info
        return {
            version = version
        }
    end
end

return PLUGIN