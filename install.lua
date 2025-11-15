-- Factory LAN Computer Installer
-- Run with: wget run https://raw.githubusercontent.com/aellsw/fag-factory-lan/main/install.lua

local GITHUB_USER = "aellsw"
local REPO = "fag-factory-lan"
local BRANCH = "main"

local files = {
  "fag/protocol.lua",
  "fag/network.lua",
  "main.lua",
  "safety.lua",
  "config.lua"
}

print("=== Factory LAN Computer Installer ===")
print("Downloading from GitHub...")
print("")

-- Create directories
if not fs.exists("fag") then
  fs.makeDir("fag")
  print("Created fag/ directory")
end

-- Download each file
local success_count = 0
local fail_count = 0

for _, file in ipairs(files) do
  local url = string.format(
    "https://raw.githubusercontent.com/%s/%s/%s/%s",
    GITHUB_USER, REPO, BRANCH, file
  )
  
  print("Downloading " .. file .. "...")
  
  local response = http.get(url)
  if response then
    local content = response.readAll()
    response.close()
    
    local handle = fs.open(file, "w")
    handle.write(content)
    handle.close()
    
    print("  OK")
    success_count = success_count + 1
  else
    print("  FAILED")
    fail_count = fail_count + 1
  end
end

print("")
print("=== Installation Complete ===")
print("Downloaded: " .. success_count .. " files")
if fail_count > 0 then
  print("Failed: " .. fail_count .. " files")
end
print("")
print("Next steps:")
print("1. Edit config.lua with your factory_id and scada_id")
print("2. Run: main")
