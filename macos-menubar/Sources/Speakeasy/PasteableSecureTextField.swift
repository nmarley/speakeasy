import AppKit

/// A secure text field that allows pasting via Command-V.
/// Instead of overriding unavailable methods, we override `performKeyEquivalent(with:)`
/// to intercept Cmd+V and trigger the paste action through NSApp.
class PasteableSecureTextField: NSSecureTextField {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
            let characters = event.charactersIgnoringModifiers,
            characters.lowercased() == "v"
        {
            // Send the paste action to trigger pasting.
            NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func validateUserInterfaceItem(_ item: NSValidatedUserInterfaceItem) -> Bool {
        if item.action == #selector(NSText.paste(_:)) {
            return true
        }
        return super.validateUserInterfaceItem(item)
    }
}
