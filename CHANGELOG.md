# Changelog

## 2.0.0

- Rebuilt the control architecture around separate controller modules.
- Removed ECO mode for now.
- NORMAL is now the default operating mode.
- NORMAL now targets turbine steam demand with a 3% reserve.
- Added modular control structure:
  - `steammanager.lua`
  - `turbinecontroller.lua`
  - `activereactorcontroller.lua`
  - `passivereactorcontroller.lua`
- Added turbine calibration support in the turbine controller.
- Updated installer file list.
- Updated README.


## 1.0.0

- Clean full repository release.
- Added options menu.
- Added language selection before autostart.
- Added update action from options menu.
- Added German and English language files.
- Added root `install.lua` and `update.lua`.

## 0.2.0

- Project renamed to AtomicControl.
- Added language file structure.

## 0.1.0

- Modular reactor/turbine controller.
- Alarm system.
- Load balancing.
- Steam production display.
