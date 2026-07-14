# boomerpix

Menu bar app for macOS that watches your Downloads/Desktop folders and automatically
converts images in "modern web" formats (WebP, AVIF, HEIC) into formats everything
understands:

- static images → **JPEG** (quality configurable)
- images with transparency → **PNG** (so nothing gets a white box behind it)
- animated WebP → **GIF**

Originals are moved to the Trash by default (recoverable), or kept if you prefer.
No third-party dependencies — decoding and encoding use Apple's ImageIO.

Requires macOS 14 (Sonoma) or newer.

## Build & install

```sh
./scripts/make-app.sh --install   # builds dist/boomerpix.app and copies it to /Applications
open /Applications/boomerpix.app
```

On first conversion, macOS will ask for permission to access your Downloads/Desktop
folder — allow it once and you're set.

The build is ad-hoc signed, which is fine for your own machine. If you share the app
with others they'll need to right-click → Open the first time (or you eventually
notarize it with an Apple Developer account).

## Usage

- The menu bar icon shows a small photo glyph. The dropdown has:
  - **Pause / Resume** — temporarily stop auto-converting
  - **Convert Now** — sweep all watched folders for convertible files
  - **Settings…** — watched folders, formats, originals handling, JPEG quality,
    launch at login
- Watching applies to **newly appearing files only**; files already in a folder are
  only touched by Convert Now.
- Filename collisions get a suffix: `photo.webp` → `photo 2.jpg` if `photo.jpg` exists.

## Sharing it (DMG)

```sh
./scripts/make-dmg.sh   # -> dist/boomerpix-<version>.dmg
```

The DMG contains the app plus an Applications shortcut — standard drag-to-install.
Since the build is unsigned, people who download it must right-click → **Open** on
first launch (once), or run
`xattr -d com.apple.quarantine /Applications/boomerpix.app`.

## Icons

Both icons are generated from code — no design assets to maintain:

- App icon (Finder/DMG): `swift scripts/genicons.swift` regenerates
  `Resources/boomerpix.icns` (a retro sunrise; tweak colors/geometry in the script).
- Menu bar glyph: drawn at runtime in `Sources/boomerpix/MenuBarIcon.swift` as a
  template image, so it adapts to light/dark menu bars automatically.

## Headless test mode

```sh
.build/debug/boomerpix convert some-image.webp
```

Converts the given files in place and exits — handy for testing without the GUI.

## Notes & known limitations

- "Has transparency" is judged from the image's alpha channel; a fully opaque image
  saved with an alpha channel still becomes PNG rather than JPEG.
- In keep-originals mode, already-converted files are remembered in memory; after an
  app restart, Convert Now skips files whose output already exists, but a folder
  event for an old original could reconvert it (producing a ` 2` copy).
- Launch at login (SMAppService) only works when running as an installed `.app`,
  not via `swift run`.
