import AppKit

@main
class AppDelegate: NSObject, NSApplicationDelegate, APIKeyViewControllerDelegate {
    var statusItem: NSStatusItem?
    var pushToTalkManager: PushToTalkManager?
    var audioRecorder: AudioRecorder?
    var statusMenuItem: NSMenuItem?

    // State machine to manage app status
    private let stateMachine = RustAppStateMachine()

    private let statusOverlay = StatusOverlayController()

    // API Key popover
    var apiKeyPopover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        // Set up state machine listener to update UI
        stateMachine.addListener { [weak self] state in
            guard let self = self else { return }

            // Update UI when state changes
            DispatchQueue.main.async {
                self.refreshUI()
            }
        }

        // Initialize state machine
        stateMachine.initializeFromSettings()

        // Log current state after initialization
        Log.general.debug(
            "Current state after initialization: \(String(describing: self.stateMachine.currentState), privacy: .public)"
        )

        setupMenu()

        pushToTalkManager = PushToTalkManager()
        pushToTalkManager?.delegate = self
        // Initialize the audio recorder subsystem.
        audioRecorder = AudioRecorder()

        // Add this line to setup the state machine listener
        setupStateMachineListener()

        // Ensure UI reflects current state
        refreshUI()

        // Check Accessibility permission for keyboard monitoring
        checkAccessibilityPermission()
    }

    private func checkAccessibilityPermission() {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            Log.general.warning("Accessibility permission not granted")

            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText =
                    "Speakeasy needs Accessibility permission to monitor keyboard shortcuts (Cmd+Shift+Space). Please grant permission in System Settings."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Quit")

                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    // Open System Settings to Accessibility pane
                    if let url = URL(
                        string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                    ) {
                        NSWorkspace.shared.open(url)
                    }
                    NSApplication.shared.terminate(nil)
                } else {
                    NSApplication.shared.terminate(nil)
                }
            }
        } else {
            Log.general.info("Accessibility permission is granted")
        }
    }

    func setupMenu() {
        let menu = NSMenu()
        // Define 'status' locally from the state machine's current state.
        let status = self.stateMachine.currentState

        // Use the state machine display text and icon
        statusMenuItem = NSMenuItem(title: status.displayText, action: nil, keyEquivalent: "")
        statusMenuItem?.image = status == .ready ? AppIcons.greenStatusDot : AppIcons.redStatusDot

        menu.addItem(NSMenuItem.separator())

        statusMenuItem!.isEnabled = false
        menu.addItem(statusMenuItem!)

        // Add version menu item
        let versionItem = NSMenuItem(
            title: "Version \(Version.full)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        menu.addItem(NSMenuItem.separator())

        // Add history item with submenu
        let historyMenuItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        let historySubmenu = NSMenu(title: "Recent Transcripts")

        // Get the most recent transcripts
        let recentTranscripts = TranscriptManager.shared.getRecentTranscripts(limit: 5)

        if recentTranscripts.isEmpty {
            let emptyItem = NSMenuItem(
                title: "No recent transcripts", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            historySubmenu.addItem(emptyItem)
        } else {
            for transcript in recentTranscripts {
                // Truncate long transcripts for display
                let displayText = transcript.count > 50 ? transcript.prefix(50) + "..." : transcript
                let transcriptItem = NSMenuItem(
                    title: String(displayText),
                    action: #selector(copyTranscriptToClipboard(_:)),
                    keyEquivalent: ""
                )
                transcriptItem.representedObject = transcript
                historySubmenu.addItem(transcriptItem)
            }
        }

        historyMenuItem.submenu = historySubmenu
        menu.addItem(historyMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Add transcript cleanup toggle
        let cleanupItem = NSMenuItem(
            title: "Clean Up Transcripts",
            action: #selector(toggleTranscriptCleanup(_:)),
            keyEquivalent: ""
        )
        cleanupItem.target = self
        cleanupItem.state = SettingsManager.shared.isTranscriptCleanupEnabled() ? .on : .off
        menu.addItem(cleanupItem)

        menu.addItem(NSMenuItem.separator())

        // Add OpenAI API key management menu item
        let apiKeyTitle =
            SettingsManager.shared.hasOpenAIKey()
            ? "Manage OpenAI API Key..." : "Add OpenAI API Key..."
        let apiKeyMenuItem = NSMenuItem(
            title: apiKeyTitle, action: #selector(manageOpenAIKey(_:)),
            keyEquivalent: "")
        apiKeyMenuItem.target = self
        apiKeyMenuItem.isEnabled = true
        menu.addItem(apiKeyMenuItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(
            NSMenuItem(
                title: "Quit Speakeasy", action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"))

        statusItem?.menu = menu
    }

    @objc func toggleTranscriptCleanup(_ sender: NSMenuItem) {
        let newValue = !SettingsManager.shared.isTranscriptCleanupEnabled()
        SettingsManager.shared.setTranscriptCleanupEnabled(newValue)
        sender.state = newValue ? .on : .off
        Log.general.info(
            "Transcript cleanup toggled: \(newValue ? "on" : "off", privacy: .public)")
    }

    @objc func manageOpenAIKey(_ sender: Any?) {
        if let popover = apiKeyPopover, popover.isShown {
            popover.performClose(sender)
        } else {
            let apiKeyVC = APIKeyViewController()
            apiKeyVC.delegate = self
            let popover = NSPopover()
            popover.contentViewController = apiKeyVC
            popover.behavior = .applicationDefined
            apiKeyPopover = popover

            if let button = statusItem?.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

            }
        }
    }

    // MARK: - APIKeyViewControllerDelegate

    func apiKeyDidSave(key: String) {
        SettingsManager.shared.storeOpenAIKey(key)

        // Update state based on whether API key was provided or removed
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        Log.general.debug(
            "API key save: trimmedKey.isEmpty=\(!trimmedKey.isEmpty, privacy: .public)")

        if !trimmedKey.isEmpty {
            let success = stateMachine.process(.apiKeyProvided)
            Log.general.debug(
                "API key provided event processed: success=\(success, privacy: .public)")
        } else {
            let success = stateMachine.process(.apiKeyRemoved)
            Log.general.debug(
                "API key missing event processed: success=\(success, privacy: .public)")
        }

        // Log current state after API key save
        Log.general.debug(
            "Current state after API key save: \(String(describing: self.stateMachine.currentState), privacy: .public)"
        )

        // Use refreshUI instead of setupMenu to ensure consistent updates
        refreshUI()
        apiKeyPopover?.performClose(nil)
        Log.general.debug("OpenAI API key saved")
    }

    func apiKeyDidCancel() {
        apiKeyPopover?.performClose(nil)
    }

    static func main() {
        let app = NSApplication.shared
        // Explicitly set activation policy to .accessory to ensure event taps
        // work on Tahoe LSUIElement=true in Info.plist would default to a more
        // restrictive policy
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    private func setupStateMachineListener() {
        stateMachine.addListener { [weak self] state in
            // Update the status overlay based on the app state
            switch state {
            case .recording:
                self?.statusOverlay.updateStatus(with: "Recording")
                self?.statusOverlay.show()
            case .transcribing:
                self?.statusOverlay.updateStatus(with: "Transcribing")
                self?.statusOverlay.show()
            case .cleaningUp:
                self?.statusOverlay.updateStatus(with: "Cleaning up")
                self?.statusOverlay.show()
            default:
                // Hide the overlay for other states
                self?.statusOverlay.hide()
            }
        }
    }

    private func refreshUI() {
        // Update status bar icon
        let state = stateMachine.currentState

        if let statusButton = statusItem?.button {
            statusButton.image = NSImage(
                systemSymbolName: state.icon,
                accessibilityDescription: state.accessibilityDescription
            )
        }

        // Update menu
        setupMenu()
    }
}

extension AppDelegate: PushToTalkManagerDelegate {
    func pushToTalkDidEngage(_ manager: PushToTalkManager) {
        Log.general.debug("!!! AppDelegate.pushToTalkDidEngage called !!!")
        let startTime = Date()

        // Log current state before attempting to record
        let currentState = self.stateMachine.currentState
        Log.general.debug(
            "Push-to-talk engage - Current state: \(String(describing: currentState), privacy: .public)"
        )
        Log.general.debug(
            "Push-to-talk engage - SettingsManager.hasOpenAIKey(): \(SettingsManager.shared.hasOpenAIKey(), privacy: .public)"
        )

        // Try to start recording
        if !self.stateMachine.requestStartRecording() {
            Log.general.error(
                "Failed to transition to recording state. Current state: \(String(describing: self.stateMachine.currentState), privacy: .public)"
            )
            return
        }
        Log.general.info(
            "State transitioned in \(Date().timeIntervalSince(startTime), privacy: .public) seconds"
        )
        let recordStart = Date()
        audioRecorder?.startRecording()
        Log.general.info(
            "Recording started in \(Date().timeIntervalSince(recordStart), privacy: .public) seconds"
        )
    }

    func pushToTalkDidDisengage(_ manager: PushToTalkManager) {
        audioRecorder?.stopRecording { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let url):
                // File saved successfully, proceed with transcription
                Log.general.info("Recording finished successfully, proceeding to transcribe.")
                self.transcribeAudio(url: url)

            case .failure(let error):
                // Handle error case
                Log.general.error(
                    "Failed to stop recording or save file: \(error.localizedDescription, privacy: .public)"
                )
                // Log the full error for more details if needed
                Log.general.debug("Detailed recording stop error: \(error, privacy: .public)")

                // Transition state machine to indicate failure/readiness
                // Using .noAudioRecorded for now as it transitions back to .ready
                // Consider adding a specific .recordingFailed(Error) event later if needed.
                if !self.stateMachine.process(.noAudioRecorded) {
                    Log.general.warning("Failed to transition state after recording error.")
                }
            }
        }
    }

    func pushToTalkDidCancel(_ manager: PushToTalkManager) {
        let currentState = stateMachine.currentState

        Log.general.debug(
            "Cancel requested - Current state: \(String(describing: currentState), privacy: .public)"
        )

        // Only allow cancellation during recording, transcribing, or cleaning up states
        guard
            currentState == .recording || currentState == .transcribing
                || currentState == .cleaningUp
        else {
            Log.general.debug(
                "Cancel ignored - not in recording, transcribing, or cleaning up state")
            return
        }

        if currentState == .recording {
            // Cancel recording - stop without proceeding to transcription
            Log.general.info("Cancelling recording")
            audioRecorder?.stopRecording { [weak self] result in
                // Don't proceed to transcription regardless of result
                self?.audioRecorder?.clearRecordingURL()

                // Clean up any temporary files
                if case .success(let url) = result {
                    try? FileManager.default.removeItem(at: url)
                    Log.general.debug("Cleaned up cancelled recording file")
                }
            }
        } else if currentState == .transcribing {
            // Cancel transcription
            Log.general.info("Cancelling transcription")
            TranscriptionService.shared.cancelCurrentTranscription()

            // Clean up the recording file
            audioRecorder?.clearRecordingURL()
        } else if currentState == .cleaningUp {
            // Cancel cleanup - the blocking FFI call will finish on its own
            // but we won't use its result
            Log.general.info("Cancelling transcript cleanup")
            audioRecorder?.clearRecordingURL()
        }

        // Transition state back to ready
        if stateMachine.requestCancellation() {
            Log.general.info("Successfully cancelled operation and returned to ready state")
            // Reset toggle state in PushToTalkManager to ensure clean state
            pushToTalkManager?.resetToggleState()
        } else {
            Log.general.warning("Failed to transition state after cancellation")
        }
    }
}

extension AppDelegate {
    @objc private func copyTranscriptToClipboard(_ sender: NSMenuItem) {
        if let transcript = sender.representedObject as? String {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(transcript, forType: .string)
        }
    }

    private func finishWithTranscription(_ transcription: String) {
        Log.general.debug("Adding transcription to TranscriptManager")
        TranscriptManager.shared.addTranscript(transcription)

        DispatchQueue.main.async { [weak self] in
            _ = self?.stateMachine.process(.transcriptionCompleted, context: transcription)

            Log.general.debug(
                "About to call ClipboardManager.paste() with transcription: \(transcription, privacy: .public)"
            )
            ClipboardManager.shared.paste(transcription: transcription)
            Log.general.debug("ClipboardManager.paste() call completed")

            // Update the menu to show the new transcript in the history
            self?.setupMenu()
            Log.general.debug("Menu updated with new transcript in history")
        }
    }

    private func cleanupAndPaste(transcription: String) {
        // Transition to cleaning up state
        DispatchQueue.main.async { [weak self] in
            _ = self?.stateMachine.process(.cleanupStarted)
        }

        guard let apiKey = SettingsManager.shared.getOpenAIKey() else {
            Log.general.error("No API key available for transcript cleanup")
            // Fall back to using the raw transcription
            finishWithTranscription(transcription)
            return
        }

        Log.general.info(
            "Transcript cleanup — original (\(transcription.count, privacy: .public) chars): \(transcription, privacy: .public)"
        )

        // Run cleanup on a background thread since it's a blocking FFI call
        Task.detached { [weak self] in
            if let cleaned = RustFFI.cleanupTranscript(text: transcription, apiKey: apiKey) {
                let changed = transcription != cleaned
                Log.general.info(
                    "Transcript cleanup — cleaned (\(cleaned.count, privacy: .public) chars): \(cleaned, privacy: .public)"
                )
                Log.general.info(
                    "Transcript cleanup — changed: \(changed, privacy: .public)")
                self?.finishWithCleanedTranscription(cleaned)
            } else {
                Log.general.error(
                    "Transcript cleanup failed, falling back to original transcription")
                DispatchQueue.main.async { [weak self] in
                    _ = self?.stateMachine.process(.cleanupFailed)
                }
                // Fall back to the raw transcription
                self?.finishWithTranscription(transcription)
            }
        }
    }

    private func finishWithCleanedTranscription(_ transcription: String) {
        Log.general.debug("Adding cleaned transcription to TranscriptManager")
        TranscriptManager.shared.addTranscript(transcription)

        DispatchQueue.main.async { [weak self] in
            _ = self?.stateMachine.process(.cleanupCompleted, context: transcription)

            Log.general.debug(
                "About to call ClipboardManager.paste() with cleaned transcription: \(transcription, privacy: .public)"
            )
            ClipboardManager.shared.paste(transcription: transcription)
            Log.general.debug("ClipboardManager.paste() call completed")

            // Update the menu to show the new transcript in the history
            self?.setupMenu()
            Log.general.debug("Menu updated with new transcript in history")
        }
    }

    private func transcribeAudio(url: URL) {
        Log.general.debug(
            "AppDelegate.transcribeAudio() called with URL: \(url.path, privacy: .public)")

        if !self.stateMachine.process(.stopRecordingRequested) {
            Log.general.error("Failed to transition state to transcription")
            return
        }

        Log.general.debug(
            "State successfully transitioned to transcription, calling TranscriptionService")

        TranscriptionService.shared.transcribe(audioURL: url) { [weak self] result in
            Log.general.debug("TranscriptionService completed, processing result")
            switch result {
            case .success(let transcription):
                Log.general.debug(
                    "Transcription successful, result: \(transcription, privacy: .public)")

                // Check if transcript cleanup is enabled
                if SettingsManager.shared.isTranscriptCleanupEnabled() {
                    self?.cleanupAndPaste(transcription: transcription)
                } else {
                    self?.finishWithTranscription(transcription)
                }

                // Only clear recording URL after successful transcription
                self?.audioRecorder?.clearRecordingURL()

            case .failure(let error):
                Log.general.error(
                    "Transcription request error: \(error.localizedDescription, privacy: .public)"
                )

                // Check if this is a retryable error
                let isRetryable = (error as? TranscriptionError)?.isRetryable ?? false

                if isRetryable {
                    Log.general.debug(
                        "Transcription failed with retryable error, preserving audio file for potential retry"
                    )
                } else {
                    Log.general.debug(
                        "Transcription failed with non-retryable error, cleaning up audio file")
                    // Only clear recording URL for non-retryable errors
                    self?.audioRecorder?.clearRecordingURL()
                }

                DispatchQueue.main.async { [weak self] in
                    _ = self?.stateMachine.process(
                        .transcriptionFailed, context: error.localizedDescription)
                }
            }
        }
    }
}
