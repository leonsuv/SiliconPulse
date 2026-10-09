#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
if [[ -f release.config ]]; then source release.config; fi
BUNDLE_ID="${BUNDLE_ID:-io.github.leonsuv.SiliconPulse}"
VERSION="${VERSION:-1.1.0}"
swift build -c release
APP="$ROOT/SiliconPulse.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SiliconPulse "$APP/Contents/MacOS/SiliconPulse"
if [[ -d .build/release/SiliconPulse_SiliconPulse.bundle ]]; then cp -R .build/release/SiliconPulse_SiliconPulse.bundle "$APP/Contents/Resources/"; fi
python3 - "$APP/Contents/Resources" <<'PYLOC'
import json, pathlib, sys
root = pathlib.Path.cwd()
resources = pathlib.Path(sys.argv[1])
catalog = json.loads((root / "SiliconPulse/Resources/Localizable.xcstrings").read_text())
for language in ("en", "de"):
    directory = resources / f"{language}.lproj"
    directory.mkdir(parents=True, exist_ok=True)
    lines = []
    for key, entry in sorted(catalog.get("strings", {}).items()):
        value = key
        if language != catalog.get("sourceLanguage", "en"):
            localized = entry.get("localizations", {}).get(language, {})
            value = localized.get("stringUnit", {}).get("value", key)
        lines.append(f"{json.dumps(key, ensure_ascii=False)} = {json.dumps(value, ensure_ascii=False)};")
    (directory / "Localizable.strings").write_text("\n".join(lines) + "\n")
PYLOC
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SiliconPulse</string>
<key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
<key>CFBundleName</key><string>SiliconPulse</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>${VERSION}</string>
<key>CFBundleShortVersionString</key><string>${VERSION}</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
clang -O3 -std=c11 -mmacosx-version-min=14.0 Native/Scanner/fasttree-scan.c -o "$APP/Contents/Resources/siliconpulse-scan" -lpthread
codesign --force --sign - "$APP/Contents/Resources/siliconpulse-scan"
cp Native/Scanner/LICENSE "$APP/Contents/Resources/FastTree-LICENSE.txt"
cp SiliconPulse/Workbench/PortPeek-LICENSE.txt "$APP/Contents/Resources/PortPeek-LICENSE.txt"
cp Tools/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
