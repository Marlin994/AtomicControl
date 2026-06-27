-- AtomicControl installer for CC:Tweaked
-- Usage:
--   wget run <raw-url-to-this-file>
--
-- This is a template installer. Replace BASE_URL before publishing releases.

local BASE_URL = "https://raw.githubusercontent.com/YOURNAME/AtomicControl/main/src/"

local files = {
  "main.lua",
  "config.lua",
  "control.lua",
  "devices.lua",
  "reactors.lua",
  "turbines.lua",
  "energy.lua",
  "alarms.lua",
  "ui.lua",
  "utils.lua",
  "lang.lua",
  "lang/de.lua",
  "lang/en.lua"
}

local function ensureDir(path)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
end

print("AtomicControl installer")
print("-----------------------")

for _, file in ipairs(files) do
  ensureDir(file)
  local url = BASE_URL .. file
  print("Downloading " .. file)
  shell.run("wget", url, file)
end

print("")
print("Done.")
print("Start with:")
print("  main")
print("")
print("Run setup with:")
print("  main setup")
