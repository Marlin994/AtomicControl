-- AtomicControl Updater
-- Downloads the latest source files from GitHub.
-- Does NOT touch reactor_turbine_controller.cfg.

local BASE = "https://raw.githubusercontent.com/Marlin994/AtomicControl/main/src/"

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
  "startup.lua",
  "lang/de.lua",
  "lang/en.lua"
}

local function findMonitor()
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "monitor" then
      return peripheral.wrap(name)
    end
  end
  return nil
end

local function drawScreen(title, subtitle, bg)
  local mon = findMonitor()

  if mon then
    local w, h = mon.getSize()
    mon.setTextScale(0.5)
    mon.setBackgroundColor(bg or colors.red)
    mon.setTextColor(colors.white)
    mon.clear()

    local lines = { title or "AtomicControl", "", subtitle or "Updating..." }
    local startY = math.floor((h - #lines) / 2) + 1

    for i, line in ipairs(lines) do
      mon.setCursorPos(math.max(1, math.floor((w - #line) / 2) + 1), startY + i - 1)
      mon.write(line)
    end
  end
end

local function ensureDir(path)
  local dir = fs.getDir(path)
  if dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
end

local function downloadFile(file)
  ensureDir(file)

  local tmp = file .. ".tmp"

  if fs.exists(tmp) then fs.delete(tmp) end

  local ok = shell.run("wget", BASE .. file, tmp)

  if not ok or not fs.exists(tmp) then
    if fs.exists(tmp) then fs.delete(tmp) end
    return false
  end

  if fs.exists(file) then fs.delete(file) end
  fs.move(tmp, file)

  return true
end

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)

drawScreen("AtomicControl", "Updating...", colors.red)

print("AtomicControl Updater")
print("---------------------")
print("Downloading latest files...")
print("")

for _, file in ipairs(files) do
  write("Downloading " .. file .. " ... ")

  local ok = downloadFile(file)

  if ok then
    print("OK")
  else
    print("FAILED")
    print("")
    print("Update failed. Existing config was not changed.")

    drawScreen("AtomicControl", "UPDATE FAILED", colors.red)

    print("")
    print("Press any key to continue...")
    os.pullEvent("key")
    return
  end
end

print("")
print("Update complete.")
print("Rebooting...")
sleep(1)

os.reboot()
