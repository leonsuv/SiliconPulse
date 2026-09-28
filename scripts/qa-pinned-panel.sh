#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/SiliconPulse.app"
BIN="$APP/Contents/MacOS/SiliconPulse"
LOG="/tmp/siliconpulse-pin-qa.log"
BUNDLE="com.example.SiliconPulse"
CHECKER="$ROOT/scripts/check-panel-window.swift"
PREVIOUS_PIN="$(defaults read "$BUNDLE" panelPinned 2>/dev/null || echo false)"
PREVIOUS_REOPEN="$(defaults read "$BUNDLE" reopenPinnedAtLaunch 2>/dev/null || echo true)"
PID=""

stop_app() {
    if [[ -n "$PID" ]] && kill -0 "$PID" 2>/dev/null; then
        kill -TERM "$PID" 2>/dev/null || true
        wait "$PID" 2>/dev/null || true
    fi
    PID=""
}
restore_preferences() {
    stop_app
    local pin_bool="NO" reopen_bool="NO"
    if [[ "$PREVIOUS_PIN" == "1" || "$PREVIOUS_PIN" == "true" || "$PREVIOUS_PIN" == "YES" ]]; then pin_bool="YES"; fi
    if [[ "$PREVIOUS_REOPEN" == "1" || "$PREVIOUS_REOPEN" == "true" || "$PREVIOUS_REOPEN" == "YES" ]]; then reopen_bool="YES"; fi
    defaults write "$BUNDLE" panelPinned -bool "$pin_bool"
    defaults write "$BUNDLE" reopenPinnedAtLaunch -bool "$reopen_bool"
}
trap restore_preferences EXIT
pkill -x SiliconPulse 2>/dev/null || true
sleep 1

launch() {
    local mode="$1"
    "$BIN" $mode > "$LOG" 2>&1 &
    PID=$!
    sleep 3
}

check_panel() {
    local stage="$1"
    local result
    result="$(swift "$CHECKER" 2>/dev/null || true)"
    if [[ "$result" == "CGWINDOW_PANEL_ON_SCREEN" ]]; then
        echo "$stage: $result"
    else
        echo "$stage: $result; app state log follows"
        tail -n 12 "$LOG" || true
    fi
}

# Deactivation: launch pinned, activate Finder, wait two seconds, then query WindowServer.
defaults write "$BUNDLE" panelPinned -bool true
defaults write "$BUNDLE" reopenPinnedAtLaunch -bool true
launch "--pin-qa"
osascript -e 'tell application "Finder" to activate'
sleep 2
check_panel "Finder deactivation"
tail -n 8 "$LOG" || true
stop_app

# Escape is delivered to the panel's key handler through the explicit QA hook.
launch "--pin-qa --pin-qa-escape"
sleep 1
check_panel "Escape"
tail -n 8 "$LOG" || true
stop_app

# Showing Settings must leave a pinned panel visible.
launch "--pin-qa --pin-qa-settings"
sleep 2
check_panel "Settings open"
tail -n 8 "$LOG" || true
stop_app

# Relaunch with no force-pin hook: persisted pin state must reopen the saved panel.
launch "--pin-qa-relaunch"
check_panel "Relaunch"
tail -n 8 "$LOG" || true
