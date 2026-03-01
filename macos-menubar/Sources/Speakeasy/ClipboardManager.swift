import AppKit
import Quartz

class ClipboardManager {
    static let shared = ClipboardManager()

    /// True while a paste operation is in flight (from Cmd+V post until
    /// clipboard restoration completes or is skipped). Used by
    /// PushToTalkManager to ignore synthetic modifier events.
    static var isPasting = false

    /// How long to wait before restoring the clipboard (100ms).
    /// Non-blocking -- runs on a background queue.
    private static let restoreDelay: TimeInterval = 0.1

    /// Polling interval for changeCount checks (10ms).
    private static let pollInterval: TimeInterval = 0.01

    /// Serial queue for clipboard restoration polling.
    private let restoreQueue = DispatchQueue(label: "com.speakeasy.clipboard-restore")

    /// Cancellation token for the pending restore.
    private var restoreWork: DispatchWorkItem?

    /// Puts the given transcription text into the clipboard, simulates a
    /// Cmd+V paste, and asynchronously restores the previous clipboard
    /// content after the target app has had time to process the paste.
    func paste(transcription: String) {
        Log.general.debug("ClipboardManager.paste() starting")
        Log.general.debug("Transcription to paste: \(transcription, privacy: .public)")

        let pasteboard = NSPasteboard.general

        // Store the current clipboard content for later restoration.
        let previousContent = pasteboard.string(forType: .string)
        Log.general.debug(
            "Previous clipboard content stored: \(previousContent ?? "nil", privacy: .public)")

        // Cancel any in-flight restoration from a previous paste.
        cancelPendingRestore()

        // Write transcription eagerly so it is immediately available
        // to any app that processes the Cmd+V.
        pasteboard.clearContents()
        pasteboard.setString(transcription, forType: .string)

        // Synchronization point: reading changeCount ensures the
        // pasteboard server has committed the write before we post
        // the CGEvent, preventing the target app from reading stale data.
        let _ = pasteboard.changeCount
        Thread.sleep(forTimeInterval: 0.01)

        // Verify transcription was set correctly.
        let clipboardAfterSet = pasteboard.string(forType: .string)
        if clipboardAfterSet != transcription {
            Log.general.error(
                "Clipboard write failed: expected \(transcription, privacy: .public), got \(clipboardAfterSet ?? "nil", privacy: .public)"
            )
        }

        // Record changeCount after our write. Any change from this value
        // means something else wrote to the clipboard.
        let ourChangeCount = pasteboard.changeCount

        // -- Simulate Cmd+V --

        Log.general.debug("Simulating Cmd+V paste operation")
        let source = CGEventSource(stateID: .hidSystemState)

        let cmdVDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        cmdVDown?.flags = .maskCommand

        let cmdVUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        cmdVUp?.flags = .maskCommand

        ClipboardManager.isPasting = true
        cmdVDown?.post(tap: .cghidEventTap)
        cmdVUp?.post(tap: .cghidEventTap)
        Log.general.debug("Cmd+V events posted")

        // -- Schedule async restoration --
        //
        // Poll changeCount on a background queue. If it changes before
        // the restore delay, another app took the clipboard and we skip
        // restoration. Otherwise, restore after the delay.

        scheduleRestore(
            expectedCount: ourChangeCount,
            previousContent: previousContent
        )

        Log.general.debug("ClipboardManager.paste() returning (restore is async)")
    }

    // MARK: - Restoration

    private func scheduleRestore(
        expectedCount: Int,
        previousContent: String?
    ) {
        let work = DispatchWorkItem { [weak self] in
            guard let self = self else { return }

            // Poll changeCount until the restore delay has elapsed.
            let deadline = Date().addingTimeInterval(Self.restoreDelay)

            while Date() < deadline {
                let currentCount = NSPasteboard.general.changeCount
                if currentCount != expectedCount {
                    // Something else wrote to the clipboard. Don't
                    // restore -- we'd clobber whatever was just written.
                    Log.general.debug(
                        "ClipboardManager: changeCount changed (\(expectedCount, privacy: .public) -> \(currentCount, privacy: .public)), skipping restore"
                    )
                    DispatchQueue.main.async {
                        ClipboardManager.isPasting = false
                    }
                    return
                }
                Thread.sleep(forTimeInterval: Self.pollInterval)
            }

            // Delay elapsed, changeCount unchanged -- safe to restore.
            DispatchQueue.main.async { [weak self] in
                guard self != nil else { return }

                // Double-check changeCount on main thread before restoring.
                let pasteboard = NSPasteboard.general
                let finalCount = pasteboard.changeCount
                if finalCount != expectedCount {
                    Log.general.debug(
                        "ClipboardManager: changeCount changed at restore time, skipping")
                    ClipboardManager.isPasting = false
                    return
                }

                Log.general.debug(
                    "Restoring previous clipboard content: \(previousContent ?? "nil", privacy: .public)"
                )
                pasteboard.clearContents()
                if let previousContent = previousContent {
                    pasteboard.setString(previousContent, forType: .string)
                }

                // Verify restoration.
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

                ClipboardManager.isPasting = false
            }
        }

        restoreWork = work
        restoreQueue.async(execute: work)
    }

    // MARK: - Cancellation

    private func cancelPendingRestore() {
        restoreWork?.cancel()
        restoreWork = nil
    }
}
