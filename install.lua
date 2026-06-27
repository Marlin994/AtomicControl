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
    "lang/de.lua",
    "lang/en.lua"
}

term.clear()
term.setCursorPos(1,1)

print("AtomicControl Installer")
print("-----------------------")
print()

for _, file in ipairs(files) do

    local dir = fs.getDir(file)
    if dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end

    if fs.exists(file) then
        fs.delete(file)
    end

    write("Downloading "..file.." ... ")

    local ok = shell.run(
        "wget",
        BASE .. file,
        file
    )

    if ok then
        print("OK")
    else
        print("FAILED")
        error("Installation aborted.")
    end
end

print()
print("Installation complete!")
print()
print("Starting setup...")
sleep(1)

shell.run("main","setup")
