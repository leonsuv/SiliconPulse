# SiliconPulse 1.1 interface validation

Validated on an Apple M4 Mac running macOS 27 with Swift 6.4 Command Line Tools.

- Release bundle builds, passes strict ad-hoc signature verification, and declares macOS 14 as its binary deployment target.
- `scripts/check-interface.sh` captures 23 production-view renders with real local telemetry: compact 420×820, wide 760×900, performance details, Edit mode, all seven settings sections in light/dark, and minimum 340×420.
- Live UI checks verified overview card expansion, Performance filtering, Edit mode showing every section, pinning, and navigation in the new settings sidebar. WindowServer confirmed that the pinned panel remains on screen with Settings open.
- PNG dimensions and successful completion are checked; conflicting Auto Layout constraints fail verification. Layout, typography, contrast, and clipping are also inspected visually.
- Snapshot mode restores the app preference domain on completion. Run it with SiliconPulse closed.
- The checked-in screenshots come from these native renders, without simulated readings or desktop compositing.

The local Command Line Tools installation does not include XCTest, so `swift test` cannot run locally. GitHub's Build and Release workflows run the existing battery-health test with Xcode. The Release workflow now requires tests to pass before publication.

macOS 14 runtime behavior has not been tested locally. Sensor availability depends on hardware and macOS private telemetry interfaces. This UI release does not change telemetry collection or require new permissions.
