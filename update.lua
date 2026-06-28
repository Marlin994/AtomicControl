-- AtomicControl Updater
local INSTALL_URL = "https://raw.githubusercontent.com/Marlin994/AtomicControl/main/install.lua"
local TEMP_FILE = "atomiccontrol_update_install.lua"

term.clear()
term.setCursorPos(1, 1)

print("AtomicControl Updater")
print("---------------------")
print("Downloading latest installer...")
print("")

if fs.exists(TEMP_FILE) then
  fs.delete(TEMP_FILE)
end

local ok = shell.run("wget", INSTALL_URL, TEMP_FILE)

if not ok or not fs.exists(TEMP_FILE) then
  print("")
  print("Download failed.")
  return
end

print("")
print("Running installer...")
print("")

shell.run(TEMP_FILE)

if fs.exists(TEMP_FILE) then
  fs.delete(TEMP_FILE)
end

print("")
print("Update finished.")
print("Rebooting...")
sleep(2)
os.reboot()
