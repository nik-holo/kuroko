# Later

Deliberately deferred — roughly in the order they'll probably matter:

- **Notarization** — Apple Developer Program ($99/yr), Developer ID signing with
  hardened runtime + `notarytool` + stapling, wired into `make-app.sh`/`make-dmg.sh`.
  Kills the Gatekeeper "Open Anyway" friction for downloads. Do this when the app
  has users beyond friends.
- **Sparkle auto-updates** — pairs with notarization; matters once users won't
  re-download DMGs manually.
- **Persist the processed-file memory** — in keep-originals mode the in-memory
  "already converted" set dies with the app; a restart plus a folder event can
  reconvert an old original into a ` 2` copy. Store keys on disk.
- **Clipboard conversion** — menu item/hotkey: convert the image on the clipboard
  and put the result back (or as a file).
- **Per-folder rules** — different format/originals/quality settings per watched
  folder. Wait until someone actually asks; multiplies settings UI complexity.
- **WebP as an output format** — ImageIO cannot encode WebP (decode only, still
  true on macOS 26), so this needs bundling libwebp, breaking the zero-dependency
  rule. AVIF/HEIC outputs cover most "modern format out" needs.
