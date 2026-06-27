# ⚛️ AtomicControl

**AtomicControl** is an advanced reactor and turbine controller for **CC** and **Extreme/Bigger Reactors**.

It automatically manages complete power plants consisting of:

- ☢️ Active Reactors
- ☢️ Passive Reactors
- 🌪️ Multiple Turbines
- 🔋 Energy Storage
- ⚖️ Intelligent Load Balancing
- 🚨 Alarm System
- 📊 Live Touch Monitor Interface
- 🌍 German & English language support

---

# Features

- Automatic active reactor control based on turbine steam demand
- Passive reactor support
- Multiple turbine support
- Turbine calibration for stable 1800 RPM operation
- Automatic turbine RPM regulation
- NORMAL / CYANITE operating modes
- Automatic energy storage management
- Reactor load balancing
- Alarm system
- Current steam production display
- Multi-page touch interface
- Automatic peripheral detection
- Configuration is automatically saved
- Autostart support
- Modular architecture
- Language system (German / English)

---

# Operating Modes

## NORMAL

NORMAL is the default mode.

It tries to produce only slightly more steam than the turbines currently consume.

```text
Target steam production = turbine steam demand × 1.03
```

The controller uses a small deadband so the reactor does not constantly move the rods.

## CYANITE

CYANITE mode is used to burn fuel and produce Cyanite.

- Active reactors run at 0% rods
- Turbines are still regulated around 1800 RPM
- If the energy storage is full, turbines are disengaged but kept ready with idle flow

---

# Installation

## Recommended (Pastebin)

```lua
pastebin run rmAZkc7s
```

The bootstrap loader always downloads the latest version directly from GitHub.

---

## Alternative (GitHub)

```lua
wget run https://raw.githubusercontent.com/Marlin994/AtomicControl/main/install.lua
```

---

# Updating

```lua
wget run https://raw.githubusercontent.com/Marlin994/AtomicControl/main/update.lua
```

---

# Requirements

- Minecraft
- CC
- Extreme Reactors or Bigger Reactors
- Advanced Monitor (recommended 5x4)
- Wired Modem Network

---

# Project Structure

```text
src/
installer/
docs/
lang/
```

---

# Contributing

Pull requests, bug reports, and feature requests are always welcome.

If you have ideas or find a bug, feel free to open an Issue.

---

# License

This project is licensed under the **MIT License**.

---

Made with ❤️ for the CC community.
