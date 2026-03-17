import AppKit

enum MenuBarIconRenderer {
    private static let iconSize = NSSize(width: 22, height: 22)
    private static let barWidth: CGFloat = 14
    private static let barHeight: CGFloat = 3
    private static let barX: CGFloat = 4
    private static let bar5hY: CGFloat = 6
    private static let bar7dY: CGFloat = 2

    static func renderIcon(pct5h: Double, pct7d: Double) -> NSImage {
        let image = NSImage(size: iconSize, flipped: false) { rect in
            // Background bars (track)
            let trackColor = NSColor.black.withAlphaComponent(0.2)
            trackColor.setFill()
            NSBezierPath(roundedRect: NSRect(x: barX, y: bar5hY, width: barWidth, height: barHeight),
                         xRadius: 1.5, yRadius: 1.5).fill()
            NSBezierPath(roundedRect: NSRect(x: barX, y: bar7dY, width: barWidth, height: barHeight),
                         xRadius: 1.5, yRadius: 1.5).fill()

            // Filled bars
            let fillColor = NSColor.black.withAlphaComponent(0.8)
            fillColor.setFill()
            let fill5h = max(barWidth * CGFloat(min(pct5h, 1.0)), 0)
            let fill7d = max(barWidth * CGFloat(min(pct7d, 1.0)), 0)

            if fill5h > 0 {
                NSBezierPath(roundedRect: NSRect(x: barX, y: bar5hY, width: fill5h, height: barHeight),
                             xRadius: 1.5, yRadius: 1.5).fill()
            }
            if fill7d > 0 {
                NSBezierPath(roundedRect: NSRect(x: barX, y: bar7dY, width: fill7d, height: barHeight),
                             xRadius: 1.5, yRadius: 1.5).fill()
            }

            // Claude dot at top
            let dotColor = NSColor.black.withAlphaComponent(0.6)
            dotColor.setFill()
            let dotSize: CGFloat = 4
            let dotRect = NSRect(x: (rect.width - dotSize) / 2, y: rect.height - dotSize - 4,
                                 width: dotSize, height: dotSize)
            NSBezierPath(ovalIn: dotRect).fill()

            return true
        }
        image.isTemplate = true
        return image
    }

    static func renderUnauthenticatedIcon() -> NSImage {
        let image = NSImage(size: iconSize, flipped: false) { rect in
            let dashColor = NSColor.black.withAlphaComponent(0.3)
            dashColor.setStroke()

            // Dashed bars
            for y in [bar5hY, bar7dY] {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: barX, y: y + barHeight / 2))
                path.line(to: NSPoint(x: barX + barWidth, y: y + barHeight / 2))
                path.lineWidth = barHeight
                path.setLineDash([3, 2], count: 2, phase: 0)
                path.stroke()
            }

            // Claude dot
            let dotColor = NSColor.black.withAlphaComponent(0.3)
            dotColor.setFill()
            let dotSize: CGFloat = 4
            let dotRect = NSRect(x: (rect.width - dotSize) / 2, y: rect.height - dotSize - 4,
                                 width: dotSize, height: dotSize)
            NSBezierPath(ovalIn: dotRect).fill()

            return true
        }
        image.isTemplate = true
        return image
    }
}
