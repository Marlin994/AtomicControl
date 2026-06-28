# Changelog

## 3.2.0

- Clean integrated repository release.
- Repaired `ui.lua` to avoid accumulated syntax errors from patch stacking.
- Options menu now consistently contains:
  - Language
  - Rescan
  - CAL T
  - CAL R
  - Update
  - Back
- Active/passive reactor detection now uses `isActivelyCooled()` first.
- Energy storage detection supports Extreme Reactors Energizer.
- Update now reboots after successful installation.
- Updates no longer start language/autostart setup when an existing config is found.
- Reactor calibration uses 5% rod steps.
- README updated.

