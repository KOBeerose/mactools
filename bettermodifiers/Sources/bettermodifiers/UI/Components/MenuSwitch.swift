import AppKit

/// Switch for menu item views. NSSwitch draws gray inside menus because the
/// menu window is never key; this one always uses the accent color when on.
final class MenuSwitch: NSControl {
    var isOn = false {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize { NSSize(width: 32, height: 18) }

    override func draw(_ dirtyRect: NSRect) {
        let track = bounds.insetBy(dx: 0.5, dy: 0.5)
        let radius = track.height / 2
        let trackPath = NSBezierPath(roundedRect: track, xRadius: radius, yRadius: radius)
        (isOn ? NSColor.controlAccentColor : NSColor.tertiaryLabelColor).setFill()
        trackPath.fill()

        let knobSize = track.height - 3
        let knobX = isOn ? track.maxX - knobSize - 1.5 : track.minX + 1.5
        let knob = NSRect(x: knobX, y: track.minY + 1.5, width: knobSize, height: knobSize)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.shadowBlurRadius = 1
        shadow.set()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: knob).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    override func mouseDown(with event: NSEvent) {
        isOn.toggle()
        sendAction(action, to: target)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
