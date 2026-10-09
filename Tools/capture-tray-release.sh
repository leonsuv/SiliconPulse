#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
STAGING="$(mktemp -d /tmp/SiliconPulse-tray-release.XXXXXX)"
ditto SiliconPulse.app "$STAGING/SiliconPulse.app"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier io.github.leonsuv.SiliconPulse.Capture.$$" "$STAGING/SiliconPulse.app/Contents/Info.plist"
codesign --force --deep --sign - "$STAGING/SiliconPulse.app" >/dev/null
sed 's/optionOnScreenOnly/optionAll/g' Tools/screenshot-window-id.swift > "$STAGING/window-id.swift"
"$STAGING/SiliconPulse.app/Contents/MacOS/SiliconPulse" --release-screenshot --release-screenshot-en "--ui-snapshot=$STAGING/render" > "$STAGING/capture.log" 2>&1 &
CAPTURE_PID=$!
trap 'kill "$CAPTURE_PID" 2>/dev/null || true' EXIT
sleep 8
mkdir -p docs/assets/screenshots
for attempt in 1 2 3; do
  if WID="$(swift "$STAGING/window-id.swift" panel "$CAPTURE_PID")"; then
    if screencapture -x -o -l "$WID" "$ROOT/docs/assets/screenshots/tray-overview-1-2-1.png"; then
      echo "Captured own panel $WID"
      exit 0
    fi
  fi
  sleep 2
done
exit 2
