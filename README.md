# ⚛️ AtomicControl

**AtomicControl** is an advanced reactor and turbine controller for **CC** and **Extreme/Bigger Reactors**.

It manages complete power plants consisting of active reactors, passive reactors, turbines and energy storage.

---

## Features

- Active reactor control based on turbine steam demand
- Reactor calibration curve support
- Turbine calibration
- PID-style turbine flow control around 1800 RPM
- Adaptive turbine calibration learning
- Passive reactor support
- Multiple turbines and multiple reactors
- NORMAL / CYANITE modes
- Energy storage management
- Alarm system
- Touch monitor interface
- Multi-page device lists
- German and English language files
- Autostart setup
- Installer and updater

---

## Operating Modes

### NORMAL

NORMAL is the default mode.

```text
Target steam production = turbine steam demand × 1.03
```

If active reactors are calibrated, AtomicControl uses their measured steam curves to choose rod levels directly.

### CYANITE

CYANITE mode burns fuel intentionally.

- active reactors run at 0% rods
- turbines are still regulated around 1800 RPM
- if the energy storage is full, turbines disengage but keep a small idle flow

---

## Calibration

### Turbine calibration

Use `CAL T` in the options menu.

The selected turbine is calibrated to find the flow needed for stable 1800 RPM.

### Reactor calibration

Use `CAL R` in the options menu.

The selected active reactor is measured at rod levels:

```text
100, 90, 80, 70, 60, 50, 40, 30, 20, 10, 0
```

During reactor calibration, all turbines are forced to 2000 mB/t flow.

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

---

## Requirements

- Minecraft
- CC
- Extreme Reactors or Bigger Reactors
- Advanced Monitor recommended
- Wired Modem Network recommended

---

## License

MIT License.
