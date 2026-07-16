#!/usr/bin/env swift
// Generates Resources/dmg-background.png — the DMG window backdrop (660x400pt
// @2x): light grey, soft brand-color glows, and a fat gradient arrow pointing
// from the app icon position to the Applications folder position.
// Run: swift scripts/gendmgbg.swift   (from the repo root)

import AppKit

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let W: CGFloat = 660, H: CGFloat = 400
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(W) * 2, pixelsHigh: Int(H) * 2,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
)!
rep.size = NSSize(width: W, height: H)  // -> 144dpi, Finder renders @2x crisp

// rep.size at half the pixel dimensions makes the context 144dpi: drawing
// happens in point coordinates, retina scaling is implicit.
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let cg = NSGraphicsContext.current!.cgContext

// base: dark stage, subtle spotlight glow in the middle
srgb(0x1D1D21).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

func glow(_ hex: UInt32, alpha: CGFloat, center: NSPoint, radius: CGFloat) {
    let gradient = NSGradient(colors: [srgb(hex, alpha), srgb(hex, 0)])!
    gradient.draw(
        in: NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius,
                                        width: radius * 2, height: radius * 2)),
        relativeCenterPosition: .zero
    )
}
glow(0xFFFFFF, alpha: 0.07, center: NSPoint(x: 330, y: 260), radius: 320)

// gradient arrow: icons sit at Finder positions {165,200} and {495,200}
// (top-left coords); our drawing is bottom-up, icon row center ~ y=215.
let arrowY: CGFloat = 218
let shaftStart: CGFloat = 245, shaftEnd: CGFloat = 388, headTip: CGFloat = 425
cg.saveGState()
// one continuous outline (rounded tail, shaft, head) — no seams between parts
let half: CGFloat = 11, headHalf: CGFloat = 26
let arrow = CGMutablePath()
arrow.move(to: CGPoint(x: shaftStart, y: arrowY - half))
arrow.addLine(to: CGPoint(x: shaftEnd, y: arrowY - half))
arrow.addLine(to: CGPoint(x: shaftEnd, y: arrowY - headHalf))
arrow.addLine(to: CGPoint(x: headTip, y: arrowY))
arrow.addLine(to: CGPoint(x: shaftEnd, y: arrowY + headHalf))
arrow.addLine(to: CGPoint(x: shaftEnd, y: arrowY + half))
arrow.addLine(to: CGPoint(x: shaftStart, y: arrowY + half))
arrow.addArc(center: CGPoint(x: shaftStart, y: arrowY), radius: half,
             startAngle: .pi / 2, endAngle: -.pi / 2, clockwise: false)
arrow.closeSubpath()
cg.addPath(arrow)
cg.clip()
let colors = [srgb(0x8E8E96).cgColor, srgb(0xEDEDF2).cgColor]
let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: colors as CFArray, locations: [0, 1])!
cg.drawLinearGradient(
    gradient,
    start: CGPoint(x: shaftStart - 12, y: 0), end: CGPoint(x: headTip, y: 0),
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
)
cg.restoreGState()

// caption under the arrow
func draw(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, center: NSPoint) {
    let descriptor = NSFont.systemFont(ofSize: size, weight: weight)
        .fontDescriptor.withDesign(.rounded)
    let font = descriptor.flatMap { NSFont(descriptor: $0, size: size) }
        ?? NSFont.systemFont(ofSize: size, weight: weight)
    let string = NSAttributedString(string: text, attributes: [
        .font: font, .foregroundColor: color,
    ])
    let bounds = string.size()
    string.draw(at: NSPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2))
}
draw("drag to install", size: 14, weight: .semibold, color: srgb(0x8E8E96),
     center: NSPoint(x: (shaftStart + headTip) / 2, y: arrowY - 46))
draw("kuroko", size: 26, weight: .heavy, color: srgb(0xF2F2F5),
     center: NSPoint(x: W / 2, y: H - 52))
draw("image formats that just work", size: 12, weight: .regular, color: srgb(0x8E8E96),
     center: NSPoint(x: W / 2, y: H - 74))

NSGraphicsContext.current = nil
let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let out = repoRoot.appendingPathComponent("Resources/dmg-background.png")
try rep.representation(using: .png, properties: [:])!.write(to: out)
print("wrote Resources/dmg-background.png")
