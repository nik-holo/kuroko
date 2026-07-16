#!/usr/bin/env swift
// Generates the menu bar template glyph and embeds it as a base64 PNG in
// Sources/kuroko/MenuBarIconData.swift.
//
// Source: Resources/menubar-master.png — light-on-dark artwork (white hood on
// dark background). The mask is per-pixel luminance: bright pixels become ink,
// dark pixels (background, face opening) become transparent. Rerun after
// changing the master: swift scripts/genmenubaricon.swift   (from repo root)

import AppKit

func rgbaRep(width: Int, height: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: width, height: height)
    return rep
}

let repoRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let masterURL = repoRoot.appendingPathComponent("Resources/menubar-master.png")
guard let masterImage = NSImage(contentsOf: masterURL),
      let probe = NSBitmapImageRep(data: try Data(contentsOf: masterURL)) else {
    fatalError("cannot read \(masterURL.path)")
}
let W = probe.pixelsWide, H = probe.pixelsHigh

// Normalize into a rep of known layout.
let norm = rgbaRep(width: W, height: H)
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: norm)
masterImage.draw(in: NSRect(x: 0, y: 0, width: W, height: H))
NSGraphicsContext.current = nil

// Mask: alpha = smoothstep of luminance (bright = ink), times source alpha.
let mask = rgbaRep(width: W, height: H)
let src = norm.bitmapData!, dst = mask.bitmapData!
let srcRow = norm.bytesPerRow, dstRow = mask.bytesPerRow
let lo = 0.45, hi = 0.75
var minX = W, maxX = 0, minY = H, maxY = 0
for y in 0..<H {
    for x in 0..<W {
        let p = src + y * srcRow + x * 4
        let a = Double(p[3])
        guard a > 0 else { continue }
        let lum = (Double(p[0]) + Double(p[1]) + Double(p[2])) / 3 / a
        let k = min(1, max(0, (lum - lo) / (hi - lo)))
        let alpha = UInt8(k * a)
        guard alpha > 0 else { continue }
        (dst + y * dstRow + x * 4)[3] = alpha  // premultiplied black: rgb stay 0
        if alpha > 128 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
guard maxX > minX, maxY > minY else { fatalError("no glyph found in master") }
print("ink bounds: x \(minX)..\(maxX), y \(minY)..\(maxY)")

// The eyes survive the luminance mask only as thin sclera crescents, which
// fade out at menu bar size. Find small ink blobs (the eyes — the hood is one
// big component) and stamp them as solid ovals instead.
var componentID = [Int](repeating: -1, count: W * H)
var components: [(minX: Int, maxX: Int, minY: Int, maxY: Int, area: Int)] = []
func inkAt(_ x: Int, _ y: Int) -> Bool { (dst + y * dstRow + x * 4)[3] > 100 }
for sy in 0..<H {
    for sx in 0..<W where inkAt(sx, sy) && componentID[sy * W + sx] == -1 {
        let id = components.count
        var queue = [(sx, sy)], head = 0
        componentID[sy * W + sx] = id
        var bounds = (minX: sx, maxX: sx, minY: sy, maxY: sy, area: 0)
        while head < queue.count {
            let (x, y) = queue[head]; head += 1
            bounds.area += 1
            bounds.minX = min(bounds.minX, x); bounds.maxX = max(bounds.maxX, x)
            bounds.minY = min(bounds.minY, y); bounds.maxY = max(bounds.maxY, y)
            for (nx, ny) in [(x-1, y), (x+1, y), (x, y-1), (x, y+1)]
            where nx >= 0 && nx < W && ny >= 0 && ny < H
                && inkAt(nx, ny) && componentID[ny * W + nx] == -1 {
                componentID[ny * W + nx] = id
                queue.append((nx, ny))
            }
        }
        components.append(bounds)
    }
}
let hoodArea = components.map(\.area).max() ?? 0
var eyeBlobs = components.filter { $0.area < hoodArea / 10 }
// merge fragments belonging to the same eye (sclera split by the pupil)
var merged = true
while merged {
    merged = false
    outer: for i in 0..<eyeBlobs.count {
        for j in (i + 1)..<eyeBlobs.count {
            let a = eyeBlobs[i], b = eyeBlobs[j]
            let gapX = max(0, max(a.minX, b.minX) - min(a.maxX, b.maxX))
            let gapY = max(0, max(a.minY, b.minY) - min(a.maxY, b.maxY))
            if gapX < 8 && gapY < 8 {
                eyeBlobs[i] = (min(a.minX, b.minX), max(a.maxX, b.maxX),
                               min(a.minY, b.minY), max(a.maxY, b.maxY), a.area + b.area)
                eyeBlobs.remove(at: j)
                merged = true
                break outer
            }
        }
    }
}
for blob in eyeBlobs {
    // inflate a little and fill as one solid ellipse per eye
    let cx = Double(blob.minX + blob.maxX) / 2, cy = Double(blob.minY + blob.maxY) / 2
    let rx = Double(blob.maxX - blob.minX) / 2 + 1.5, ry = Double(blob.maxY - blob.minY) / 2 + 1.5
    for y in max(0, blob.minY - 3)...min(H - 1, blob.maxY + 3) {
        for x in max(0, blob.minX - 3)...min(W - 1, blob.maxX + 3) {
            let dx = (Double(x) - cx) / rx, dy = (Double(y) - cy) / ry
            if dx * dx + dy * dy <= 1 { (dst + y * dstRow + x * 4)[3] = 255 }
        }
    }
}
print("eyes stamped: \(eyeBlobs.count)")

// Crop to ink, pad to square, downscale into 36x36 (18pt @2x) with 2.5pt margin.
let inkW = maxX - minX + 1, inkH = maxY - minY + 1
let side = max(inkW, inkH)
let cropX = minX - (side - inkW) / 2, cropY = minY - (side - inkH) / 2

let out = rgbaRep(width: 36, height: 36)
let maskImage = NSImage(size: NSSize(width: W, height: H))
maskImage.addRepresentation(mask)
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
NSGraphicsContext.current?.imageInterpolation = .high
let margin: CGFloat = 2  // ink fills 16pt of 18pt — matches typical menu bar icons
let fromRect = NSRect(x: CGFloat(cropX), y: CGFloat(H - cropY - side),
                      width: CGFloat(side), height: CGFloat(side))
maskImage.draw(in: NSRect(x: margin, y: margin, width: 36 - 2 * margin, height: 36 - 2 * margin),
               from: fromRect, operation: .copy, fraction: 1)
NSGraphicsContext.current = nil

let png = out.representation(using: .png, properties: [:])!
let swiftFile = """
// Generated by scripts/genmenubaricon.swift — do not edit by hand.
// 36x36 template PNG (18pt @2x): the hooded mascot glyph.
enum MenuBarIconData {
    static let templatePNGBase64 = \"\(png.base64EncodedString())\"
}
"""
try swiftFile.write(
    to: repoRoot.appendingPathComponent("Sources/kuroko/MenuBarIconData.swift"),
    atomically: true, encoding: .utf8
)

// 8x preview on white for inspection
let pv = rgbaRep(width: 288, height: 288)
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: pv)
NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 288, height: 288).fill()
let outImage = NSImage(size: NSSize(width: 36, height: 36))
outImage.addRepresentation(out)
NSGraphicsContext.current?.imageInterpolation = .none
outImage.draw(in: NSRect(x: 0, y: 0, width: 288, height: 288))
NSGraphicsContext.current = nil
try pv.representation(using: .png, properties: [:])!
    .write(to: repoRoot.appendingPathComponent("Resources/menubar-preview.png"))
print("wrote MenuBarIconData.swift (\(png.count) bytes png) + Resources/menubar-preview.png")
