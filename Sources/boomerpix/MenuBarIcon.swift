import AppKit

/// Menu bar glyph drawn in code (no bundled assets needed): a small retro
/// sunrise — half-disc sun, two arcs, horizon line. Template image, so macOS
/// tints it correctly for light/dark menu bars and the pressed state.
enum MenuBarIcon {
    static let image: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let center = NSPoint(x: 9, y: 4)
            NSColor.black.set()

            let core = NSBezierPath()
            core.appendArc(withCenter: center, radius: 2.5, startAngle: 0, endAngle: 180)
            core.close()
            core.fill()

            for radius in [5.0, 7.5] {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 180)
                arc.lineWidth = 1.5
                arc.lineCapStyle = .round
                arc.stroke()
            }

            let horizon = NSBezierPath()
            horizon.move(to: NSPoint(x: 0.75, y: center.y))
            horizon.line(to: NSPoint(x: 17.25, y: center.y))
            horizon.lineWidth = 1.5
            horizon.lineCapStyle = .round
            horizon.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
