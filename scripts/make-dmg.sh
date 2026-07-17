#!/bin/bash
# Builds a distributable DMG: dist/kuroko-<version>.dmg
# The DMG opens as a styled Finder window: brand background with a gradient
# arrow, app on the left, Applications shortcut on the right.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
DMG="dist/kuroko-${VERSION}.dmg"
VOL="kuroko"

./scripts/make-app.sh
if [[ ! -f Resources/dmg-background.png ]]; then
    swift scripts/gendmgbg.swift
fi

# detach leftovers from previous runs so the volume gets its proper name
for vol in "/Volumes/$VOL" "/Volumes/$VOL "*; do
    [[ -d "$vol" ]] && hdiutil detach "$vol" >/dev/null 2>&1 || true
done

STAGE="$(mktemp -d)"
RW_DMG="$(mktemp -d)/rw.dmg"
MOUNT_POINT=""
trap 'rm -rf "$STAGE" "$(dirname "$RW_DMG")"; [[ -n "$MOUNT_POINT" ]] && hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true' EXIT

cp -R dist/kuroko.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"
cp Resources/dmg-background.png "$STAGE/.background/background.png"

hdiutil create -volname "$VOL" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW_DMG" >/dev/null
MOUNT_POINT="$(hdiutil attach "$RW_DMG" -readwrite -noverify -noautoopen | grep -oE '/Volumes/.+$' | head -1)"
VOLNAME="$(basename "$MOUNT_POINT")"
sleep 2  # let Finder register the new disk before scripting it

# Finder window layout (may prompt once for Finder automation permission)
osascript <<EOF
tell application "Finder"
    tell disk "$VOLNAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 548}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 104
        set text size of viewOptions to 12
        set background picture of viewOptions to file ".background:background.png"
        set position of item "kuroko.app" of container window to {165, 200}
        set position of item "Applications" of container window to {495, 200}
        update without registering applications
        delay 1
        close
    end tell
end tell
EOF

# Volume icon must go in AFTER the Finder scripting above — Finder's layout
# pass deletes .VolumeIcon.icns and clears the custom-icon flag.
cp Resources/kuroko.icns "$MOUNT_POINT/.VolumeIcon.icns"
SetFile -a C "$MOUNT_POINT"

sync
hdiutil detach "$MOUNT_POINT" >/dev/null
MOUNT_POINT=""
rm -f "$DMG"
hdiutil convert "$RW_DMG" -format UDZO -o "$DMG" >/dev/null

# custom icon on the .dmg file itself (lives in the resource fork: survives
# local use, AirDrop and zips, but a plain HTTP download strips it)
swift scripts/seticon.swift Resources/kuroko.icns "$DMG"

# stable-name copy for the permanent download link:
# github.com/nik-holo/kuroko/releases/latest/download/kuroko.dmg
cp "$DMG" dist/kuroko.dmg

echo "Built $DMG (+ dist/kuroko.dmg for the stable release-asset link)"
echo "Note: unsigned build — after macOS blocks the first launch, recipients allow it"
echo "via System Settings > Privacy & Security > 'Open Anyway',"
echo "or run: xattr -d com.apple.quarantine /Applications/kuroko.app"
