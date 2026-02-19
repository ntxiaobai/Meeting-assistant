import AppKit

enum AppIconFactory {
    static func dockIcon(size: CGFloat) -> NSImage {
        drawWaveIcon(size: size, templateStyle: false)
    }

    static func menuBarTemplateIcon(size: CGFloat) -> NSImage {
        let image = drawWaveIcon(size: size, templateStyle: true)
        image.isTemplate = true
        return image
    }
}

private extension AppIconFactory {
    static func drawWaveIcon(size: CGFloat, templateStyle: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        if !templateStyle {
            let gradient = NSGradient(colors: [
                NSColor(calibratedRed: 0.16, green: 0.45, blue: 0.98, alpha: 1.0),
                NSColor(calibratedRed: 0.08, green: 0.79, blue: 0.86, alpha: 1.0),
            ])
            let rounded = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.06, dy: size * 0.06), xRadius: size * 0.24, yRadius: size * 0.24)
            gradient?.draw(in: rounded, angle: 50)
        } else {
            NSColor.clear.setFill()
            rect.fill()
        }

        let color: NSColor = templateStyle ? .labelColor : .white
        color.setStroke()

        let lineWidth = max(1.6, size * 0.075)
        let waveform = NSBezierPath()
        waveform.lineWidth = lineWidth
        waveform.lineCapStyle = .round
        waveform.lineJoinStyle = .round

        let inset = size * 0.19
        let w = size - inset * 2
        let h = size - inset * 2
        let minY = inset + h * 0.22
        let midY = inset + h * 0.5
        let maxY = inset + h * 0.78
        let x0 = inset
        let step = w / 8

        waveform.move(to: NSPoint(x: x0 + step * 0.0, y: midY))
        waveform.line(to: NSPoint(x: x0 + step * 1.0, y: minY))
        waveform.line(to: NSPoint(x: x0 + step * 2.0, y: maxY))
        waveform.line(to: NSPoint(x: x0 + step * 3.0, y: midY))
        waveform.line(to: NSPoint(x: x0 + step * 4.0, y: minY + h * 0.12))
        waveform.line(to: NSPoint(x: x0 + step * 5.0, y: maxY - h * 0.08))
        waveform.line(to: NSPoint(x: x0 + step * 6.0, y: midY))
        waveform.line(to: NSPoint(x: x0 + step * 7.0, y: minY + h * 0.18))
        waveform.line(to: NSPoint(x: x0 + step * 8.0, y: maxY - h * 0.16))
        waveform.stroke()

        if !templateStyle {
            NSColor.white.withAlphaComponent(0.2).setStroke()
            let border = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.06, dy: size * 0.06), xRadius: size * 0.24, yRadius: size * 0.24)
            border.lineWidth = max(1.0, size * 0.012)
            border.stroke()
        }

        return image
    }
}
