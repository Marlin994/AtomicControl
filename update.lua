-- AtomicControl Updater
-- Downloads the latest installer from GitHub and runs it.

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
  print("Please check:")
  print("- HTTP API enabled")
  print("- Internet connection")
  print("- GitHub repository is public")
  print("- install.lua exists in repository root")
  return
end

print("")
print("Running installer...")
print("")

shell.run(TEMP_FILE)

if fs.exists(TEMP_FILE) then
  fs.delete(TEMP_FILE)
end
