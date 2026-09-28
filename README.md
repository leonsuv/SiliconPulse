# SiliconPulse

A small native macOS menu bar monitor for Apple Silicon (macOS 14+). The popover reports battery health and charge, CPU per-core activity, thermal state, memory, boot volume, network throughput, Wi-Fi signal and link rate, and top processes. It samples on demand while open and keeps the menu bar value lightweight.

## Install

Download `SiliconPulse.zip` from [GitHub Releases](../../releases), unzip it, and move `SiliconPulse.app` into Applications. The app is ad-hoc signed for local launch.

## Build from source

Requires Xcode command line tools and Swift 5.9 or later. Run:

```sh
./build.sh
```

This creates `SiliconPulse.app` in the repository root. No third-party packages, sudo, privileged helper, or `powermetrics` are used. The app reads battery and host telemetry through macOS frameworks. IOReport is private and version-dependent; missing symbols or channels display as `n/a`.

## Features

- Battery health calculated as NominalChargeCapacity / DesignCapacity
- Power counters and CPU/GPU frequency residency where available
- CPU load history and per-core E/P gauges
- Memory, disk, network, Wi-Fi, thermal, and process cards
- Settings for menu bar metric, refresh interval, temperature units, and launch at login
- English and German localization

## Screenshot

_Screenshot coming soon._

## License

MIT. See [LICENSE](LICENSE).
