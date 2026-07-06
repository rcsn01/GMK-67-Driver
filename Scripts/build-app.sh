#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

swift build --product gmk67
swift build --product GMK67App

APP="$ROOT/dist/GMK67.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
HELPER="$RESOURCES/Helper"

rm -rf "$APP"
mkdir -p "$MACOS" "$HELPER" "$RESOURCES/Resources/vendor"

cp "$ROOT/.build/debug/GMK67App" "$MACOS/GMK67"
cp "$ROOT/.build/debug/gmk67" "$HELPER/gmk67"
cp "$ROOT/Resources/vendor/KeyboardLayout.xml" "$RESOURCES/Resources/vendor/KeyboardLayout.xml"
cp "$ROOT/Resources/vendor/device.xml" "$RESOURCES/Resources/vendor/device.xml"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>GMK67</string>
    <key>CFBundleIdentifier</key>
    <string>local.gmk67.driver</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>GMK67</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Local user-space GMK67 driver tools.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSInputMonitoringUsageDescription</key>
    <string>GMK67 needs Input Monitoring permission to open the keyboard USB HID interface for RGB lighting and key remapping.</string>
</dict>
</plist>
PLIST

chmod +x "$MACOS/GMK67" "$HELPER/gmk67"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP" >/dev/null
  echo "Ad-hoc signed $APP"
fi

echo "Built $APP"
