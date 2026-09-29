# Changelog

All notable changes to SiliconPulse are documented here.

## [1.1.0] - 2026-09-29

### Changed
- Rebuilt the dashboard with a clear live summary, colored history charts, and compact overview cards that expand on demand.
- Added Overview, Performance, Energy, and System categories while preserving saved card order and visibility.
- Wide pinned panels use two columns; smaller windows adapt the summary to keep readings accessible.
- Replaced settings tabs with a native sidebar and grouped controls. Added System, Light, and Dark appearance choices.
- Refined typography, spacing, card surfaces, toolbar controls, and accessibility labels in English and German.
- Updated documentation and screenshots from the running production views with real telemetry.

### Fixed
- Panel minimum sizing and wide-window bounds now match the dashboard layout.
- Card reordering accepts drops only in Edit mode.
- Removed a duplicate system model row and fixed the project link in Settings.

## [1.0.0] - 2026-09-29

### Added
- Native macOS menu bar telemetry dashboard with a pinnable, resizable panel and configurable cards.
- Battery, CPU, GPU, power, memory, disk, network/Wi-Fi, thermal, process, sleep assertion, Bluetooth battery, and fan readings where available.
- Configurable menu bar metrics, overlay mode, charts, local alerts, and English/German interface strings.
- Swift Package build script and ad-hoc signed app bundle for direct distribution.
