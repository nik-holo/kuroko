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

SPARKLE_FRAMEWORK=".build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
    echo "error: Sparkle framework not found at $SPARKLE_FRAMEWORK (run swift build first)" >&2
    exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp .build/release/kuroko "$APP/Contents/MacOS/kuroko"
cp Resources/kuroko.icns "$APP/Contents/Resources/kuroko.icns"
cp -R "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"

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
    <key>SUFeedURL</key><string>https://kuroko.holo.red/appcast.xml</string>
    <key>SUPublicEDKey</key><string>QTo3ixAh4FMNAf8ZIDqq2/GGftzrypwf0u2mWxGBigE=</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>NSServices</key>
    <array>
        <dict>
            <key>NSMenuItem</key>
            <dict><key>default</key><string>Convert with kuroko</string></dict>
            <key>NSMessage</key><string>convertFiles</string>
            <key>NSSendFileTypes</key>
            <array><string>public.image</string></array>
        </dict>
    </array>
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
