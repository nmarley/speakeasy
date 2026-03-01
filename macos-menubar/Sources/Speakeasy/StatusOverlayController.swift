import AppKit

class StatusOverlayController: NSObject {
    private var panel: NSPanel?
    private var statusLabel: NSTextField?

    override init() {
        super.init()
        setupPanel()
    }

    private func setupPanel() {
        // Create an NSPanel instead of NSWindow for HUD style
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        // Configure panel appearance
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.level = .floating
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        // Add rounded corners to the panel
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = 15.0
        panel.contentView?.layer?.masksToBounds = true
        panel.contentView?.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.5).cgColor

        // Create and configure the status label
        let label = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 80))
        label.cell = VerticallyCenteredTextFieldCell()
        label.isEditable = false
        label.isBordered = false
        label.drawsBackground = false
        label.textColor = .white
        label.alignment = .center
        label.font = NSFont.systemFont(ofSize: 24, weight: .medium)  // Increased font size
        label.stringValue = ""

        // Center the label in the panel
        // label.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView?.addSubview(label)

        // Add constraints to center the label
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: panel.contentView!.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: panel.contentView!.centerYAnchor),
            label.widthAnchor.constraint(equalTo: panel.contentView!.widthAnchor),
            label.heightAnchor.constraint(equalTo: panel.contentView!.heightAnchor),
        ])

        // Center the panel on screen
        panel.center()

        // Store references
        self.panel = panel
        self.statusLabel = label
    }

    func updateStatus(with text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.statusLabel?.stringValue = text
        }
    }

    func show() {
        DispatchQueue.main.async { [weak self] in
            guard let panel = self?.panel else { return }

            // Center the panel on the current screen
            if let screen = NSScreen.main {
                let screenRect = screen.visibleFrame
                let panelRect = panel.frame
                let x = screenRect.midX - panelRect.width / 2
                let y = screenRect.midY - panelRect.height / 2
                panel.setFrameOrigin(NSPoint(x: x, y: y))
            }

            panel.orderFrontRegardless()
        }
    }

    func hide() {
        DispatchQueue.main.async { [weak self] in
            self?.panel?.orderOut(nil)
        }
    }
}

class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        var newRect = super.drawingRect(forBounds: rect)
        let textSize = self.cellSize(forBounds: rect)
        let heightDelta = newRect.size.height - textSize.height
        if heightDelta > 0 {
            newRect.origin.y += heightDelta / 2.0
            newRect.size.height -= heightDelta
        }
        return newRect
    }
}
