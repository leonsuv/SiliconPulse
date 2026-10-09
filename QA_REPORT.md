# QA report

## Overlay mode

- Live screenshots were captured with `screencapture -l` from SiliconPulse-owned windows. The gallery has separate List and Bar captures over bright and dark backdrops; the bright captures visibly show the dark pill against white.
- The default overlay background opacity is 0.92. On a white backdrop, the pill composites to about sRGB 20/255. At the minimum text-opacity control setting (0.90), calculated contrast ratios against that pill are: white 14.92:1, green 9.40:1, yellow 10.73:1, orange 6.92:1, and red 4.73:1. The lowest threshold color exceeds 4.5:1.
- With sparklines disabled, overlay sampling defaults to two seconds. It skips history-buffer updates and chart drawing. `AppModel` updates only changed per-metric observable text and numeric values rather than replacing the whole snapshot.
- Process measurements used `ps` RSS and CPU for 20 one-second observations after a two-second startup settle. Menu bar only: 0.29% CPU / 127.5 MiB RSS. Overlay only with sparklines off and two-second refresh: 1.86% / 128.6 MiB. Pinned panel: 6.04% / 144.5 MiB. One run per state on an Apple Silicon Mac; not a cross-device guarantee.

## Settings and pinning

- The retained Settings window was visible in the QA process (`CGWindowListCopyWindowInfo`) and all seven English tabs plus one German tab were captured from that window.
- A pinned panel remained visible with `panelPinned=true` after the Escape handler, after Finder activation/deactivation, while Settings was open, and after terminating and relaunching the app. The final relaunch reported one visible pinned panel.

## Screenshot coverage

- 31 JPEGs are in `docs/assets/screenshots/`: panel overview, At a glance, all 13 cards, two pinned sizes, edit mode, seven Settings tabs, a German overview, German Settings, and List/Bar overlay on bright/dark backdrops.
- The capture runner is `Tools/capture-screenshots.sh`; it selects windows owned by its isolated QA process and does not capture the desktop. Each screenshot was reviewed in a contact sheet; representative dashboard, Settings, overlay, hero and social preview images were also inspected individually.
- The menu bar status item itself is owned by the macOS system menu bar process rather than an app window, so a `screencapture -l` capture limited to SiliconPulse-owned windows cannot include it. The optional demo GIF was not created.

## Build and test

- `./build.sh` completed and ad-hoc signed `SiliconPulse.app`.
- The single battery-health smoke test was attempted once. Local `swift test` stopped before running it because this machine's Command Line Tools could not resolve XCTest (`unable to resolve module dependency: 'XCTest'`). GitHub Actions has a smoke-test step on `macos-15`; its hosted result is pending publication.

## Native monitor feature pass (2026-10-09)

### Scope and implementation

The separate, retained Monitor window now exposes the fifteen functional areas from the supplied reference screenshots: Summary, Performance, Processes, System Info, Startup apps, Users, Services, Power & Frequency, Apple Silicon, Flight Recorder, Connections, Installed Apps, Drivers, Disk Space, and Benchmarks. The compact menu bar panel remains available; its Details button and status-item menu open the Monitor.

The owner's accessible GitHub projects were checked. FastTree's MIT-licensed native scanner/index and PortPeek's MIT-licensed socket parsing approach were reused with attribution. No accessible TMOG source repository was found. Hardware counters and the remaining UI/controllers were implemented in Swift; unavailable hardware readings remain `n/a`. The scanner is compiled and signed inside the app bundle; QA tools are excluded from the app target.

### Local verification

`./build.sh` completed successfully on Apple M4 / macOS 27. The explicit `--monitor-qa` mode exercised all fifteen sections without a crash, rendered them locally, and collected all fourteen hardware inventory categories. Representative Summary, CPU, Processes, Drivers, Installed Apps, scanner and Flight Recorder renders were visually inspected, including the German light appearance. Local live-data images stay outside the repository.

| Check | Observed result |
| --- | --- |
| Live telemetry | 10 CPU cores, 477 readable processes, 52 sensors |
| CPU topology | 6 efficiency / 4 performance cores; separate user/kernel histories |
| Power and frequency | CPU 0.966 W, GPU 0.027 W, ANE 0 W in one sample; 11 frequency sensors; memory pressure Normal |
| Connections | 243 socket records, including process/protocol/endpoint information |
| Services / apps / drivers | 916 service entries, 96 app bundles, 414 driver/extension entries |
| Scanner | Two generated fixture files, 24 KiB total; drill-down, search and saved-index restore succeeded |
| Flight Recorder | Three actual frames recorded, JSON round trip and replay succeeded |
| Startup / services | Generated user launch agent bootstrapped, disabled/enabled and booted out successfully |
| Process action | Only the QA-owned temporary sleep process was terminated |
| App removal | Only the QA-created temporary app was moved to Trash and cleaned up |
| Settings | Settings and Monitor windows were both visible after opening Settings |
| CPU benchmark | 2,909.6 single-core / 23,546.3 multi-core Mops/s |
| GPU benchmark | 487.1 GFLOP/s for the included Metal workload |
| Disk benchmark | 2,835.4 MB/s write / 4,576.5 MB/s read for the temporary 64 MiB file |

Benchmark results are workload-specific measurements, not standardized or comparable to Geekbench scores. APFS and storage caching can influence disk results. QA fixture changes were cleaned up; existing benchmark and scanner histories were restored.

### CPU measurement and remaining limits

Process CPU time was measured with `getrusage` over ten-second wall-clock intervals, expressed as a percentage of one core. With the full Monitor open: **6.77% CPU**. With Monitor closed and recording stopped: **0.75% CPU**. These are single local measurements with the menu bar timer still active. The historical under-1% goal is not achieved with the full Monitor open; further optimization remains.

DRAM energy on this macOS version, NPU/media active residency where no channel is exposed, and restricted per-process GPU/NPU/private-memory/network counters show `n/a`. CPU/GPU frequency tables are validated against the exposed residency states; unsupported chips do not get guessed frequency values. Some system processes are inaccessible without additional privileges and cannot provide all process details.

The internet benchmark and combined score were not executed in QA. Administrator-password flows, changes to real system services, full-volume scans, macOS 14 compatibility at runtime, and other Apple Silicon chip families were not exercised. Destructive QA actions were confined to generated fixtures. No additional unit tests were added.

## Smooth telemetry charts (2026-10-09)

Monitor, replay, panel and overlay line charts now use monotone interpolation, which rounds the transitions without the overshoot of an unrestricted spline. A shared chart modifier gives each chart a fixed horizontal history span and animates new samples and domain movement over 850 ms. This removes the old explicit animation suppression and initial per-sample horizontal rescaling. Animations are scoped to charts, respect Reduce Motion, and introduce no additional sampling or display timers. Overlay sparklines remain conditional on the existing setting.

`./build.sh` succeeded and the app was ad-hoc signed. This pass did not repeat the full management-action QA or remeasure CPU; the earlier CPU figures do not characterize animated charts. Perceptual smoothness across displays is not established by the build check.

## Native chart renderer and release 1.2.0 (2026-10-10)

The previous Swift Charts animation pass caused substantial UI overhead: the running Summary process list showed approximately 47% CPU during inspection (an instantaneous reading, not a controlled average). It is superseded by cached Core Animation shape layers. Paths are rebuilt once per sample and translated by the compositor; there is no per-frame SwiftUI mark layout. Shape-preserving cubic interpolation retains each measured point and splits missing readings. Monitor charts show a one-minute viewport, a subdued grid and lightly tinted area. Overlay charts remain line-only and conditional on the sparkline setting. Reduce Motion disables scrolling animations.

The new build was launched and its Summary window inspected through accessibility and a live screenshot. A separate 20-second process CPU-time measurement with Summary visible reported **5.20% of one core**. This does not establish an under-1% open-window result or a guaranteed frame rate. The earlier 850 ms Swift Charts implementation and its performance assumptions no longer apply.

The release build reports version 1.2.0. Both the executable and bundled scanner report arm64. `codesign --verify --deep --strict` passed. Existing release workflows run the single battery-health smoke test; no extra tests were added. Release screenshot capture runs under an isolated preferences domain, waits for real telemetry, and captures only its own Monitor window using `screencapture -l`; it does not capture the desktop or use generated telemetry.

Five 1.2 release screenshots were captured with `screencapture -l` and individually inspected: CPU, GPU, Memory and Apple Silicon in English/Dark, plus CPU in German/Light. They contain the app's telemetry and no personal paths, usernames, device serials or connection endpoints. README galleries reference these new images. The local release zip passed `unzip -t`.
