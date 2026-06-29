# ⚛️ AtomicControl

**AtomicControl** is an advanced ComputerCraft controller for **Extreme Reactors / Bigger Reactors** power plants.

It controls active reactors, passive reactors, turbines, energy storage, calibration, load balancing and a touch monitor UI.

---

## Current Version

**v3.3.16**

This is a cleaned-up stability release with the rebuilt multi-page UI, per-device automatic enable/disable, individual turbine target RPM, and fixed installer/storage handling.

---

## Features

- Active reactor support
- Passive reactor support
- Reliable active/passive detection via `isActivelyCooled()`
- Multiple reactor support
- Multiple turbine support
- Turbine PID-style flow control with **individual target RPM per turbine**
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
- Target-RPM-aware turbine alarms and UI coloring
- Learned steam transfer efficiency compensation
- Per-reactor and per-turbine `Auto erlaubt` / `Auto allowed` control
- Rebuilt multi-page touch UI
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
target steam production = (turbine demand / steamTransferEfficiency) × 1.03
```

If the active reactor has been calibrated, AtomicControl uses the measured reactor steam curve to choose suitable rod levels directly.

If no reactor calibration exists yet, it falls back to dynamic rod regulation.

### CYANITE

CYANITE mode intentionally burns fuel to produce Cyanite.

- active reactors run at 0% rods
- turbines are still regulated around their configured target RPM
- if the energy storage is full, turbines are disengaged but kept ready with idle flow

---

## Calibration

### Turbine Calibration

Use the turbine page:

```text
TURBINEN -> KAL TURB.
```

This calibrates the selected turbine and stores the flow needed for its configured target RPM.

### Reactor Calibration

Use the reactor page:

```text
REAKTOREN -> KAL REAK.
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

The updater downloads the latest installer, installs all program files, and reboots the ComputerCraft computer.

When an existing configuration file is found, setup is not started again.

The installer does not overwrite `startup.lua`; autostart is created only when setup asks for it and you confirm it.

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
