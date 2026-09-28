#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP="$(pwd)/SiliconPulse.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SiliconPulse "$APP/Contents/MacOS/SiliconPulse"
if [ -d .build/release/SiliconPulse_SiliconPulse.bundle ]; then cp -R .build/release/SiliconPulse_SiliconPulse.bundle "$APP/Contents/Resources/"; fi
cp -R SiliconPulse/Resources/de.lproj "$APP/Contents/Resources/"
cp -R SiliconPulse/Resources/en.lproj "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict><key>CFBundleExecutable</key><string>SiliconPulse</string><key>CFBundleIdentifier</key><string>com.example.SiliconPulse</string><key>CFBundleName</key><string>SiliconPulse</string><key>CFBundlePackageType</key><string>APPL</string><key>CFBundleVersion</key><string>1</string><key>CFBundleShortVersionString</key><string>1.0</string><key>LSUIElement</key><true/><key>LSMinimumSystemVersion</key><string>14.0</string></dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
