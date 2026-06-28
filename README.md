# ⚛️ AtomicControl

**AtomicControl** is an advanced ComputerCraft controller for **Extreme Reactors / Bigger Reactors** power plants.

It controls active reactors, passive reactors, turbines, energy storage, calibration, load balancing and a touch monitor UI.

---

## Current Version

**v3.2.0**

This is a clean integrated release that merges the previous patch series into one consistent repository.

---

## Features

- Active reactor support
- Passive reactor support
- Reliable active/passive detection via `isActivelyCooled()`
- Multiple reactor support
- Multiple turbine support
- Turbine PID-style flow control around **1800 RPM**
- Turbine calibration
- Adaptive turbine calibration learning
- Active reactor calibration curve
- Reactor calibration in **5% rod steps**
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

### Fallback APIs

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

- active reactors run at 0% rods
- turbines are still regulated around 1800 RPM
- if the energy storage is full, turbines are disengaged but kept ready with idle flow

---

## Calibration

### Turbine Calibration

Use:

```text
OPTION -> CAL T
```

This calibrates the selected turbine and stores the flow needed for stable 1800 RPM.

### Reactor Calibration

Use:

```text
OPTION -> CAL R
```

During reactor calibration:

- all turbines are forced to **2000 mB/t**
- other active reactors are disabled
- the selected active reactor is measured at rod levels:

```text
100, 95, 90, 85, 80, 75, 70, 65, 60, 55,
50, 45, 40, 35, 30, 25, 20, 15, 10, 5, 0
```

AtomicControl saves the measured steam output curve and uses it in NORMAL mode.

---

## Active vs Passive Reactor Detection

AtomicControl primarily uses:

```lua
isActivelyCooled()
```

This is the reliable Extreme Reactors method.

Fallback checks include:

```lua
getCoolantAmountMax()
getHotFluidAmountMax()
getHotFluidStats()
```

---

## Installation

### Recommended

```lua
pastebin run rmAZkc7s
```

### Direct GitHub install

```lua
wget run https://raw.githubusercontent.com/Marlin994/AtomicControl/main/install.lua
```

---

## Updating

```lua
wget run https://raw.githubusercontent.com/Marlin994/AtomicControl/main/update.lua
```

The updater downloads the latest installer, installs all files, and reboots the ComputerCraft computer.

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

---

## Required Files

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

## License

MIT License.
