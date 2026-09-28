# SiliconPulse

SiliconPulse is a lightweight native macOS menu bar monitor for Apple Silicon Macs running macOS 14 or later. It samples only while the popover is open; when closed it refreshes battery and selected menu bar metrics every five seconds. The app does not use sudo, a privileged helper, or `powermetrics`.

## Features

- Battery charge, health, capacity, electrical readings, adapter state, and battery power history
- CPU and GPU utilization, per-core activity, memory pressure and paging, power telemetry, and temperatures
- Disk capacity, SMART status, disk throughput and IOPS, mounted removable volumes
- Network rates, local interface details, Wi-Fi signal and link properties, optional TCP latency probe
- Bluetooth device battery levels, fans when exported by the system, process CPU and memory ranking
- Sleep blockers, model and system details, collapsible and reorderable sections
- Configurable menu bar metrics, history duration, units, compact rows, login startup, local alerts, and copyable snapshot
- English and German interface strings

## Install

Download `SiliconPulse.zip` from [GitHub Releases](../../releases), unzip it, and move `SiliconPulse.app` into Applications. The app is ad-hoc signed for local launch.

## Build from source

Requires Xcode command line tools and Swift 5.9 or later. Run:

```sh
./build.sh
```

This creates `SiliconPulse.app` in the repository root. The project uses only Apple frameworks and ships no third-party dependencies.

## Private APIs used

IOReport provides Apple Silicon energy channels, and IOHIDEventSystem provides sensor readings. Both interfaces are private and version-dependent, are loaded dynamically, and fall back to `n/a` when symbols or readings are unavailable. AppleSMC fan readings are best-effort and the fan card appears only when fan properties are exposed. The app does not request serial numbers, SSIDs, public IP information, or administrator privileges.

The optional latency probe is off by default. Enabling it makes a TCP connection request to `1.1.1.1:443` to measure connection time.

## Screenshot

_Screenshot coming soon._

## License

MIT. See [LICENSE](LICENSE).
