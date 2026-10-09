#!/bin/bash
# Capture only the already-open SiliconPulse Monitor, never the desktop.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NAME="${1:?Usage: capture-monitor-window.sh screenshot-name}"
if [[ ! "$NAME" =~ ^[a-z0-9-]+$ ]]; then exit 2; fi
PID="$(swift -e 'import AppKit; print(NSRunningApplication.runningApplications(withBundleIdentifier: "io.github.leonsuv.SiliconPulse").map { $0.processIdentifier }.max() ?? 0)')"
WID="$(swift "$ROOT/Tools/screenshot-window-id.swift" monitor "$PID")"
mkdir -p "$ROOT/docs/assets/screenshots"
screencapture -x -o -l "$WID" "$ROOT/docs/assets/screenshots/$NAME.png"
echo "Captured $NAME.png from SiliconPulse window $WID"
