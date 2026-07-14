#!/usr/bin/env swift
// Generates Resources/boomerpix.icns (app icon).
// Run: swift scripts/genicons.swift   (from the repo root)
// Design: retro 70s sunrise — concentric sun arcs over a dark horizon.

import AppKit

func srgb(_ hex: UInt32) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: 1
    )
}

// outer → inner sun rings
let rings: [(radius: CGFloat, color: NSColor)] = [
    (330, srgb(0xB33F1F)), // rust
    (264, srgb(0xD96E30)), // burnt orange
    (198, srgb(0xED9F3C)), // amber
    (132, srgb(0xF4C453)), // gold
    (66,  srgb(0xF8E7C9)), // cream core
]
let skyTop = srgb(0x2B1712)
let skyBottom = srgb(0x54301C)
let ground = srgb(0x201209)

func renderAppIcon(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let scale = NSAffineTransform()
    scale.scale(by: CGFloat(pixels) / 1024)
    scale.concat()

    // macOS-style rounded square, inset per Apple icon grid (824pt content on 1024 canvas)
    let plate = NSRect(x: 100, y: 100, width: 824, height: 824)
    NSBezierPath(roundedRect: plate, xRadius: 185, yRadius: 185).addClip()

    NSGradient(colors: [skyBottom, skyTop])!.draw(in: plate, angle: 90)

    let horizonY: CGFloat = 400
    let sunCenter = NSPoint(x: 512, y: horizonY)
    for ring in rings {
        ring.color.setFill()
        NSBezierPath(ovalIn: NSRect(
            x: sunCenter.x - ring.radius, y: sunCenter.y - ring.radius,
            width: ring.radius * 2, height: ring.radius * 2
        )).fill()
    }

    ground.setFill()
    NSRect(x: plate.minX, y: plate.minY, width: plate.width, height: horizonY - plate.minY).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// --- main ---

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = repoRoot.appendingPathComponent("Resources")
let iconset = resources.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let entries: [(name: String, pixels: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for entry in entries {
    let rep = renderAppIcon(pixels: entry.pixels)
    let png = rep.representation(using: .png, properties: [:])!
    try png.write(to: iconset.appendingPathComponent("\(entry.name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("boomerpix.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    fatalError("iconutil failed")
}
print("wrote Resources/boomerpix.icns")
