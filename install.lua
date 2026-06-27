-- AtomicControl Installer
-- https://github.com/Marlin994/AtomicControl

local BASE = "https://raw.githubusercontent.com/Marlin994/AtomicControl/main/src/"
local CFG_FILE = "reactor_turbine_controller.cfg"

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
  "steammanager.lua",
  "turbinecontroller.lua",
  "activereactorcontroller.lua",
  "passivereactorcontroller.lua",
  "reactorcalibration.lua",
  "startup.lua",
  "lang/de.lua",
  "lang/en.lua"
}

local function ensureDir(path)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
end

local hadConfig = fs.exists(CFG_FILE)

term.clear()
term.setCursorPos(1, 1)

print("AtomicControl Installer")
print("-----------------------")
print("")

for _, file in ipairs(files) do
  ensureDir(file)

  if fs.exists(file) then
    fs.delete(file)
  end

  write("Downloading " .. file .. " ... ")

  local ok = shell.run("wget", BASE .. file, file)

  if ok and fs.exists(file) then
    print("OK")
  else
    print("FAILED")
    print("")
    print("Missing file: " .. file)
    print("Installation aborted.")
    return
  end
end

print("")
print("Installation complete.")
sleep(1)

if hadConfig then
  print("Existing config found.")
  print("Starting AtomicControl without setup...")
  sleep(1)
  shell.run("main")
else
  print("Starting first setup...")
  sleep(1)
  shell.run("main", "setup")
end
