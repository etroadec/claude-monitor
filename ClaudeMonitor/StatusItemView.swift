import Cocoa

class StatusItemView: NSView {
    var label: String = "" { didSet { needsDisplay = true } }
    var value: String = "CL" { didSet { needsDisplay = true } }
    var valueColor: NSColor = .white { didSet { needsDisplay = true } }
    var showBadge: Bool = false { didSet { needsDisplay = true; invalidateIntrinsicContentSize() } }

    private let labelFont = NSFont.systemFont(ofSize: 6, weight: .regular)
    private let valueFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)

    override var intrinsicContentSize: NSSize {
        let labelSize = (label as NSString).size(withAttributes: [.font: labelFont])
        let valueSize = (value as NSString).size(withAttributes: [.font: valueFont])
        let w = max(labelSize.width, valueSize.width)
        return NSSize(width: w, height: NSStatusBar.system.thickness)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let h = bounds.height

        if label.isEmpty {
            let attrs: [NSAttributedString.Key: Any] = [.font: valueFont, .foregroundColor: valueColor]
            let size = (value as NSString).size(withAttributes: attrs)
            let y = (h - size.height) / 2
            (value as NSString).draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: y), withAttributes: attrs)
        } else {
            let labelAttrs: [NSAttributedString.Key: Any] = [
                .font: labelFont,
                .foregroundColor: NSColor.white,
            ]
            let valueAttrs: [NSAttributedString.Key: Any] = [
                .font: valueFont,
                .foregroundColor: valueColor,
            ]

            let labelSize = (label as NSString).size(withAttributes: labelAttrs)
            let valueSize = (value as NSString).size(withAttributes: valueAttrs)

            let spacing: CGFloat = -2
            let totalH = labelSize.height + valueSize.height + spacing
            let baseY = (h - totalH) / 2

            (value as NSString).draw(at: NSPoint(x: 0, y: baseY), withAttributes: valueAttrs)
            let labelY = baseY + valueSize.height + spacing
            (label as NSString).draw(at: NSPoint(x: 0, y: labelY), withAttributes: labelAttrs)

            // Badge dot: at the end of the SESSION label line
            if showBadge {
                let dotSize: CGFloat = 4
                let dotX = labelSize.width + 2
                let dotY = labelY + (labelSize.height - dotSize) / 2
                let dotRect = NSRect(x: dotX, y: dotY, width: dotSize, height: dotSize)
                NSColor.systemOrange.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
        }
    }
}
