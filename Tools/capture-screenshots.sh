#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/SiliconPulse.app"
QA_APP="/tmp/SiliconPulse-QA-$$.app"
ditto "$APP" "$QA_APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier io.github.leonsuv.SiliconPulse.QA.$$" "$QA_APP/Contents/Info.plist"
codesign --force --deep --sign - "$QA_APP" >/dev/null
EXECUTABLE="$QA_APP/Contents/MacOS/SiliconPulse"
OUT="$ROOT/docs/assets/screenshots"
WINDOW_ID_SCRIPT="$ROOT/Tools/screenshot-window-id.swift"
DOMAIN="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$QA_APP/Contents/Info.plist")"
BACKUP="/tmp/SiliconPulse-defaults-backup.plist"
PERMISSION_CHECK="/tmp/SiliconPulse-screen-permission.png"
mkdir -p "$OUT"

restore_defaults() {
  if [[ -s "$BACKUP" ]]; then defaults import "$DOMAIN" "$BACKUP" >/dev/null 2>&1 || true; fi
  if [[ -f "$PERMISSION_CHECK" ]]; then unlink "$PERMISSION_CHECK"; fi
}
trap restore_defaults EXIT

defaults export "$DOMAIN" "$BACKUP" >/dev/null 2>&1 || true
defaults write "$DOMAIN" overlay.active -bool false
defaults write "$DOMAIN" panelPinned -bool false
defaults write "$DOMAIN" reopenPinnedAtLaunch -bool false
defaults write "$DOMAIN" showDockIcon -bool false
defaults write "$DOMAIN" panelWidth -float 380
defaults write "$DOMAIN" visibleSections -array Battery Power GPU CPU Memory Disk Network Thermal Processes 'Sleep blockers' System Bluetooth Fans
defaults write "$DOMAIN" expandedSections -array Battery Power GPU CPU Memory Disk Network Thermal Processes 'Sleep blockers' System Bluetooth Fans

if ! screencapture -x "$PERMISSION_CHECK" >/dev/null 2>&1 || [[ ! -s "$PERMISSION_CHECK" ]]; then
  echo "SCREEN_RECORDING_PERMISSION=unavailable"
  exit 3
fi
if ! sips -g pixelWidth -g pixelHeight "$PERMISSION_CHECK" 2>/dev/null | rg -q 'pixelWidth: [1-9][0-9]*'; then
  echo "SCREEN_RECORDING_PERMISSION=blank"
  exit 3
fi
echo "SCREEN_RECORDING_PERMISSION=available"

launch_capture() {
  local name="$1" target="$2" wait_seconds="$3"
  shift 3
  local raw="$OUT/$name.png" final="$OUT/$name.jpg" pid="" wid="" attempt=0
  open -na "$QA_APP" --args "$@" >/tmp/SiliconPulse-screenshot-run.log 2>&1
  pid=0
  while [[ $attempt -lt 14 ]]; do
    sleep 1
    pid="$(swift -e 'import AppKit; let apps=NSRunningApplication.runningApplications(withBundleIdentifier: CommandLine.arguments[1]); print(apps.map { $0.processIdentifier }.max() ?? 0)' "$DOMAIN")"
    wid="$(swift "$WINDOW_ID_SCRIPT" "$target" "$pid" 2>/dev/null || true)"
    if [[ -n "$wid" ]]; then break; fi
    attempt=$((attempt + 1))
  done
  if [[ -z "$wid" ]]; then
    echo "CAPTURE_SKIPPED=$name window-not-found"
    swift -e 'import AppKit; for app in NSRunningApplication.runningApplications(withBundleIdentifier: CommandLine.arguments[1]) { app.forceTerminate() }' "$DOMAIN" >/dev/null 2>&1 || true
    return 0
  fi
  sleep "$wait_seconds"
  if ! screencapture -x -l "$wid" "$raw" >/dev/null 2>&1 || [[ ! -s "$raw" ]]; then
    echo "CAPTURE_SKIPPED=$name capture-failed"
  else
    sips -s format jpeg -s formatOptions 76 -Z 1800 "$raw" --out "$final" >/dev/null
    if [[ "$(stat -f %z "$final")" -gt 409600 ]]; then
      sips -s formatOptions 62 -Z 1400 "$final" --out "$final" >/dev/null
    fi
    if [[ "$(stat -f %z "$final")" -le 409600 ]]; then
      echo "CAPTURED=$name.jpg bytes=$(stat -f %z "$final") window=$wid"
    else
      echo "CAPTURE_SKIPPED=$name too-large"
    fi
    unlink "$raw"
  fi
  swift -e 'import AppKit; for app in NSRunningApplication.runningApplications(withBundleIdentifier: CommandLine.arguments[1]) { app.forceTerminate() }' "$DOMAIN" >/dev/null 2>&1 || true
  sleep 1
}

BASE=(--release-screenshot)
launch_capture panel-overview panel 4 "${BASE[@]}" --release-screenshot-panel
swift "$ROOT/Tools/crop-at-a-glance.swift" "$OUT/panel-overview.jpg" "$OUT/at-a-glance.jpg"
for card in Battery Power GPU CPU Memory Disk Network Thermal Processes "Sleep blockers" System Bluetooth Fans; do
  slug="$(printf '%s' "$card" | tr '[:upper:] ' '[:lower:]-')"
  launch_capture "card-$slug" panel 4 "${BASE[@]}" "--release-screenshot-card=$card"
done
launch_capture panel-pinned-compact panel 4 "${BASE[@]}" --release-screenshot-pinned=compact
launch_capture panel-pinned-large panel 4 "${BASE[@]}" --release-screenshot-pinned=large
launch_capture panel-edit-mode panel 2 "${BASE[@]}" --release-screenshot-edit

for tab in 0 1 2 3 4 5 6; do
  launch_capture "settings-tab-$tab" settings 2 "--settings-qa-tab=$tab" --release-screenshot-en
done
launch_capture panel-overview-de panel 4 "${BASE[@]}" --release-screenshot-de --release-screenshot-panel
launch_capture settings-general-de settings 2 --settings-qa-tab=0 --release-screenshot-de

for style in list bar; do
  for backdrop in bright dark; do
    launch_capture "overlay-$style-$backdrop" overlay 4 "${BASE[@]}" "--release-screenshot-overlay=$style-$backdrop"
  done
done
