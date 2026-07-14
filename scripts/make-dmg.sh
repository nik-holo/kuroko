#!/bin/bash
# Builds a distributable DMG: dist/boomerpix-<version>.dmg
# The DMG contains boomerpix.app and an Applications shortcut (drag to install).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="0.1.0"
DMG="dist/boomerpix-${VERSION}.dmg"

./scripts/make-app.sh

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R dist/boomerpix.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "boomerpix" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo "Built $DMG"
echo "Note: unsigned build — recipients must right-click the app > Open on first launch,"
echo "or run: xattr -d com.apple.quarantine /Applications/boomerpix.app"
