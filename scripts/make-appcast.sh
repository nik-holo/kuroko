#!/bin/bash
# Generates docs/appcast.xml for Sparkle auto-updates, signing the current
# version's DMG with the EdDSA key from the login Keychain (created once via
# Sparkle's generate_keys). Run after make-dmg.sh, before deploying the site.
# Release notes come from the matching "## <version>" section of CHANGELOG.md.
# The appcast advertises only the newest version — that's all Sparkle needs.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
DMG="dist/kuroko-${VERSION}.dmg"
SIGN_UPDATE=".build/artifacts/sparkle/Sparkle/bin/sign_update"

[[ -f "$DMG" ]] || { echo "error: $DMG not found — run scripts/make-dmg.sh first" >&2; exit 1; }
[[ -x "$SIGN_UPDATE" ]] || { echo "error: sign_update not found — run swift build first" >&2; exit 1; }

SIGNATURE_ATTRS="$("$SIGN_UPDATE" "$DMG")"   # -> sparkle:edSignature="..." length="..."
PUB_DATE="$(date -u +"%a, %d %b %Y %H:%M:%S +0000")"

# Release notes: the "## ${VERSION}" section of CHANGELOG.md, rendered to a
# small self-contained HTML fragment that Sparkle shows inline in the update
# dialog (instead of loading the GitHub release page in its web view).
NOTES_HTML="$(python3 scripts/changelog-html.py "$VERSION")" \
    || { echo "error: no '## ${VERSION}' section in CHANGELOG.md" >&2; exit 1; }

cat > docs/appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>kuroko</title>
    <link>https://kuroko.holo.red/</link>
    <item>
      <title>kuroko ${VERSION}</title>
      <pubDate>${PUB_DATE}</pubDate>
      <sparkle:version>${VERSION}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
${NOTES_HTML}
      ]]></description>
      <sparkle:fullReleaseNotesLink>https://github.com/nik-holo/kuroko/releases/tag/v${VERSION}</sparkle:fullReleaseNotesLink>
      <enclosure
        url="https://github.com/nik-holo/kuroko/releases/download/v${VERSION}/kuroko-${VERSION}.dmg"
        ${SIGNATURE_ATTRS}
        type="application/octet-stream"/>
    </item>
  </channel>
</rss>
EOF

echo "Wrote docs/appcast.xml for ${VERSION}"
echo "Remember: the DMG signed here must be byte-identical to the released asset."