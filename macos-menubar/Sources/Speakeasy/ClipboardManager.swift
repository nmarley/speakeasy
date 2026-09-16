import AppKit
import Quartz

class ClipboardManager {
    static let shared = ClipboardManager()

    /// True while synthetic Cmd+V events are in flight. Used by
    /// PushToTalkManager to ignore those events. Independent of clipboard
    /// restoration; a 5s restore must not keep push-to-talk deaf.
    static var isPasting = false

    /// How long to leave the transcription on the pasteboard before
    /// restoring the previous contents. Reads never bump changeCount, so
    /// this is a safety timeout, not a signal that the target consumed
    /// the paste. 5s outlasts slow consumers on macOS 26.
    private static let restoreDelay: TimeInterval = 5.0

    /// How long to keep isPasting true after posting the key events.
    private static let pastingGuardDuration: TimeInterval = 0.1

    private static let keyCodeV: CGKeyCode = 0x09
    private static let keyCodeCommand: CGKeyCode = 0x37

    /// Monotonic paste counter. Incremented on every paste() call so a
    /// restore or key-post scheduled by an earlier dictation can
    /// deterministically bail out.
    private var pasteGeneration = 0

    /// Puts the given transcription text into the clipboard, simulates a
    /// Cmd+V paste on the next runloop turn, and restores the previous
    /// clipboard after restoreDelay if nothing else wrote to it.
    func paste(transcription: String) {
        dispatchPrecondition(condition: .onQueue(.main))

        Log.general.debug("ClipboardManager.paste() starting")
        Log.general.debug("Transcription to paste: \(transcription, privacy: .public)")

        pasteGeneration &+= 1
        let generation = pasteGeneration

        let pasteboard = NSPasteboard.general
        let previousContent = pasteboard.string(forType: .string)
        Log.general.debug(
            "Previous clipboard content stored: \(previousContent ?? "nil", privacy: .public)")

        pasteboard.clearContents()
        pasteboard.setString(transcription, forType: .string)

        // Reading changeCount fences the pasteboard write so the next
        // runloop turn cannot post Cmd+V against a stale pasteboard.
        let _ = pasteboard.changeCount

        let clipboardAfterSet = pasteboard.string(forType: .string)
        if clipboardAfterSet != transcription {
            Log.general.error(
                "Clipboard write failed: expected \(transcription, privacy: .public), got \(clipboardAfterSet ?? "nil", privacy: .public)"
            )
        }

        let ourChangeCount = pasteboard.changeCount

        DispatchQueue.main.async { [weak self] in
            guard let self, self.pasteGeneration == generation else { return }
            self.postPasteKeyEvents()
            self.schedulePastingGuardClear(generation: generation)
            self.scheduleRestore(
                expectedCount: ourChangeCount,
                previousContent: previousContent,
                generation: generation
            )
        }

        Log.general.debug("ClipboardManager.paste() returning (key post and restore are async)")
    }

    private func postPasteKeyEvents() {
        Log.general.debug("Simulating Cmd+V paste operation")
        let source = CGEventSource(stateID: .privateState)

        let commandDown = CGEvent(
            keyboardEventSource: source, virtualKey: Self.keyCodeCommand, keyDown: true)
        commandDown?.flags = .maskCommand

        let vDown = CGEvent(
            keyboardEventSource: source, virtualKey: Self.keyCodeV, keyDown: true)
        vDown?.flags = .maskCommand

        let vUp = CGEvent(
            keyboardEventSource: source, virtualKey: Self.keyCodeV, keyDown: false)
        vUp?.flags = .maskCommand

        let commandUp = CGEvent(
            keyboardEventSource: source, virtualKey: Self.keyCodeCommand, keyDown: false)

        ClipboardManager.isPasting = true
        commandDown?.post(tap: .cghidEventTap)
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)
        commandUp?.post(tap: .cghidEventTap)
        Log.general.debug("Cmd+V events posted")
    }

    private func schedulePastingGuardClear(generation: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pastingGuardDuration) {
            [weak self] in
            guard let self, self.pasteGeneration == generation else { return }
            ClipboardManager.isPasting = false
        }
    }

    private func scheduleRestore(
        expectedCount: Int,
        previousContent: String?,
        generation: Int
    ) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.restoreDelay) { [weak self] in
            guard let self, self.pasteGeneration == generation else {
                Log.general.debug(
                    "ClipboardManager: restore superseded by newer paste, skipping")
                return
            }

            let pasteboard = NSPasteboard.general
            let currentCount = pasteboard.changeCount
            if currentCount != expectedCount {
                Log.general.debug(
                    "ClipboardManager: changeCount changed (\(expectedCount, privacy: .public) -> \(currentCount, privacy: .public)), skipping restore"
                )
                return
            }

            Log.general.debug(
                "Restoring previous clipboard content: \(previousContent ?? "nil", privacy: .public)"
            )
            pasteboard.clearContents()
            if let previousContent {
                pasteboard.setString(previousContent, forType: .string)
            }

            let finalContent = pasteboard.string(forType: .string)
            if finalContent != previousContent {
                Log.general.error("CLIPBOARD RESTORATION FAILED!")
                Log.general.error(
                    "Expected: \(previousContent ?? "nil", privacy: .public)")
                Log.general.error(
                    "Actual: \(finalContent ?? "nil", privacy: .public)")
            } else {
                Log.general.debug("Clipboard restored successfully")
            }
        }
    }
}
