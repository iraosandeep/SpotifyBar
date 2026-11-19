#!/bin/bash
# Builds SpotifyBar.app (menu bar only). Usage: ./build.sh [--install]
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP="build/SpotifyBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/SpotifyBar" "$APP/Contents/MacOS/SpotifyBar"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SpotifyBar</string>
    <key>CFBundleDisplayName</key><string>SpotifyBar</string>
    <key>CFBundleIdentifier</key><string>local.spotifybar</string>
    <key>CFBundleExecutable</key><string>SpotifyBar</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x SpotifyBar 2>/dev/null || true
    rm -rf /Applications/SpotifyBar.app
    cp -R "$APP" /Applications/
    open /Applications/SpotifyBar.app
    echo "Installed to /Applications and launched"
fi
