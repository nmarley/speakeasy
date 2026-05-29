import AVFoundation
import AppKit
import Foundation

let WhisperSampleRate: Double = 16000

enum AudioRecorderError: Error, LocalizedError {
    case audioFileCreationFailed
    case noAudioRecorded
    case engineNotRunning
    case cleanupFailed

    var errorDescription: String? {
        switch self {
        case .audioFileCreationFailed:
            return "AudioRecorder Error: Failed to create audio output file."
        case .noAudioRecorded:
            return "AudioRecorder Error: No audio data was recorded."
        case .engineNotRunning:
            return "AudioRecorder Error: Audio engine was not running when stop was requested."
        case .cleanupFailed:
            return "AudioRecorder Error: Failed to clean up recording file."
        }
    }
}

class AudioRecorder: NSObject {
    private(set) var recordingURL: URL?

    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var converter: AVAudioConverter?
    private var isRecording = false

    // Sleep/wake notification observers
    private var sleepObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var configChangeObserver: NSObjectProtocol?  // Observer for configuration changes

    // Add initializer to warm up the audio engine
    override init() {
        super.init()

        // Set up and prepare the audio engine
        prepareAudioEngine()

        // Register for sleep/wake notifications
        registerForSleepWakeNotifications()
    }

    deinit {
        // Remove notification observers
        if let sleepObserver = sleepObserver {
            NotificationCenter.default.removeObserver(sleepObserver)
        }

        if let wakeObserver = wakeObserver {
            NotificationCenter.default.removeObserver(wakeObserver)
        }

        if let configChangeObserver = configChangeObserver {  // Remove config change observer
            NotificationCenter.default.removeObserver(configChangeObserver)
        }
    }

    private func registerForSleepWakeNotifications() {
        // Register for sleep notification
        sleepObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Log.general.debug("System is going to sleep, cleaning up audio resources")
            self?.cleanupAudioResourcesForSleep()
        }

        // Register for wake notification
        wakeObserver = NotificationCenter.default.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Log.general.debug("System woke from sleep, reinitializing audio engine")
            self?.reinitializeAudioEngine()
        }

        // Register for engine configuration changes
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,  // Observe changes specifically for our engine instance
            queue: .main
        ) { [weak self] _ in
            Log.general.info(
                "Received AVAudioEngineConfigurationChangeNotification, handling reset.")
            self?.handleConfigurationChange()
        }
    }

    private func cleanupAudioResourcesForSleep() {
        if isRecording {
            Log.general.debug("Recording was in progress during sleep, stopping it")
            isRecording = false
        }

        audioFile = nil
        converter = nil

        if audioEngine.isRunning {
            audioEngine.stop()
            Log.general.debug("Audio engine stopped for sleep")
        }
    }

    private func reinitializeAudioEngine() {
        // Called after wake. We rely on handleConfigurationChange to perform the heavy reset
        // if the engine configuration actually changed. Here, we just ensure
        // prepareAudioEngine is called after a delay to give the system time to settle.

        Log.general.debug("Wake detected. Scheduling prepareAudioEngine after delay.")

        // Wait a moment before potentially restarting (give the system time to fully wake up
        // and potentially post a configuration change notification).
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }

            // Only prepare if the engine isn't already running (e.g., if config change handled it)
            // Although prepareAudioEngine should be safe to call even if running, this avoids redundancy.
            if !self.audioEngine.isRunning {
                Log.general.debug(
                    "Engine not running after wake delay, calling prepareAudioEngine.")
                self.prepareAudioEngine()
            } else {
                Log.general.debug(
                    "Engine already running after wake delay (likely handled by config change), skipping prepareAudioEngine call."
                )
            }

            // Original log message kept for consistency if needed, but maybe less accurate now:
            // Log.general.debug("Audio engine reinitialized after wake")
        }
    }

    private func handleConfigurationChange() {
        Log.general.debug(
            "Handling configuration change: Stopping engine and preparing for re-initialization.")

        // Ensure the engine is stopped
        if audioEngine.isRunning {
            audioEngine.stop()
            Log.general.debug("Stopped audio engine due to configuration change.")
        }

        audioEngine.inputNode.removeTap(onBus: 0)
        Log.general.debug("Removed tap on input node.")

        isRecording = false
        audioFile = nil
        converter = nil

        Log.general.debug("Audio state reset. Re-preparing engine after short delay.")

        // Re-prepare the engine after a short delay to allow the system to settle
        // Using a slightly shorter delay than wake, as the config change might happen quickly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            Log.general.debug("Delay complete, calling prepareAudioEngine after config change.")
            self?.prepareAudioEngine()
        }
    }

    private func prepareAudioEngine() {
        requestMicrophoneAccess { [weak self] granted in
            guard let self = self else { return }

            if granted {
                do {
                    let inputNode = self.audioEngine.inputNode
                    let inputFormat = inputNode.outputFormat(forBus: 0)

                    inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
                        [weak self] buffer, _ in
                        guard let self = self, self.isRecording,
                            let audioFile = self.audioFile,
                            let converter = self.converter
                        else { return }

                        let ratio = WhisperSampleRate / inputFormat.sampleRate
                        let outputFrameCount =
                            AVAudioFrameCount(Double(buffer.frameLength) * ratio)

                        guard
                            let outputBuffer = AVAudioPCMBuffer(
                                pcmFormat: converter.outputFormat,
                                frameCapacity: outputFrameCount)
                        else { return }

                        var error: NSError?
                        var inputConsumed = false
                        let inputBlock: AVAudioConverterInputBlock = {
                            _, outStatus in
                            if inputConsumed {
                                outStatus.pointee = .noDataNow
                                return nil
                            }
                            inputConsumed = true
                            outStatus.pointee = .haveData
                            return buffer
                        }

                        converter.convert(
                            to: outputBuffer, error: &error, withInputFrom: inputBlock)
                        if let error = error {
                            Log.general.error(
                                "Audio conversion error: \(error, privacy: .public)")
                            return
                        }

                        if outputBuffer.frameLength > 0 {
                            do {
                                try audioFile.write(from: outputBuffer)
                            } catch {
                                Log.general.error(
                                    "Failed to write audio buffer: \(error, privacy: .public)")
                            }
                        }
                    }

                    try self.audioEngine.start()
                    Log.general.info("Audio engine started and ready for recording")
                } catch {
                    Log.general.error("Failed to start audio engine: \(error, privacy: .public)")
                }
            } else {
                Log.general.error("Microphone access denied")
            }
        }
    }

    func startRecording() {
        if audioFile != nil {
            Log.general.debug(
                "Found existing audio file when starting recording, cleaning up first")
            cleanupAudioResourcesForSleep()

            if !audioEngine.isRunning {
                Log.general.debug("Audio engine not running, restarting it")
                do {
                    try audioEngine.start()
                } catch {
                    Log.general.error(
                        "Failed to restart audio engine before recording: \(error, privacy: .public)"
                    )
                }
            }
        }

        let tempDirectory = FileManager.default.temporaryDirectory
        let filename = "speakeasy_recording_\(Date().timeIntervalSince1970).wav"
        let fileURL = tempDirectory.appendingPathComponent(filename)

        Log.general.debug("Audio file will be written to: \(fileURL.path, privacy: .public)")

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }

        let startTime = Date()

        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: WhisperSampleRate,
                channels: 1,
                interleaved: true)
        else {
            Log.general.error("Failed to create 16KHz mono PCM format")
            return
        }

        let inputFormat = audioEngine.inputNode.outputFormat(forBus: 0)
        guard let newConverter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            Log.general.error("Failed to create audio converter")
            return
        }

        do {
            audioFile = try AVAudioFile(
                forWriting: fileURL,
                settings: outputFormat.settings,
                commonFormat: .pcmFormatInt16,
                interleaved: true)
            converter = newConverter
            isRecording = true
            recordingURL = fileURL

            Log.general.info("Recording started successfully")
            Log.general.info("Audio file location: \(fileURL.path, privacy: .public)")
            Log.general.info(
                "Recording setup completed in \(Date().timeIntervalSince(startTime), privacy: .public) seconds"
            )
        } catch {
            Log.general.error("Failed to start recording: \(error, privacy: .public)")
        }
    }

    func stopRecording(completion: @escaping (Result<URL, Error>) -> Void) {
        isRecording = false

        // Close the audio file by releasing the reference
        let finishedFile = audioFile
        audioFile = nil
        converter = nil

        guard finishedFile != nil else {
            Log.general.warning("No audio file was open when stop was requested")
            if let url = recordingURL, FileManager.default.fileExists(atPath: url.path) {
                Log.general.info("Found existing recording file, returning it")
                completion(.success(url))
            } else {
                recordingURL = nil
                completion(.failure(AudioRecorderError.noAudioRecorded))
            }
            return
        }

        guard let fileURL = recordingURL, FileManager.default.fileExists(atPath: fileURL.path)
        else {
            Log.general.error("Recording file missing after stop")
            recordingURL = nil
            completion(.failure(AudioRecorderError.noAudioRecorded))
            return
        }

        let fileSize =
            (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?
            .intValue ?? 0
        Log.general.info("Recording stopped successfully")
        Log.general.info("Final audio file location: \(fileURL.path, privacy: .public)")
        Log.general.info("Final file size: \(fileSize, privacy: .public) bytes")
        completion(.success(fileURL))
    }

    func clearRecordingURL() {
        Log.general.info("Clearing recording URL")
        self.recordingURL = nil
        Log.general.info(
            "done, self.recordingURL: \(self.recordingURL != nil ? "\(self.recordingURL!)" : "nil", privacy: .public)"
        )
    }

    // Helper method to request microphone access
    private func requestMicrophoneAccess(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    completion(granted)
                }
            }
        default:
            completion(false)
        }
    }
}
