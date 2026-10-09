# Changelog

All notable changes to SiliconPulse are documented here.

## [1.2.0] - 2026-10-10

### Added
- Native Monitor window with fifteen areas: summary, performance, processes, hardware inventory, startup apps, users, services, power/frequency, Apple Silicon, recording/replay, connections, installed apps, drivers, storage analysis and benchmarks.
- FastTree-based folder scanning, retained scan history and treemap/circle views; TCP/UDP/IPC inspection informed by PortPeek.
- Confirmed management actions for user processes, launch agents/services and application removal.
- Low Power Mode control with status reconciliation and macOS administrator authorization when required.

### Changed
- Native cached chart paths with continuously scrolling layers, shape-preserving curves, a readable one-minute viewport and Reduce Motion support.
- Compact panel layout and direct access to the detailed Monitor window.
- English/German documentation and new live window screenshots. Release binaries explicitly target arm64.

### Fixed
- IOReport subscription ABI and mutable channel handling; macOS 27 CLPC CPU/GPU/ANE energy counters on supported chips.
- CPU user/kernel histories, E/P topology, frequency table validation, memory pressure reporting and process identity checks.
- Settings window reuse across panel, overlay and Monitor.

### Availability
- Missing hardware counters remain n/a. DRAM power and some NPU/media/per-process counters are unavailable on the tested Mac.
- App is ad-hoc signed, not notarized. Local verification used Apple M4 / macOS 27; other OS/chip combinations and the internet benchmark were not exercised.

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
