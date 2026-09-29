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
