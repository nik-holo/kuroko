#!/usr/bin/env swift
// Generates docs/og-image.png (1200x630) — the social share card:
// app icon on the left, wordmark + tagline on the right, dark stage look.
// Run: swift scripts/genogimage.swift   (from the repo root)

import AppKit

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let W = 1200, H = 630
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = NSSize(width: W, height: H)
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

srgb(0x1C1C20).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()
// soft spotlight behind the icon
let glow = NSGradient(colors: [srgb(0xFFFFFF, 0.09), srgb(0xFFFFFF, 0)])!
glow.draw(in: NSBezierPath(ovalIn: NSRect(x: 40, y: 95, width: 440, height: 440)),
          relativeCenterPosition: .zero)

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
if let icon = NSImage(contentsOf: repoRoot.appendingPathComponent("Resources/icon-master.png")) {
    NSGraphicsContext.current?.imageInterpolation = .high
    icon.draw(in: NSRect(x: 70, y: 125, width: 380, height: 380))
}

func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, at point: NSPoint) {
    let descriptor = NSFont.systemFont(ofSize: size, weight: weight)
        .fontDescriptor.withDesign(.rounded)
    let font = descriptor.flatMap { NSFont(descriptor: $0, size: size) }
        ?? NSFont.systemFont(ofSize: size, weight: weight)
    NSAttributedString(string: text, attributes: [
        .font: font, .foregroundColor: color,
    ]).draw(at: point)
}

draw("kuroko", size: 92, weight: .heavy, color: srgb(0xF2F2F5), at: NSPoint(x: 500, y: 360))
draw("WebP · AVIF · HEIC  →  JPEG · PNG · GIF", size: 36, weight: .semibold,
     color: srgb(0xC9C9D2), at: NSPoint(x: 502, y: 290))
draw("automatic image converter", size: 32, weight: .regular,
     color: srgb(0x9A97A3), at: NSPoint(x: 502, y: 236))
draw("in your Mac's menu bar", size: 32, weight: .regular,
     color: srgb(0x9A97A3), at: NSPoint(x: 502, y: 190))
draw("free & open source · kuroko.holo.red", size: 24, weight: .regular,
     color: srgb(0x6E6C77), at: NSPoint(x: 502, y: 120))

NSGraphicsContext.current = nil
try rep.representation(using: .png, properties: [:])!
    .write(to: repoRoot.appendingPathComponent("docs/og-image.png"))
print("wrote docs/og-image.png")
