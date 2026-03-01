import AppKit

enum AppIcons {
    static let greenStatusDot: NSImage = {
        return createCircleIcon(radius: 12, color: .systemGreen)
    }()

    static let yellowStatusDot: NSImage = {
        return createCircleIcon(radius: 12, color: .systemYellow)
    }()

    static let redStatusDot: NSImage = {
        return createCircleIcon(radius: 12, color: .systemRed)
    }()

    private static func createCircleIcon(radius: Double, color: NSColor) -> NSImage {
        let size = NSSize(width: radius, height: radius)
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(origin: .zero, size: size)).fill()
        image.unlockFocus()
        return image
    }
}
