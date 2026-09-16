import ApplicationServices
import Foundation

/// Inserts text into the focused field via Accessibility.
/// On success the clipboard is left untouched. Callers fall back to
/// ClipboardManager when the focused element does not support
/// kAXSelectedTextAttribute (Chrome, Electron, Terminal, secure fields).
class TextInserter {
    static let shared = TextInserter()

    /// Returns true if the transcription was inserted into the focused
    /// element. False means the caller should paste via the clipboard.
    func insert(_ text: String) -> Bool {
        dispatchPrecondition(condition: .onQueue(.main))

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard focusedStatus == .success, let focusedRef else {
            Log.general.debug(
                "AX insert: no focused element (status \(focusedStatus.rawValue, privacy: .public))"
            )
            return false
        }
        let element = focusedRef as! AXUIElement

        var settable = DarwinBoolean(false)
        let settableStatus = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &settable
        )
        guard settableStatus == .success, settable.boolValue else {
            Log.general.debug(
                "AX insert: selected text not settable (status \(settableStatus.rawValue, privacy: .public))"
            )
            return false
        }

        let setStatus = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFString
        )
        guard setStatus == .success else {
            Log.general.debug(
                "AX insert: set selected text failed (status \(setStatus.rawValue, privacy: .public))"
            )
            return false
        }

        Log.general.info("AX insert succeeded")
        return true
    }
}
