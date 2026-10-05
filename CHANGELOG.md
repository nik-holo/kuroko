# Changelog

Each `## <version>` section is embedded verbatim (as HTML) into the Sparkle
update dialog by `scripts/make-appcast.sh`. Keep it short: a handful of
bullets, plain markdown (bullets, **bold**, `code`, links).

## 0.5.0

- **Web links become images:** `.webloc` / `.url` files landing in a watched
  folder (what Safari drops when you drag a picture out of Threads, Instagram,
  Dribbble…) are resolved — the image behind the link is downloaded, the link
  is trashed, and the image is converted if it's WebP/AVIF/HEIC
- Drop link files or a browser URL onto the menu bar icon to download + convert
- New **Web Links** toggle in Settings; `kuroko fetch` headless command

## 0.4.1

- Auto format now scans the actual pixels instead of trusting the container's
  alpha flag: opaque images with an alpha channel become JPEG, only genuinely
  transparent ones stay PNG
- Refreshed landing page screenshots

## 0.4.0

- Auto-updates via Sparkle, with a **Check for Updates…** menu item
- Automatic update checks enabled for the installed app

## 0.3.0

- AVIF and HEIC output formats (runtime-checked; WebP encode is unsupported by ImageIO)
- Free-form pixel and MB size caps (quality first, then dimension reduction)
- Strip-metadata toggle
- Finder right-click conversion via Services
- Undo Last Conversion, running conversion counter, opt-in notifications
- Homebrew tap install
