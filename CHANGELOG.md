# Changelog

Each `## <version>` section is embedded verbatim (as HTML) into the Sparkle
update dialog by `scripts/make-appcast.sh`. Keep it short: a handful of
bullets, plain markdown (bullets, **bold**, `code`, links).

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
