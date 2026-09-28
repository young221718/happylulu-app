import AppKit

@MainActor
enum LuluBrand {
    static func menuBarIcon() -> NSImage {
        // An original vector companion to the smiling clock in the app icon.
        // Template rendering adapts to the menu bar in both light and dark modes.
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

            let contour = NSBezierPath()
            contour.appendArc(withCenter: NSPoint(x: 9, y: 9), radius: 7,
                              startAngle: 64, endAngle: 34, clockwise: false)
            contour.line(to: NSPoint(x: 15.25, y: 14.15))
            contour.lineWidth = 1.6
            contour.lineCapStyle = .round
            contour.lineJoinStyle = .round
            contour.stroke()

            for x in [5.7, 10.5] {
                NSBezierPath(roundedRect: NSRect(x: x, y: 9.0, width: 1.8, height: 2.8), xRadius: 0.9, yRadius: 0.9).fill()
            }
            let smile = NSBezierPath()
            smile.move(to: NSPoint(x: 5.5, y: 6.9))
            smile.curve(to: NSPoint(x: 12.5, y: 6.9),
                        controlPoint1: NSPoint(x: 7.25, y: 3.8),
                        controlPoint2: NSPoint(x: 10.75, y: 3.8))
            smile.lineWidth = 1.6
            smile.lineCapStyle = .round
            smile.stroke()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "HappyLulu"
        return image
    }
}
