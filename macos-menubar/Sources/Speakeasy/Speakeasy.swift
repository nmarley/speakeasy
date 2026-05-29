import AppKit

@main
class AppDelegate: NSObject, NSApplicationDelegate, APIKeyViewControllerDelegate,
    ModelManagementViewControllerDelegate
{
    var statusItem: NSStatusItem?
    var pushToTalkManager: PushToTalkManager?
    var audioRecorder: AudioRecorder?
    var statusMenuItem: NSMenuItem?

    // State machine to manage app status
    private let stateMachine = RustAppStateMachine()

    private let statusOverlay = StatusOverlayController()

    // Whisper model context (loaded once, held for app lifetime)
    private var whisperContext: OpaquePointer?

    // Popovers
    var apiKeyPopover: NSPopover?
    var modelPopover: NSPopover?

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

        // Initialize state machine (checks whether model file exists)
        stateMachine.initializeFromSettings()

        // Load Whisper model if available
        loadWhisperModel()

        // Log current state after initialization
        Log.general.debug(
            "Current state after initialization: \(String(describing: self.stateMachine.currentState), privacy: .public)"
        )

        setupMenu()

        pushToTalkManager = PushToTalkManager()
        pushToTalkManager?.delegate = self
        audioRecorder = AudioRecorder()

        setupStateMachineListener()

        // Ensure UI reflects current state
        refreshUI()

        // Check Accessibility permission for keyboard monitoring
        checkAccessibilityPermission()

        // First-run: if no model is available, prompt to download
        if stateMachine.needsSetup {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.showModelManagement(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let ctx = whisperContext {
            Log.general.debug("Destroying Whisper context")
            RustFFI.destroyWhisperContext(ctx)
            whisperContext = nil
        }
    }

    private func loadWhisperModel() {
        guard SettingsManager.shared.hasModel() else {
            Log.general.info("No Whisper model found, staying in needsModel state")
            return
        }

        let modelPath = SettingsManager.shared.modelPath()
        Log.general.info("Loading Whisper model from: \(modelPath, privacy: .public)")

        if let ctx = RustFFI.initWhisperContext(modelPath: modelPath) {
            whisperContext = ctx
            Log.general.info("Whisper model loaded successfully")
        } else {
            Log.general.error("Failed to load Whisper model from: \(modelPath, privacy: .public)")
            // State machine stays in needsModel since we could not load it
            stateMachine.handleModelChange(hasModel: false)
        }
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
        let status = self.stateMachine.currentState

        statusMenuItem = NSMenuItem(title: status.displayText, action: nil, keyEquivalent: "")
        statusMenuItem?.image = status == .ready ? AppIcons.greenStatusDot : AppIcons.redStatusDot

        menu.addItem(NSMenuItem.separator())

        statusMenuItem!.isEnabled = false
        menu.addItem(statusMenuItem!)

        let versionItem = NSMenuItem(
            title: "Version \(Version.full)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        menu.addItem(NSMenuItem.separator())

        // History submenu
        let historyMenuItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        let historySubmenu = NSMenu(title: "Recent Transcripts")

        let recentTranscripts = TranscriptManager.shared.getRecentTranscripts(limit: 5)

        if recentTranscripts.isEmpty {
            let emptyItem = NSMenuItem(
                title: "No recent transcripts", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            historySubmenu.addItem(emptyItem)
        } else {
            for transcript in recentTranscripts {
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

        // Model management
        let modelTitle: String
        if SettingsManager.shared.hasModel() {
            modelTitle = "Model: \(SettingsManager.defaultModelName)"
        } else if ModelDownloadService.shared.isDownloading {
            modelTitle = "Downloading Model..."
        } else {
            modelTitle = "Download Model..."
        }
        let modelMenuItem = NSMenuItem(
            title: modelTitle, action: #selector(showModelManagement(_:)),
            keyEquivalent: "")
        modelMenuItem.target = self
        menu.addItem(modelMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Transcript cleanup toggle
        let cleanupItem = NSMenuItem(
            title: "Clean Up Transcripts",
            action: #selector(toggleTranscriptCleanup(_:)),
            keyEquivalent: ""
        )
        cleanupItem.target = self
        cleanupItem.state = SettingsManager.shared.isTranscriptCleanupEnabled() ? .on : .off
        menu.addItem(cleanupItem)

        // OpenAI API key management (only needed for cleanup feature)
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

    @objc func showModelManagement(_ sender: Any?) {
        if let popover = modelPopover, popover.isShown {
            popover.performClose(sender)
        } else {
            let modelVC = ModelManagementViewController(
                hasModel: SettingsManager.shared.hasModel())
            modelVC.delegate = self
            let popover = NSPopover()
            popover.contentViewController = modelVC
            popover.behavior = .applicationDefined
            modelPopover = popover

            if let button = statusItem?.button {
                popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            }
        }
    }

    // MARK: - ModelManagementViewControllerDelegate

    func modelDidFinishDownloading(modelPath: String) {
        Log.general.info("Model download complete, loading Whisper context")
        stateMachine.handleModelChange(hasModel: true)
        loadWhisperModel()
        refreshUI()
    }

    func modelManagementDidClose() {
        modelPopover?.performClose(nil)
    }

    func modelDidDelete() {
        if let ctx = whisperContext {
            RustFFI.destroyWhisperContext(ctx)
            whisperContext = nil
        }
        stateMachine.handleModelChange(hasModel: false)
        refreshUI()
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
        refreshUI()
        apiKeyPopover?.performClose(nil)
        Log.general.debug("OpenAI API key saved (used for transcript cleanup)")
    }

    func apiKeyDidCancel() {
        apiKeyPopover?.performClose(nil)
    }

    static func main() {
        let app = NSApplication.shared
        // Explicitly set activation policy to .accessory to ensure event taps
        // work on Tahoe (LSUIElement=true in Info.plist would default to a more
        // restrictive policy)
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    private func setupStateMachineListener() {
        stateMachine.addListener { [weak self] state in
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
                self?.statusOverlay.hide()
            }
        }
    }

    private func refreshUI() {
        let state = stateMachine.currentState

        if let statusButton = statusItem?.button {
            statusButton.image = NSImage(
                systemSymbolName: state.icon,
                accessibilityDescription: state.accessibilityDescription
            )
        }

        setupMenu()
    }
}

extension AppDelegate: PushToTalkManagerDelegate {
    func pushToTalkDidEngage(_ manager: PushToTalkManager) {
        Log.general.debug("AppDelegate.pushToTalkDidEngage called")
        let startTime = Date()

        let currentState = self.stateMachine.currentState
        Log.general.debug(
            "Push-to-talk engage - Current state: \(String(describing: currentState), privacy: .public)"
        )

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
                Log.general.info("Recording finished successfully, proceeding to transcribe.")
                self.transcribeAudio(url: url)

            case .failure(let error):
                Log.general.error(
                    "Failed to stop recording or save file: \(error.localizedDescription, privacy: .public)"
                )
                Log.general.debug("Detailed recording stop error: \(error, privacy: .public)")

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

        guard
            currentState == .recording || currentState == .transcribing
                || currentState == .cleaningUp
        else {
            Log.general.debug(
                "Cancel ignored - not in recording, transcribing, or cleaning up state")
            return
        }

        if currentState == .recording {
            Log.general.info("Cancelling recording")
            audioRecorder?.stopRecording { [weak self] result in
                self?.audioRecorder?.clearRecordingURL()

                if case .success(let url) = result {
                    try? FileManager.default.removeItem(at: url)
                    Log.general.debug("Cleaned up cancelled recording file")
                }
            }
        } else if currentState == .transcribing {
            Log.general.info("Cancelling transcription")
            TranscriptionService.shared.cancelCurrentTranscription()
            audioRecorder?.clearRecordingURL()
        } else if currentState == .cleaningUp {
            Log.general.info("Cancelling transcript cleanup")
            audioRecorder?.clearRecordingURL()
        }

        if stateMachine.requestCancellation() {
            Log.general.info("Successfully cancelled operation and returned to ready state")
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

            self?.setupMenu()
            Log.general.debug("Menu updated with new transcript in history")
        }
    }

    private func cleanupAndPaste(transcription: String) {
        DispatchQueue.main.async { [weak self] in
            _ = self?.stateMachine.process(.cleanupStarted)
        }

        guard let apiKey = SettingsManager.shared.getOpenAIKey() else {
            Log.general.error("No API key available for transcript cleanup")
            finishWithTranscription(transcription)
            return
        }

        Log.general.info(
            "Transcript cleanup - original (\(transcription.count, privacy: .public) chars): \(transcription, privacy: .public)"
        )

        Task.detached { [weak self] in
            if let cleaned = RustFFI.cleanupTranscript(text: transcription, apiKey: apiKey) {
                let changed = transcription != cleaned
                Log.general.info(
                    "Transcript cleanup - cleaned (\(cleaned.count, privacy: .public) chars): \(cleaned, privacy: .public)"
                )
                Log.general.info(
                    "Transcript cleanup - changed: \(changed, privacy: .public)")
                self?.finishWithCleanedTranscription(cleaned)
            } else {
                Log.general.error(
                    "Transcript cleanup failed, falling back to original transcription")
                DispatchQueue.main.async { [weak self] in
                    _ = self?.stateMachine.process(.cleanupFailed)
                }
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

            self?.setupMenu()
            Log.general.debug("Menu updated with new transcript in history")
        }
    }

    private func transcribeAudio(url: URL) {
        Log.general.debug(
            "AppDelegate.transcribeAudio() called with URL: \(url.path, privacy: .public)")

        guard let ctx = whisperContext else {
            Log.general.error("No Whisper context available for transcription")
            _ = stateMachine.process(.transcriptionFailed, context: "Whisper model not loaded")
            return
        }

        if !self.stateMachine.process(.stopRecordingRequested) {
            Log.general.error("Failed to transition state to transcription")
            return
        }

        Log.general.debug(
            "State successfully transitioned to transcription, calling TranscriptionService")

        TranscriptionService.shared.transcribe(context: ctx, audioURL: url) { [weak self] result in
            Log.general.debug("TranscriptionService completed, processing result")
            switch result {
            case .success(let transcription):
                Log.general.debug(
                    "Transcription successful, result: \(transcription, privacy: .public)")

                if SettingsManager.shared.isTranscriptCleanupEnabled() {
                    self?.cleanupAndPaste(transcription: transcription)
                } else {
                    self?.finishWithTranscription(transcription)
                }

                self?.audioRecorder?.clearRecordingURL()

            case .failure(let error):
                Log.general.error(
                    "Transcription failed: \(error.localizedDescription, privacy: .public)"
                )
                self?.audioRecorder?.clearRecordingURL()

                DispatchQueue.main.async { [weak self] in
                    _ = self?.stateMachine.process(
                        .transcriptionFailed, context: error.localizedDescription)
                }
            }
        }
    }
}
