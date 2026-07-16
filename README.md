# kuroko

*kuroko (黒子): the black-clad kabuki stagehand the audience agrees not to see.*

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
./scripts/make-app.sh --install   # builds dist/kuroko.app and copies it to /Applications
open /Applications/kuroko.app
```

On first conversion, macOS will ask for permission to access your Downloads/Desktop
folder — allow it once and you're set.

The build is ad-hoc signed, which is fine for your own machine. If you share the app
with others they'll need to right-click → Open the first time (or you eventually
notarize it with an Apple Developer account).

## Usage

- The menu bar icon is the hooded kuroko mascot. The dropdown has:
  - **Pause / Resume** — temporarily stop auto-converting
  - **Convert Now** — sweep all watched folders for convertible files
  - **Convert Files…** — pick images or folders to convert manually
  - **Settings…** — watched folders, formats, originals handling, JPEG quality,
    launch at login
- **Drag & drop:** drop images (any format macOS can read — also PNG, JPEG, TIFF…)
  or folders onto the menu bar icon. A confirm panel lets you pick the output
  format (Auto/JPEG/PNG/GIF), JPEG quality, whether originals go to the Trash,
  and a destination folder. Folders contribute their top-level images.
- Watching applies to **newly appearing files only**; files already in a folder are
  only touched by Convert Now.
- Filename collisions get a suffix: `photo.webp` → `photo 2.jpg` if `photo.jpg` exists.

## Sharing it (DMG)

```sh
./scripts/make-dmg.sh   # -> dist/kuroko-<version>.dmg
```

The DMG opens as a styled window — brand background with a gradient arrow from the
app to the Applications shortcut (`swift scripts/gendmgbg.swift` regenerates the
backdrop in `Resources/dmg-background.png`). Building the DMG scripts Finder to lay
out the window, which may prompt once for automation permission.
Since the build is unsigned, people who download it must right-click → **Open** on
first launch (once), or run
`xattr -d com.apple.quarantine /Applications/kuroko.app`.

## Releasing a new version

The version lives in the `VERSION` file and flows into the app bundle
(`CFBundleShortVersionString`) and the DMG filename automatically.

```sh
# 1. bump the version
echo "0.2.0" > VERSION

# 2. build and spot-check the DMG
./scripts/make-dmg.sh
open dist/kuroko-0.2.0.dmg

# 3. commit, tag, push
git commit -am "Release v0.2.0"
git tag v0.2.0
git push && git push --tags

# 4. publish the GitHub release with the DMG attached (kuroko.dmg is the
#    stable-name copy the landing page's download button points at)
gh release create v0.2.0 dist/kuroko-0.2.0.dmg dist/kuroko.dmg \
  --title "kuroko 0.2.0" --generate-notes
```

## Icons

- App icon (Finder/DMG): `swift scripts/genicons.swift` regenerates
  `Resources/kuroko.icns` from `Resources/icon-master.png` (1024×1024 with real
  alpha — the hooded mascot). Delete the master and the script falls back to a
  code-drawn retro sunrise.
- Menu bar glyph: extracted from `Resources/menubar-master.png` (light-on-dark
  hooded-mascot art) by `swift scripts/genmenubaricon.swift` — bright pixels
  become ink via a luminance mask, and the eyes are re-stamped as solid ovals so
  they stay legible at 18pt. The result is embedded as a base64 PNG in
  `Sources/kuroko/MenuBarIconData.swift` (a hand-drawn hood remains as
  fallback). Rerun the script after changing the master.
- The previous glassy-"B" master is kept at `Resources/icon-master-glassb.png` —
  copy it back over `icon-master.png` and rerun the scripts to revert the
  mascot experiment.

## Headless test mode

```sh
.build/debug/kuroko convert [--format auto|jpeg|png|gif] [--dest <dir>] some-image.webp
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
