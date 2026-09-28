# SiliconPulse

A lightweight native macOS menu bar monitor for Apple Silicon Macs running macOS 14 or later. SiliconPulse uses public system interfaces where available and falls back to `n/a` when a reading is unavailable. Sampling runs at one second while the panel is visible and at five seconds for the menu bar label.

## Features

- Battery charge, health, capacities, electrical readings, adapter state, and power history
- CPU and GPU utilization, per-core activity, memory pressure, disk activity, and temperatures
- Energy estimates, Wi-Fi link details, Bluetooth battery levels, fans, process ranking, and sleep blockers
- Resizable, pinnable telemetry panel with collapsible cards and live sparklines
- Reorderable cards and visibility controls in Edit mode
- Configurable menu bar metrics, units, history, alerts, and launch at login
- English and German interface

## Panel controls

Click the status item to open or close the panel. Use the pin button in the header to keep it on screen; a pinned panel can be moved by dragging its background and resized from its edges or the lower-right grip. Click the pin again to return it beneath the menu bar. When pinned, the header close button hides the panel.

Use the pencil button to enter Edit mode. Cards collapse to their headers so they are easy to rearrange. Drag the handle to reorder, or use the up/down controls. The eye button hides or restores a card. Hidden cards are omitted from normal view and their collectors pause. Reset layout restores the default ordering, visibility, and expanded cards.

## Settings

Open Settings from the gear button or the status item's right-click menu.

- **General:** login startup, Dock icon, language, panel opacity, refresh rate, history duration, compact rows
- **Menu Bar:** selectable and reorderable metrics, symbol, separator, and preview
- **Sections:** card visibility, order, and default expanded state
- **Units:** temperature, byte units, network bits, and clock format
- **Notifications:** battery, thermal, CPU, memory pressure, disk, SMART, temperature, and Bluetooth thresholds; cooldown and quiet hours
- **Advanced:** optional network latency probe, sensor sources, snapshot controls, settings import/export, reset, and About

## Install

Download `SiliconPulse.zip` from [GitHub Releases](../../releases), unzip it, and move `SiliconPulse.app` into Applications. The app is ad-hoc signed for local launch.

## Build from source

Requires Xcode command line tools and Swift 5.9 or later:

```sh
./build.sh
```

This creates `SiliconPulse.app` in the repository root. There are no third-party dependencies. The app does not require `sudo`, a privileged helper, or `powermetrics`; it reads telemetry through the current user's system APIs.

## Private APIs

IOReport and AppleSMC sensor access are private, version-dependent interfaces. They are isolated in collectors and readings fall back to `n/a` when unavailable. CoreWLAN reads signal and link properties without accessing the SSID. The optional TCP latency probe is disabled by default; when enabled, it connects to the configured IPv4 host on port 443.

## Screenshot

_Screenshot coming soon._

## License

MIT. See [LICENSE](LICENSE).

## Overlay HUD

SiliconPulse also has an optional click-through telemetry HUD for games and full-screen apps. Toggle it with **Control–Option–O** or from the status item's right-click menu. Configure metrics, list or bar layout, colors, opacity, sample interval, display, anchor, offsets, and warning thresholds in Settings → Overlay. Use **Move overlay…** to position it; press Return, Escape, or Done to finish. The HUD state and position are saved between launches. Its sampling loop runs only while the HUD is visible and collects the selected metrics.

Overlay metrics are sampled only while the HUD is on screen. The HUD can be positioned with corner, edge-center, and screen-center anchors, or dragged in the temporary Move mode. It defaults to Control–Option–O; Settings includes alternate global shortcut presets. Use the settings preview to see a five-second sample. On macOS, apps using true exclusive fullscreen can cover the HUD; borderless-windowed or windowed-fullscreen modes keep it visible.
