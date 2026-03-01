import AVFoundation
import AppKit
import Foundation

let SampleFreq: Int32 = 44100
let EncoderBitRate: Int32 = 64000

// Define a custom error for recording failures not covered by AVAssetWriter.error
enum AudioRecorderError: Error, LocalizedError {
    case writerNotInCorrectState(AVAssetWriter.Status)
    case writerFailedWithoutError(AVAssetWriter.Status)
    case writerUnavailable
    case cleanupFailed

    var errorDescription: String? {
        switch self {
        case .writerNotInCorrectState(let status):
            return
                "AudioRecorder Error: Asset writer was not in writing state (status: \(status.rawValue)) when stop was requested."
        case .writerFailedWithoutError(let status):
            return
                "AudioRecorder Error: Asset writer finished without error, but status was \(status.rawValue) instead of completed."
        case .writerUnavailable:
            return "AudioRecorder Error: Asset writer was nil when stop was requested."
        case .cleanupFailed:
            return "AudioRecorder Error: Failed to clean up recording file."
        }
    }
}

class AudioRecorder: NSObject {
    private(set) var recordingURL: URL?
    // Audio settings for AAC encoding
    private let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
        AVSampleRateKey: SampleFreq,
        AVNumberOfChannelsKey: 1,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
    ]

    // New properties for AVAudioEngine implementation
    private let audioEngine = AVAudioEngine()
    private var audioFile: AVAudioFile?

    // New properties for AVAssetWriter implementation
    private var assetWriter: AVAssetWriter?
    private var assetWriterInput: AVAssetWriterInput?
    private var isRecording = false
    private var sessionStarted = false

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
        // If we're recording when sleep happens, try to stop gracefully
        if isRecording {
            Log.general.debug("Recording was in progress during sleep, stopping it")
            isRecording = false
            assetWriterInput?.markAsFinished()
            // Don't call finishWriting here, as it might hang during sleep
        }

        // Reset state variables
        sessionStarted = false

        // Stop the audio engine
        if audioEngine.isRunning {
            audioEngine.stop()
            Log.general.debug("Audio engine stopped for sleep")
        }

        // Remove the asset writer and input
        assetWriter = nil
        assetWriterInput = nil
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

        // Detach the input node tap explicitly to ensure it's cleanly removed
        // before prepareAudioEngine tries to install it again.
        audioEngine.inputNode.removeTap(onBus: 0)
        Log.general.debug("Removed tap on input node.")

        // Reset internal state associated with an active recording/writer, just in case
        // This is similar to cleanup, but we don't necessarily want to delete a recordingURL here.
        isRecording = false
        sessionStarted = false
        assetWriter = nil
        assetWriterInput = nil
        // Let's keep recordingURL for now, maybe it could be recovered?
        // Or should we nil it out? Let's nil it for consistency with cleanup.
        // recordingURL = nil

        Log.general.debug("Audio state reset. Re-preparing engine after short delay.")

        // Re-prepare the engine after a short delay to allow the system to settle
        // Using a slightly shorter delay than wake, as the config change might happen quickly
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            Log.general.debug("Delay complete, calling prepareAudioEngine after config change.")
            self?.prepareAudioEngine()
        }
    }

    // Set up the audio engine to keep it "warm"
    private func prepareAudioEngine() {
        // Request microphone access first
        requestMicrophoneAccess { [weak self] granted in
            guard let self = self else { return }

            if granted {
                do {
                    // Connect the input node to the engine before starting
                    let inputNode = self.audioEngine.inputNode
                    let recordingFormat = inputNode.outputFormat(forBus: 0)

                    // Install a tap on the input node that will remain for the lifetime of the app
                    inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) {
                        [weak self] buffer, when in
                        guard let self = self, self.isRecording else { return }

                        if let sampleBuffer = self.createSampleBuffer(
                            from: buffer, presentationTime: when.cmTime)
                        {
                            // Start the session with the first buffer's timestamp
                            if !self.sessionStarted {
                                let presentationTime = CMSampleBufferGetPresentationTimeStamp(
                                    sampleBuffer)
                                self.assetWriter?.startSession(atSourceTime: presentationTime)
                                self.sessionStarted = true
                                Log.general.debug(
                                    "Recording session started at \(presentationTime.seconds, privacy: .public) seconds"
                                )
                            }

                            // Append the buffer if the writer is ready
                            if self.assetWriterInput?.isReadyForMoreMediaData == true {
                                let result = self.assetWriterInput?.append(sampleBuffer) ?? false
                                if !result {
                                    Log.general.error(
                                        "Failed to append sample buffer. AssetWriter status: \(String(describing: self.assetWriter?.status), privacy: .public), error: \(String(describing: self.assetWriter?.error), privacy: .public)"
                                    )
                                }
                            }
                        }
                    }

                    // Start the audio engine
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
        // If we have an existing asset writer, something might have gone wrong
        // This is especially important after wake from sleep
        if assetWriter != nil || assetWriterInput != nil {
            Log.general.debug(
                "Found existing AVAssetWriter when starting recording, cleaning up first")
            cleanupAudioResourcesForSleep()

            // Make sure the audio engine is running
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

        // Create a temporary file URL for the recording
        let tempDirectory = FileManager.default.temporaryDirectory
        let filename = "speakeasy_recording_\(Date().timeIntervalSince1970).m4a"
        let fileURL = tempDirectory.appendingPathComponent(filename)

        Log.general.debug("Audio file will be written to: \(fileURL.path, privacy: .public)")
        Log.general.debug("Temporary directory: \(tempDirectory.path, privacy: .public)")
        Log.general.debug("Generated filename: \(filename, privacy: .public)")

        // Remove any existing file at this URL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            Log.general.debug("Removing existing file at path: \(fileURL.path, privacy: .public)")
            try? FileManager.default.removeItem(at: fileURL)
        }

        let startTime = Date()

        // Get the input node and its format
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        // Define audio settings for AAC encoding
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: recordingFormat.sampleRate,
            AVNumberOfChannelsKey: recordingFormat.channelCount,
            AVEncoderBitRateKey: EncoderBitRate,
        ]

        do {
            // Create the asset writer with proper settings
            assetWriter = try AVAssetWriter(outputURL: fileURL, fileType: .m4a)

            // Set the preferred output settings
            assetWriter?.movieTimeScale = SampleFreq

            // Create and configure the writer input with proper track settings
            let inputSettings: [String: Any] = audioSettings
            assetWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: inputSettings)
            assetWriterInput?.expectsMediaDataInRealTime = true

            // Set proper track properties to match the "good" file's tkhd flags
            assetWriterInput?.transform = CGAffineTransform.identity
            assetWriterInput?.preferredVolume = 1.0

            if let writer = assetWriter, let writerInput = assetWriterInput {
                if writer.canAdd(writerInput) {
                    writer.add(writerInput)

                    // Start writing
                    writer.startWriting()
                    sessionStarted = false

                    // Set recording flag to true to start processing buffers
                    isRecording = true
                    recordingURL = fileURL

                    Log.general.info("Recording started successfully")
                    Log.general.info("Audio file location: \(fileURL.path, privacy: .public)")
                    Log.general.info(
                        "File exists after creation: \(FileManager.default.fileExists(atPath: fileURL.path), privacy: .public)"
                    )
                    Log.general.info(
                        "Recording setup completed in \(Date().timeIntervalSince(startTime), privacy: .public) seconds"
                    )
                } else {
                    Log.general.error("Could not add writer input to asset writer")
                }
            }
        } catch {
            Log.general.error("Failed to start recording: \(error, privacy: .public)")
        }
    }

    func stopRecording(completion: @escaping (Result<URL, Error>) -> Void) {
        // Stop recording by setting the flag to false
        // Do this early so the tap callback stops trying to append buffers
        isRecording = false

        // Check if the recording might have been finalized during sleep cleanup
        // If the engine isn't running OR the writer is nil, it indicates a potential post-sleep scenario
        if !audioEngine.isRunning || assetWriter == nil {
            Log.general.debug(
                "Checking for pre-sleep finalization: Engine Running: \(self.audioEngine.isRunning, privacy: .public), Asset Writer: \(self.assetWriter == nil ? "nil" : "exists", privacy: .public)"
            )

            // If we have a recordingURL and the file exists, assume it was finalized successfully during sleep cleanup
            if let url = recordingURL, FileManager.default.fileExists(atPath: url.path) {
                Log.general.info("Found existing recording file after sleep/wake")
                Log.general.info("Audio file location: \(url.path, privacy: .public)")
                Log.general.info(
                    "File size: \((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0, privacy: .public) bytes"
                )
                // Clear the internal state *except* the URL, which is the result
                self.assetWriter = nil
                self.assetWriterInput = nil
                self.sessionStarted = false
                // Complete with success, passing the existing URL
                completion(.success(url))
                // Important: Do not call clearRecordingURL here, the caller needs the URL.
            } else {
                // Engine not running/writer nil, AND no valid file found. This is the original error case.
                Log.general.warning(
                    "Audio engine stopped or writer nil, and no valid recording file found. Reporting failure."
                )
                // Clean up internal state fully
                self.assetWriter = nil
                self.assetWriterInput = nil
                self.sessionStarted = false
                self.recordingURL = nil  // Clear URL as it's invalid/missing
                // Report failure
                completion(.failure(AudioRecorderError.writerUnavailable))
            }
            return  // Exit after handling the post-sleep cases
        }

        // If we reach here, the engine is running and the writer exists (normal stop scenario)
        // The assetWriter is guaranteed non-nil here due to the check above.
        guard self.assetWriter != nil else {
            // This path should be logically unreachable, but assert for safety.
            assertionFailure("Asset writer was unexpectedly nil after engine/writer check.")
            completion(.failure(AudioRecorderError.writerUnavailable))
            return
        }

        // Finalize the asset writer
        guard let writer = assetWriter else {
            Log.general.error("Asset writer is nil, cannot stop recording.")
            // Clean up potentially dangling state
            self.assetWriterInput = nil
            self.sessionStarted = false
            completion(.failure(AudioRecorderError.writerUnavailable))
            return
        }

        // Log status *before* attempting to finish
        Log.general.debug(
            "Attempting to stop recording. AssetWriter status: \(writer.status.rawValue, privacy: .public)"
        )

        // Special handling for failure states that might occur after sleep
        if writer.status == .failed {
            Log.general.warning(
                "AVAssetWriter in failed state before finishWriting (possibly post-sleep)")

            // Clean up resources
            assetWriter = nil
            assetWriterInput = nil
            sessionStarted = false

            // If we have a recording URL, it might be partial/corrupt, clean it up
            if let url = recordingURL, FileManager.default.fileExists(atPath: url.path) {
                try? FileManager.default.removeItem(at: url)
                Log.general.debug("Removed possibly corrupt recording file from failed writer")
                recordingURL = nil
            }

            // Report the writer's error or a generic one
            if let error = writer.error {
                completion(.failure(error))
            } else {
                completion(.failure(AudioRecorderError.writerFailedWithoutError(writer.status)))
            }
            return
        }

        if writer.status == .writing {
            // Mark the input as finished
            assetWriterInput?.markAsFinished()

            // Capture the current recording URL
            let currentRecordingURL = recordingURL

            // Finish writing
            writer.finishWriting { [weak self] in
                guard let self = self else {
                    // If self is nil, we can't determine success/failure accurately,
                    // but it's likely a failure scenario or edge case.
                    completion(.failure(AudioRecorderError.writerUnavailable))  // Or a more specific error
                    return
                }

                // Log status *after* finishing attempt
                Log.general.debug(
                    "finishWriting completed. AssetWriter status: \(writer.status.rawValue, privacy: .public)"
                )

                // Check for errors first
                if let error = writer.error {
                    // Log the detailed error
                    let nsError = error as NSError
                    Log.general.error(
                        """
                        Error finishing asset writer:
                        Domain: \(nsError.domain, privacy: .public),
                        Code: \(nsError.code, privacy: .public),
                        LocalizedDescription: \(error.localizedDescription, privacy: .public),
                        UserInfo: \(nsError.userInfo, privacy: .public)
                        """
                    )
                    completion(.failure(error))
                } else if writer.status == .completed, let fileURL = currentRecordingURL {
                    // Success case
                    Log.general.info("Recording stopped successfully")
                    Log.general.info("Final audio file location: \(fileURL.path, privacy: .public)")
                    Log.general.info(
                        "Final file size: \((try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.intValue ?? 0, privacy: .public) bytes"
                    )
                    Log.general.info(
                        "File exists: \(FileManager.default.fileExists(atPath: fileURL.path), privacy: .public)"
                    )
                    completion(.success(fileURL))
                } else {
                    // Handle cases where finishWriting didn't error but status isn't completed
                    let status = writer.status
                    Log.general.error(
                        "Asset writer finished without error, but status is \(status.rawValue, privacy: .public) (\(String(describing: status), privacy: .public)) instead of completed. URL: \(currentRecordingURL?.path ?? "nil", privacy: .public)"
                    )
                    completion(.failure(AudioRecorderError.writerFailedWithoutError(status)))
                }

                // Clean up internal state regardless of success/failure
                self.assetWriter = nil
                self.assetWriterInput = nil
                self.sessionStarted = false
            }
        } else {
            // Writer was not in the expected .writing state
            let status = writer.status
            Log.general.error(
                "Asset writer not in writing state (\(status.rawValue, privacy: .public)) when stopRecording called. Cannot finish writing."
            )
            // Clean up even if we didn't call finishWriting
            self.assetWriter = nil
            self.assetWriterInput = nil
            self.sessionStarted = false
            completion(.failure(AudioRecorderError.writerNotInCorrectState(status)))
        }
    }

    /// Converts the incoming AVAudioPCMBuffer to a CMSampleBuffer for AVAssetWriter
    private func createSampleBuffer(from buffer: AVAudioPCMBuffer, presentationTime: CMTime)
        -> CMSampleBuffer?
    {
        // Define timing using the original buffer's frame count
        var timing = CMSampleTimingInfo(
            duration: CMTime(
                value: CMTimeValue(buffer.frameLength),
                timescale: CMTimeScale(buffer.format.sampleRate)),
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: CMTime.invalid)

        // Convert from the native format to 16-bit integer interleaved PCM
        guard
            let dstFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: buffer.format.sampleRate,
                channels: buffer.format.channelCount,
                interleaved: true)
        else {
            Log.general.error("Failed to create destination format")
            return nil
        }

        guard let converter = AVAudioConverter(from: buffer.format, to: dstFormat) else {
            Log.general.error("Failed to initialize audio converter")
            return nil
        }

        guard
            let int16Buffer = AVAudioPCMBuffer(
                pcmFormat: dstFormat, frameCapacity: buffer.frameCapacity)
        else {
            Log.general.error("Failed to allocate int16Buffer")
            return nil
        }
        int16Buffer.frameLength = buffer.frameLength

        var conversionError: NSError? = nil
        let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        converter.convert(to: int16Buffer, error: &conversionError, withInputFrom: inputBlock)
        if let error = conversionError {
            Log.general.error("Audio conversion error: \(error, privacy: .public)")
            return nil
        }

        // Create a format description from the int16 format
        var audioFormatDescription: CMAudioFormatDescription?
        var asbd = int16Buffer.format.streamDescription.pointee
        let status = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &audioFormatDescription
        )
        if status != noErr {
            Log.general.error(
                "CMAudioFormatDescriptionCreate failed with status \(status, privacy: .public)")
            return nil
        }

        // Create a CMBlockBuffer from the int16 data
        var blockBuffer: CMBlockBuffer?
        let mDataByteSize =
            Int(int16Buffer.frameLength)
            * Int(int16Buffer.format.streamDescription.pointee.mBytesPerFrame)
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: mDataByteSize,
            blockAllocator: nil,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: mDataByteSize,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        if blockStatus != kCMBlockBufferNoErr {
            Log.general.error(
                "CMBlockBufferCreateWithMemoryBlock failed with status \(blockStatus)")
            return nil
        }

        if let dataPointer = int16Buffer.int16ChannelData {
            // Assuming interleaved data, use the first channel pointer
            let bytes = UnsafeMutableRawPointer(dataPointer[0])
            let replaceStatus = CMBlockBufferReplaceDataBytes(
                with: bytes,
                blockBuffer: blockBuffer!,
                offsetIntoDestination: 0,
                dataLength: mDataByteSize
            )
            if replaceStatus != kCMBlockBufferNoErr {
                Log.general.error(
                    "CMBlockBufferReplaceDataBytes failed with status \(replaceStatus)")
                return nil
            }
        } else {
            Log.general.error("Unable to get int16ChannelData")
            return nil
        }

        var sampleBuffer: CMSampleBuffer?
        let result = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: audioFormatDescription,
            sampleCount: CMItemCount(int16Buffer.frameLength),
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        if result != noErr {
            Log.general.error("CMSampleBufferCreate failed with status \(result, privacy: .public)")
            return nil
        }

        return sampleBuffer
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

// Extension to convert AVAudioTime to CMTime
extension AVAudioTime {
    var cmTime: CMTime {
        return CMTimeMake(value: Int64(self.sampleTime), timescale: Int32(self.sampleRate))
    }
}
