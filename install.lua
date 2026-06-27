-- AtomicControl Installer
-- https://github.com/Marlin994/AtomicControl

local BASE = "https://raw.githubusercontent.com/Marlin994/AtomicControl/main/src/"

-- target = local file name on the ComputerCraft computer
-- source = preferred GitHub file name
-- fallback = optional old/alternate GitHub file name
local files = {
  {target="main.lua"},
  {target="config.lua"},
  {target="control.lua"},
  {target="devices.lua"},
  {target="reactors.lua"},
  {target="turbines.lua"},
  {target="energy.lua"},
  {target="alarms.lua"},
  {target="ui.lua"},
  {target="utils.lua"},
  {target="lang.lua"},

  -- new v1.2 modules, always saved lowercase locally
  {target="steammanager.lua", source="steammanager.lua", fallback="SteamManager.lua"},
  {target="turbinecontroller.lua", source="turbinecontroller.lua", fallback="TurbineController.lua"},
  {target="activereactorcontroller.lua", source="activereactorcontroller.lua", fallback="ActiveReactorController.lua"},
  {target="passivereactorcontroller.lua", source="passivereactorcontroller.lua", fallback="PassiveReactorController.lua"},

  {target="startup.lua"},
  {target="lang/de.lua"},
  {target="lang/en.lua"}
}

local function ensureDir(path)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
end

local function downloadFile(entry)
  local target = entry.target
  local source = entry.source or target
  local fallback = entry.fallback

  ensureDir(target)

  if fs.exists(target) then
    fs.delete(target)
  end

  write("Downloading " .. target .. " ... ")

  local ok = shell.run("wget", BASE .. source, target)

  if (not ok or not fs.exists(target)) and fallback then
    if fs.exists(target) then fs.delete(target) end
    ok = shell.run("wget", BASE .. fallback, target)
  end

  if ok and fs.exists(target) then
    print("OK")
    return true
  end

  print("FAILED")
  print("")
  print("Missing file:")
  print("  " .. target)
  print("")
  print("Tried:")
  print("  " .. BASE .. source)
  if fallback then print("  " .. BASE .. fallback) end
  print("")
  return false
end

term.clear()
term.setCursorPos(1, 1)

print("AtomicControl Installer")
print("-----------------------")
print("")

for _, entry in ipairs(files) do
  if not downloadFile(entry) then
    print("Installation aborted.")
    print("")
    print("Fix:")
    print("Make sure all files from the latest patch")
    print("exist in your GitHub repo under /src/.")
    return
  end
end

print("")
print("Installation complete.")
print("Starting setup...")
sleep(1)

shell.run("main", "setup")
