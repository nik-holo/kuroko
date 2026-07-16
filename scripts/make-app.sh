#!/bin/bash
# Builds kuroko and assembles a runnable .app bundle in ./dist.
# Usage: scripts/make-app.sh [--install]   (--install copies it to /Applications)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
APP="dist/kuroko.app"

swift build -c release

if [[ ! -f Resources/kuroko.icns ]]; then
    swift scripts/genicons.swift
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/kuroko "$APP/Contents/MacOS/kuroko"
cp Resources/kuroko.icns "$APP/Contents/Resources/kuroko.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>kuroko</string>
    <key>CFBundleIdentifier</key><string>dev.nik.kuroko</string>
    <key>CFBundleName</key><string>kuroko</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>kuroko</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS lets it run locally without a Developer ID.
codesign --force --deep -s - "$APP"

echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    rm -rf /Applications/kuroko.app
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/kuroko.app"
fi
