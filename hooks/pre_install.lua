--- Pre-installation hook (also performs installation)
PLUGIN = {}

local http = require("vfox.http")
local archive = require("vfox.archive")

--- Install Yarn v1 (Classic)
local function installYarnV1(version, install_path, temp_dir)
    local archive_name = "yarn-v" .. version .. ".tar.gz"
    local archive_url = "https://classic.yarnpkg.com/downloads/" .. version .. "/" .. archive_name
    local archive_path = temp_dir .. "/" .. archive_name
    
    -- Download archive using vfox's http module
    local err = http.download_file({
        url = archive_url,
        file_path = archive_path
    })
    if err ~= nil then
        error("Failed to download Yarn archive: " .. err)
    end
    
    -- GPG verification (if not skipped)
    if os.getenv("MISE_YARN_SKIP_GPG") == nil then
        -- Check if gpg is available
        local gpg_check = io.popen("command -v gpg 2>/dev/null")
        local has_gpg = gpg_check and gpg_check:read("*a"):match("%S")
        if gpg_check then gpg_check:close() end
        
        if has_gpg then
            -- Download signature
            local signature_url = archive_url .. ".asc"
            local signature_path = temp_dir .. "/" .. archive_name .. ".asc"
            
            err = http.download_file({
                url = signature_url,
                file_path = signature_path
            })
            if err ~= nil then
                print("⚠️  Warning: Could not download signature file")
            else
                -- Import GPG key
                local keyring_dir = os.getenv("HOME") .. "/.cache/vfox-yarn/keyrings"
                os.execute("mkdir -p " .. keyring_dir .. " && chmod 0700 " .. keyring_dir)
                
                -- Download and import GPG key
                local gpg_key_path = temp_dir .. "/pubkey.gpg"
                err = http.download_file({
                    url = "https://dl.yarnpkg.com/debian/pubkey.gpg",
                    file_path = gpg_key_path
                })
                if err == nil then
                    os.execute("GNUPGHOME=" .. keyring_dir .. " gpg --import " .. gpg_key_path .. " 2>/dev/null")
                    
                    -- Verify signature
                    local verify_result = os.execute("GNUPGHOME=" .. keyring_dir .. " gpg --verify " .. signature_path .. " " .. archive_path .. " 2>/dev/null")
                    if verify_result ~= 0 and verify_result ~= true then
                        print("⚠️  GPG verification failed. Set MISE_YARN_SKIP_GPG=1 to skip verification")
                        error("GPG signature verification failed")
                    end
                end
            end
        else
            print("⚠️  Warning: gpg not found. Set MISE_YARN_SKIP_GPG=1 to skip GPG verification")
        end
    end
    
    -- Create installation directory
    os.execute("rm -rf " .. install_path .. " 2>/dev/null")
    os.execute("mkdir -p " .. install_path)
    
    -- Extract archive using vfox's archive module
    err = archive.decompress(archive_path, install_path, {
        strip_components = 1
    })
    if err ~= nil then
        error("Failed to extract Yarn archive: " .. err)
    end
    
    -- Clean up
    os.execute("rm -f " .. archive_path .. " " .. archive_path .. ".asc")
end

--- Install Yarn v2+ (Berry)
local function installYarnV2Plus(version, install_path, temp_dir)
    local yarn_url = "https://repo.yarnpkg.com/" .. version .. "/packages/yarnpkg-cli/bin/yarn.js"
    local yarn_file = temp_dir .. "/yarn.js"
    
    -- Download yarn.js using vfox's http module
    local err = http.download_file({
        url = yarn_url,
        file_path = yarn_file
    })
    if err ~= nil then
        error("Failed to download Yarn: " .. err)
    end
    
    -- Create installation directory structure
    os.execute("rm -rf " .. install_path .. " 2>/dev/null")
    os.execute("mkdir -p " .. install_path .. "/bin")
    
    -- Move and make executable
    os.execute("cp " .. yarn_file .. " " .. install_path .. "/bin/yarn")
    os.execute("chmod +x " .. install_path .. "/bin/yarn")
end

function PLUGIN:PreInstall(ctx)
    local version = ctx.version
    
    -- Derive install path from environment  
    local install_path = os.getenv("MISE_INSTALL_PATH")
    if not install_path then
        install_path = os.getenv("HOME") .. "/.local/share/mise/installs/yarn/" .. version
    end
    
    print("Installing Yarn " .. version .. " to " .. install_path .. "...")
    
    -- Create temp directory
    local temp_dir = "/tmp/vfox-yarn-" .. os.time()
    os.execute("mkdir -p " .. temp_dir)
    
    local success, err
    local major_version = string.sub(version, 1, 1)
    if major_version == "1" then
        -- Install Yarn Classic (v1.x)
        success, err = pcall(installYarnV1, version, install_path, temp_dir)
    else
        -- Install Yarn Berry (v2.x+)
        success, err = pcall(installYarnV2Plus, version, install_path, temp_dir)
    end
    
    -- Clean up temp directory
    os.execute("rm -rf " .. temp_dir)
    
    if not success then
        error("Installation failed: " .. tostring(err))
    end
    
    -- Return the version unchanged
    return {
        version = version
    }
end

return PLUGIN