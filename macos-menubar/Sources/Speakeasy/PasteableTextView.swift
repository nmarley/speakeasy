import AppKit

/// A text view that supports all standard keyboard shortcuts.
class PasteableTextView: NSTextView {

    override var acceptsFirstResponder: Bool {
        return true
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
            let characters = event.charactersIgnoringModifiers
        {
            switch characters.lowercased() {
            case "a":
                // Select all
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self)
                return true
            case "c":
                // Copy
                NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: self)
                return true
            case "v":
                // Paste
                NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
                return true
            case "x":
                // Cut
                NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: self)
                return true
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        let action = item.action
        if action == #selector(NSText.paste(_:)) || action == #selector(NSText.copy(_:))
            || action == #selector(NSText.cut(_:)) || action == #selector(NSText.selectAll(_:))
        {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }
}
