# SiliconPulse

Live Apple Silicon telemetry in your menu bar.



[![Latest release](https://img.shields.io/github/v/release/leonsuv/SiliconPulse?display_name=tag)](https://github.com/leonsuv/SiliconPulse/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/leonsuv/SiliconPulse/total)](https://github.com/leonsuv/SiliconPulse/releases)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple&logoColor=white)](https://github.com/leonsuv/SiliconPulse)
[![Apple Silicon](https://img.shields.io/badge/Architecture-Apple%20Silicon-111111)](https://github.com/leonsuv/SiliconPulse)
[![MIT License](https://img.shields.io/github/license/leonsuv/SiliconPulse)](LICENSE)
[![Build](https://github.com/leonsuv/SiliconPulse/actions/workflows/build.yml/badge.svg)](https://github.com/leonsuv/SiliconPulse/actions/workflows/build.yml)

SiliconPulse is a native macOS menu bar monitor for Apple Silicon. Its dashboard and optional overlay show battery, CPU, GPU, power, memory, storage, network and thermal readings.

- Telemetry requires no sudo or privileged helper. Optional system-setting changes may require macOS administrator authorization.
- SwiftUI, AppKit and Core Animation; no third-party packages.
- The dashboard samples while visible. When it is closed, the app samples the battery and selected menu bar metric every five seconds.


## Monitor window

Choose **Details** in the panel or **Open monitor…** in the status menu to open the resizable monitor. The menu bar app remains available.

- Summary and performance views for CPU, E/P cores, GPU, memory, storage, network, energy and temperatures.
- Searchable process list/tree, user totals and process details; confirmed termination of your own processes.
- Hardware inventory, startup agents and launchd services. Protected macOS services cannot be changed.
- Live sensors with minimum/maximum, Apple Silicon core histories and available frequency/residency readings.
- Local recording, JSON export, timeline and replay; TCP, UDP and local IPC connection inspection.
- Installed applications, on-demand sizes, related files and confirmed move to Trash; driver inventory and Finder actions.
- Folder analysis with treemap/circles, search, largest files, file types and saved scans.
- CPU, Metal GPU and disk benchmarks, an optional internet test and an explicitly nonstandard SiliconPulse index.

Availability depends on macOS and hardware. Missing readings show **n/a**; there are no sample values or Pro gates. Internet tests transfer data and run only when started explicitly.

Monitor sampling stops when its window closes or minimizes. An explicitly started recording continues with the window closed. Telemetry needs no administrator access; changing system-wide services or Low Power Mode may require macOS administrator authorization.

Disk scanning incorporates the MIT-licensed native scanner from [FastTree](https://github.com/leonsuv/FastTree); socket inspection uses approaches from [PortPeek](https://github.com/leonsuv/PortPeek). All private IOReport calls remain in one file. CLPC counter identifiers and DVFS protocol facts follow the documented [macmon research](https://github.com/vladkens/macmon); no macmon source code is incorporated.

## Screenshots

![SiliconPulse 1.2 CPU performance monitor](docs/assets/screenshots/monitor-cpu-1-2.png)

| GPU performance | Memory | Apple Silicon cores |
|---|---|---|
| ![GPU](docs/assets/screenshots/monitor-gpu-1-2.png) | ![Memory](docs/assets/screenshots/monitor-memory-1-2.png) | ![Apple Silicon](docs/assets/screenshots/monitor-silicon-1-2.png) |

[German interface in Light Mode](docs/assets/screenshots/monitor-cpu-de-1-2.png). Captured from SiliconPulse's own windows with real telemetry; readings vary by Mac and time.

## Install

1. Download [SiliconPulse-1.2.0.zip](https://github.com/leonsuv/SiliconPulse/releases/latest/download/SiliconPulse-1.2.0.zip) from GitHub Releases.
2. Unzip it and move `SiliconPulse.app` to `/Applications`.
3. The app is ad-hoc signed and not notarized. On first launch, Control-click it and choose **Open**, or use **System Settings → Privacy & Security → Open Anyway**. Alternatively, remove quarantine yourself:

   ```sh
   xattr -dr com.apple.quarantine /Applications/SiliconPulse.app
   ```

## Build from source

Requirements: an Apple Silicon Mac, macOS 14 or later, and Swift 5.9 or later.

```sh
git clone https://github.com/leonsuv/SiliconPulse.git
cd SiliconPulse
./build.sh
open SiliconPulse.app
```

The script builds the Swift package, assembles an `LSUIElement` app bundle, copies its local icon and language resources, and ad-hoc signs the app. App Sandbox is not enabled.

## Use SiliconPulse

The overview shows the key readings. Expand a card for details, or select Performance, Energy, or System. Pinned panels use two columns at widths of 560 points and above.


- Click the status item to open or close the dashboard. Settings lets you choose which readings appear in the menu bar.
- Pin the panel to keep it visible across app changes and Spaces. Drag its header to move it and use the resize handle to change its size.
- Use Edit mode to reorder cards or change which cards appear. Click a card header to expand or collapse it.
- Open Settings from the gear, the status item context menu, or Overlay Settings in that menu while the overlay is active.
- Use the dashed rectangle to turn on the click-through overlay. Its default shortcut is **Control–Option–O** and can be changed under Settings → Overlay.
- **Copy snapshot** copies a short summary; **Quit** exits the app.

## Metrics and data sources

| Metric | Source | Notes |
|---|---|---|
| Battery charge, state, capacities, cycle count, voltage, current and temperature | IOKit `AppleSmartBattery` registry properties | Health is NominalChargeCapacity ÷ DesignCapacity. Missing values show `n/a`. |
| CPU load and per-core use | Mach `host_processor_info`; `hw.perflevel*` sysctls | Cluster names and counts come from the system. |
| GPU load, renderer, tiler, memory and core count | IOKit `AGXAccelerator` registry properties | Missing services or keys show `n/a`. |
| CPU, GPU, ANE and DRAM power | Private `IOReport` symbols loaded dynamically | Missing symbols or counters show `n/a`. |
| Memory use, wired, compression, cache and pressure | Mach VM statistics and memory pressure notifications | Uses Activity Monitor style accounting. |
| Boot volume space | Foundation volume resource values | SMART status is read locally with `diskutil`. |
| Disk read/write throughput and IOPS | IOKit `IOBlockStorageDriver` statistics | A first sample or reset counter has no rate. |
| Network throughput | `getifaddrs` interface counters | Counts `en*` interfaces and does not enumerate local interface IP addresses. |
| Wi-Fi signal, channel and link rate | CoreWLAN | SSID is not read. Values depend on the Wi-Fi interface. |
| Temperature and fan speed | Model-dependent HID and AppleSMC registry interfaces | Readings can be unavailable and can be disabled in Advanced settings. |
| Process CPU and memory | `proc_listallpids` and `proc_pidinfo` | The process list is sampled only while the dashboard is open. |
| Sleep blockers | IOPM assertion APIs | Reports processes with active power assertions. |
| Thermal state, chip, model, cores, uptime and macOS | `ProcessInfo`, `sysctl` and Foundation | Individual values can be unavailable. |
| Network latency | Optional latency probe | When enabled, sends a TCP request to its configured host. It is off by default. |

`IOReport` and some sensor readers use private, model-dependent interfaces that can change with macOS. SiliconPulse shows `n/a` when a reading is unavailable and does not estimate values.

## Privacy and security

Telemetry stays on the Mac; there are no analytics. Wi-Fi collection does not read SSIDs. The hardware inventory can display device identifiers supplied by macOS, and connection inspection displays local and remote endpoints. These details are exported only when you request an export. The optional latency probe and explicitly started internet benchmark make network requests. Notifications are local. Routine telemetry needs no sudo or privileged helper; changing system-wide services or Low Power Mode can require administrator authorization.

## Compatibility

SiliconPulse requires macOS 14 or later and Apple Silicon. It was built and exercised on Apple Silicon running macOS 27.0; other supported releases have not all been tested. Battery keys, Wi-Fi information, temperature, fans, private IOReport channels and Bluetooth battery data vary by model and OS. Intel Macs are not supported.

## Performance

With the 1.2 native chart renderer, the open Summary window used **5.20% of one CPU core** over a 20-second CPU-time measurement on Apple M4 / macOS 27. This is one local observation, not a cross-device guarantee. Measurements from older builds are retained in [QA_REPORT.md](QA_REPORT.md); they do not describe this release. The monitor stops sampling when closed or minimized unless you explicitly start a recording.

## FAQ

**Why does a metric show `n/a`?** Its registry key, private counter or system interface may be unavailable on this Mac or macOS version. The app does not invent values.

**Why is CPU power sometimes zero or unavailable?** IOReport channel names and counters vary. Missing channels show `n/a`; a counter that does not change can report zero.

**Why is the download not notarized?** The release zip is ad-hoc signed. Notarization requires an Apple Developer account and is not part of this release.

**How do I quit?** Choose **Quit SiliconPulse** from the status item menu or use **Quit** in the panel footer.

**How do I reset settings?** Open Settings → Advanced and choose **Reset all settings**. Edit mode also has **Reset layout**.

**Does the overlay work in exclusive full-screen apps?** It uses a macOS floating window. Apps using exclusive full-screen presentation may hide other windows; use borderless or windowed full screen if it is not visible.

## License

SiliconPulse is available under the [MIT License](LICENSE).

## Interface verification

```sh
./build.sh
./scripts/check-interface.sh
```

Renders the compact and wide panels and all seven settings sections in light and dark from the app views. The run restores existing preferences afterward.

[UI validation](docs/UI-VALIDATION.md) · [Changelog](CHANGELOG.md)
