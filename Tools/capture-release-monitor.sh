#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGING="$(mktemp -d /tmp/SiliconPulse-release-capture.XXXXXX)"
APP="$STAGING/SiliconPulse.app"
ditto "$ROOT/SiliconPulse.app" "$APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier io.github.leonsuv.SiliconPulse.ReleaseCapture.$$" "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP" >/dev/null
"$APP/Contents/MacOS/SiliconPulse" "--monitor-release-capture=$ROOT/docs/assets/screenshots"
