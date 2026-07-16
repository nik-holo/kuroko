import AppKit

/// Menu bar glyph: the hooded mascot, extracted from Resources/menubar-master.png
/// by scripts/genmenubaricon.swift (luminance mask + solidified eyes) and
/// embedded as a base64 PNG in MenuBarIconData.swift. Template image, so macOS
/// tints it for light/dark menu bars and the pressed state.
enum MenuBarIcon {
    static let image: NSImage = {
        if let data = Data(base64Encoded: MenuBarIconData.templatePNGBase64),
           let image = NSImage(data: data) {
            image.size = NSSize(width: 18, height: 18)  // 36px png -> 18pt @2x
            image.isTemplate = true
            return image
        }
        return drawnFallback
    }()

    /// Fallback if the embedded data ever fails to decode: a hand-drawn hood.
    private static var drawnFallback: NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let path = NSBezierPath()
            path.windingRule = .evenOdd
            // broad hood: flat-ish rounded dome, gentle shoulder flare at the base
            path.move(to: NSPoint(x: 1.6, y: 1.5))
            path.curve(to: NSPoint(x: 3.4, y: 10.5),
                       controlPoint1: NSPoint(x: 2.6, y: 3.2), controlPoint2: NSPoint(x: 3.0, y: 7.0))
            path.curve(to: NSPoint(x: 9, y: 16.2),
                       controlPoint1: NSPoint(x: 3.9, y: 13.8), controlPoint2: NSPoint(x: 5.8, y: 16.2))
            path.curve(to: NSPoint(x: 14.6, y: 10.5),
                       controlPoint1: NSPoint(x: 12.2, y: 16.2), controlPoint2: NSPoint(x: 14.1, y: 13.8))
            path.curve(to: NSPoint(x: 16.4, y: 1.5),
                       controlPoint1: NSPoint(x: 15.0, y: 7.0), controlPoint2: NSPoint(x: 15.4, y: 3.2))
            path.close()
            path.appendOval(in: NSRect(x: 5.0, y: 8.6, width: 3.4, height: 2.9))
            path.appendOval(in: NSRect(x: 9.6, y: 8.6, width: 3.4, height: 2.9))
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}
