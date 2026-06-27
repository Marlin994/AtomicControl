# AtomicControl

**AtomicControl** is a modular CC:Tweaked controller for Extreme Reactors / Bigger Reactors.

It provides a touch monitor HMI for controlling active and passive reactors, turbines, energy storage and different operation modes.

## Features

- Active and passive reactor support
- Multiple turbines
- Energy storage support
- ECO / NORMAL / CYANITE modes
- Load balancing
- Alarm system
- Current steam production display
- Touch monitor interface
- Persistent configuration
- Autostart setup
- Language files for German and English

## Screenshots

Screenshots can be added to `docs/screenshots/`.

## Installation

Copy the contents of `src/` to your ComputerCraft computer.

Start AtomicControl:

```lua
main
```

Run setup again:

```lua
main setup
```

## Language

Edit `reactor_turbine_controller.cfg`:

```lua
language = "de"
```

or:

```lua
language = "en"
```

## Project Structure

```text
src/
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
  lang/
    de.lua
    en.lua

installer/
  install.lua
  update.lua

docs/
  setup.md
  peripherals.md
  modes.md
  language.md
```

## License

MIT License.
