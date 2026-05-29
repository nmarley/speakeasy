import Foundation

// MARK: - Swift Enums (Mirror the Rust ones)
enum RustAppState: UInt8, CaseIterable, CustomStringConvertible {
    case needsModel = 0
    case ready = 1
    case recording = 2
    case transcribing = 3
    case cleaningUp = 4

    // UI Properties
    var displayText: String {
        switch self {
        case .needsModel: return "Model required"
        case .ready: return "Ready"
        case .recording: return "Recording..."
        case .transcribing: return "Transcribing..."
        case .cleaningUp: return "Cleaning up..."
        }
    }

    var accessibilityDescription: String {
        switch self {
        case .needsModel: return "Whisper model is required"
        case .ready: return "Ready to record"
        case .recording: return "Recording in progress"
        case .transcribing: return "Transcribing audio"
        case .cleaningUp: return "Cleaning up transcript"
        }
    }

    var icon: String {
        switch self {
        case .needsModel: return "exclamationmark.triangle"
        case .ready: return "mic"
        case .recording: return "record.circle"
        case .transcribing: return "waveform"
        case .cleaningUp: return "text.badge.checkmark"
        }
    }

    var description: String { displayText }
}

enum RustAppEvent: UInt8, CaseIterable {
    case modelLoaded = 0
    case modelRemoved = 1
    case startRecordingRequested = 2
    case stopRecordingRequested = 3
    case transcriptionCompleted = 4
    case transcriptionFailed = 5
    case noAudioRecorded = 6
    case cancellationRequested = 7
    case cleanupStarted = 8
    case cleanupCompleted = 9
    case cleanupFailed = 10
}

// MARK: - Swift State Machine (Callbacks live here!)
class RustAppStateMachine {
    // Current state
    private(set) var currentState: RustAppState {
        didSet {
            // Debug logging
            if currentState != oldValue {
                Log.general.debug(
                    "State transition: \(oldValue, privacy: .public) -> \(self.currentState, privacy: .public)"
                )
            }
        }
    }

    // Listeners (ALL callback management in Swift!)
    private var listeners: [(RustAppState) -> Void] = []

    // Additional state for UI (not managed by Rust)
    private(set) var lastError: String?
    private(set) var lastTranscription: String?

    init(initialState: RustAppState = .needsModel) {
        self.currentState = initialState
    }

    // MARK: - Listener Management (Pure Swift)
    func addListener(_ listener: @escaping (RustAppState) -> Void) {
        listeners.append(listener)
        // Immediately call with current state
        listener(currentState)
    }

    func removeAllListeners() {
        listeners.removeAll()
    }

    // MARK: - Event Processing (Rust does logic, Swift does callbacks)
    @discardableResult
    func process(_ event: RustAppEvent, context: String? = nil) -> Bool {
        // Store context for events that need it
        switch event {
        case .transcriptionCompleted, .cleanupCompleted:
            lastTranscription = context
        case .transcriptionFailed, .cleanupFailed:
            lastError = context
        default:
            break
        }

        // Ask Rust for the new state (NO CALLBACKS!)
        let newStateRaw = RustFFI.transition(
            currentState: currentState.rawValue, event: event.rawValue)
        guard let newState = RustAppState(rawValue: newStateRaw) else {
            Log.general.error("Invalid state returned from Rust: \(newStateRaw, privacy: .public)")
            return false
        }

        // Update state if changed
        if newState != currentState {
            currentState = newState

            // Clear context when appropriate
            if newState == .ready {
                lastError = nil
            }

            // Notify all listeners (PURE SWIFT CALLBACKS!)
            notifyListeners()
            return true
        }

        return false
    }

    private func notifyListeners() {
        listeners.forEach { $0(currentState) }
    }

    // MARK: - Query Methods (Delegate to Rust)
    var canStartRecording: Bool {
        RustFFI.canStartRecording(state: currentState.rawValue)
    }

    var isBusy: Bool {
        RustFFI.isBusy(state: currentState.rawValue)
    }

    var needsSetup: Bool {
        RustFFI.needsSetup(state: currentState.rawValue)
    }

    // MARK: - User-Friendly Methods
    var recordingBlockedReason: String? {
        guard !canStartRecording else { return nil }

        switch currentState {
        case .needsModel:
            return "A Whisper model is required for voice recording."
        case .recording:
            return "Already recording."
        case .transcribing:
            return "Please wait for transcription to complete."
        case .cleaningUp:
            return "Please wait for transcript cleanup to complete."
        case .ready:
            return nil  // This shouldn't happen
        }
    }

    // MARK: - Convenience Methods for AppDelegate
    func handleModelChange(hasModel: Bool) {
        let event: RustAppEvent = hasModel ? .modelLoaded : .modelRemoved
        process(event)
    }

    func handleTranscriptionResult(_ result: Result<String, Error>) {
        switch result {
        case .success(let transcription):
            process(.transcriptionCompleted, context: transcription)
        case .failure(let error):
            process(.transcriptionFailed, context: error.localizedDescription)
        }
    }

    // MARK: - Debug Methods
    func debugDescription() -> String {
        """
        Current State: \(currentState)
        Can Start Recording: \(canStartRecording)
        Is Busy: \(isBusy)
        Needs Setup: \(needsSetup)
        Last Error: \(lastError ?? "none")
        Last Transcription: \(lastTranscription ?? "none")
        """
    }
}

// MARK: - Integration with Existing AppDelegate
extension RustAppStateMachine {

    /// Call this in applicationDidFinishLaunching
    func initializeFromSettings() {
        let hasModel = SettingsManager.shared.hasModel()
        handleModelChange(hasModel: hasModel)
    }

    /// Call this from push-to-talk engage
    func requestStartRecording() -> Bool {
        guard canStartRecording else {
            Log.general.error(
                "requestStartRecording aborted: canStartRecording is false. Current state: \(self.currentState, privacy: .public)"
            )
            return false
        }

        Log.general.debug(
            "requestStartRecording: Proceeding to process .startRecordingRequested event.")
        return process(.startRecordingRequested)
    }

    /// Call this from push-to-talk disengage
    func requestStopRecording() -> Bool {
        return process(.stopRecordingRequested)
    }

    /// Call this when recording fails to start
    func reportNoAudio() {
        process(.noAudioRecorded)
    }

    /// Call this to cancel current recording or transcription
    func requestCancellation() -> Bool {
        return process(.cancellationRequested)
    }
}
