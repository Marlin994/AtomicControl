# ⚛️ AtomicControl

**AtomicControl** is an advanced ComputerCraft controller for **Extreme Reactors / Bigger Reactors** power plants.

It controls active reactors, passive reactors, turbines, energy storage, calibration, load balancing and a touch monitor UI.

---

## Features

- Active reactor support
- Passive reactor support
- Multiple reactor support
- Multiple turbine support
- Turbine PID-style flow control around **1800 RPM**
- Turbine calibration
- Adaptive turbine calibration learning
- Active reactor calibration curve
- Direct rod control from measured reactor calibration data
- NORMAL and CYANITE operating modes
- Energy storage detection
- Extreme Reactors Energizer support
- Direct energy IO reading where available
- Touch monitor interface
- Multi-page reactor and turbine lists
- German and English language support
- Autostart setup
- Update function with automatic reboot

---

## Supported Energy Storage APIs

AtomicControl detects energy storage by available peripheral methods.

### Common FE/RF style

```lua
getEnergyStored()
getMaxEnergyStored()
```

### Extreme Reactors Energizer

```lua
getEnergyStored()
getEnergyCapacity()
getEnergyStats()
getEnergyInsertedLastTick()
getEnergyExtractedLastTick()
getEnergyIoLastTick()
```

### Other fallback APIs

```lua
getEnergy()
getMaxEnergy()

getStored()
getCapacity()

getRFStored()
getMaxRFStored()

getEnergyFilledPercentage()
```

---

## Operating Modes

### NORMAL

NORMAL is the default mode.

```text
target steam production = turbine demand × 1.03
```

If the active reactor has been calibrated, AtomicControl uses the measured reactor steam curve to choose suitable rod levels directly.

If no reactor calibration exists yet, it falls back to dynamic rod regulation.

### CYANITE

CYANITE mode intentionally burns fuel to produce Cyanite.

In CYANITE mode:

- active reactors run at 0% rods
- turbines are still regulated around 1800 RPM
- if the energy storage is full, turbines are disengaged but kept ready with idle flow

---

## Calibration

### Turbine Calibration

Use the options menu button:

```text
CAL T
```

This calibrates the selected turbine and stores the flow needed for stable 1800 RPM.

Stored values include:

- nominal flow
- idle flow
- target RPM
- calibration timestamp

During normal operation, AtomicControl can slowly adjust the saved calibration if the turbine runs stable near 1800 RPM with a different flow requirement.

### Reactor Calibration

Use the options menu button:

```text
CAL R
```

This calibrates the selected active reactor.

During reactor calibration:

- all turbines are forced to **2000 mB/t**
- other active reactors are disabled
- the selected active reactor is measured at rod levels:

```text
100, 95, 90, 85, 80, 75, 70, 65, 60, 55,
50, 45, 40, 35, 30, 25, 20, 15, 10, 5, 0
```

AtomicControl saves the measured steam output curve and uses it in NORMAL mode to select rod levels directly.

---

## Active vs Passive Reactor Detection

AtomicControl detects active Extreme Reactors using:

```lua
isActivelyCooled()
```

Fallback checks include:

```lua
getCoolantAmountMax()
getHotFluidAmountMax()
getHotFluidStats()
```

---

## Installation

### Recommended installation via Pastebin bootstrap

```lua
pastebin run rmAZkc7s
```

The Pastebin bootstrap downloads the current installer from GitHub.

### Direct GitHub install

```lua
wget run https://raw.githubusercontent.com/Marlin994/AtomicControl/main/install.lua
```

---

## Updating

```lua
wget run https://raw.githubusercontent.com/Marlin994/AtomicControl/main/update.lua
```

The updater downloads the latest installer, installs all files, and then reboots the ComputerCraft computer automatically.

When an existing configuration file is found, setup is not started again.

---

## First Start

On first start AtomicControl asks for:

1. language
2. autostart setup

The configuration is saved in:

```text
reactor_turbine_controller.cfg
```

After the first setup, updates should not ask again for language or autostart.

---

## Monitor UI

An advanced monitor is recommended.

The UI supports:

- system status
- storage level
- steam production
- turbine RPM
- turbine flow
- reactor rods
- reactor/turbine pages
- options menu
- calibration buttons
- update button

---

## Required Files

The installer downloads these files into the ComputerCraft computer:

```text
main.lua
config.lua
control.lua
devices.lua
reactors.lua
turbines.lua
energy.lua
alarms.lua
ui.lua
utils.lua
lang.lua
steammanager.lua
turbinecontroller.lua
activereactorcontroller.lua
passivereactorcontroller.lua
reactorcalibration.lua
startup.lua
lang/de.lua
lang/en.lua
```

---

## Project Structure

```text
src/
  main.lua
  config.lua
  control.lua
  devices.lua
  energy.lua
  reactors.lua
  turbines.lua
  alarms.lua
  ui.lua
  utils.lua
  lang.lua
  steammanager.lua
  turbinecontroller.lua
  activereactorcontroller.lua
  passivereactorcontroller.lua
  reactorcalibration.lua
  startup.lua
  lang/
    de.lua
    en.lua

installer/
  install.lua
  update.lua

docs/
```

---

## Troubleshooting

### Energy storage is not detected

Run this on the ComputerCraft computer:

```lua
for _,name in ipairs(peripheral.getNames()) do
  print(name .. " -> " .. peripheral.getType(name))
end
```

Then dump methods for the storage:

```lua
local p=peripheral.wrap("NAME")
local f=fs.open("storage_dump.txt","w")
for _,m in ipairs(peripheral.getMethods("NAME")) do
  local ok,r=pcall(function() return p[m]() end)
  f.writeLine(m..": "..(ok and textutils.serialize(r) or "<parameter required>"))
end
f.close()
```

### Active/passive reactor is detected incorrectly

Dump the reactor methods and values:

```lua
local p=peripheral.wrap("NAME")
local f=fs.open("reactor_dump.txt","w")
for _,m in ipairs(peripheral.getMethods("NAME")) do
  local ok,r=pcall(function() return p[m]() end)
  f.writeLine(m..": "..(ok and textutils.serialize(r) or "<parameter required>"))
end
f.close()
```

The most important value is:

```lua
isActivelyCooled()
```

---

## License

MIT License.
