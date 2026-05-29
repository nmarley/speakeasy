import Foundation

enum TranscriptionError: Error, LocalizedError {
    case unknownError
    case noWhisperContext
    case invalidAudioFile
    case runtimeError(String)

    var errorDescription: String? {
        switch self {
        case .unknownError:
            return "Unknown transcription error"
        case .noWhisperContext:
            return "Whisper model is not loaded"
        case .invalidAudioFile:
            return "Invalid audio file"
        case .runtimeError(let message):
            return "Runtime error: \(message)"
        }
    }
}

class TranscriptionService {
    static let shared = TranscriptionService()

    private var currentTask: Task<String, Error>?

    private init() {}

    func transcribe(
        context: OpaquePointer, audioURL: URL,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        Log.general.debug("TranscriptionService.transcribe() called")
        Log.general.debug("Audio file path: \(audioURL.path, privacy: .public)")

        currentTask = Task.detached {
            let audioPath = audioURL.path

            Log.general.debug("Transcription task started, calling Rust FFI")
            let startTime = Date()

            guard let result = RustFFI.transcribeAudio(context: context, audioFilePath: audioPath)
            else {
                Log.general.error("Rust FFI transcribeAudio returned nil")
                throw TranscriptionError.unknownError
            }

            let elapsedTime = Date().timeIntervalSince(startTime)
            Log.general.debug(
                "Rust FFI call completed in \(elapsedTime, privacy: .public) seconds")
            Log.general.debug("Transcription result: \(result, privacy: .public)")

            return result
        }

        Task {
            do {
                Log.general.debug("Awaiting transcription task completion")
                let result = try await currentTask!.value
                Log.general.debug("Transcription task completed successfully")
                completion(.success(result))
            } catch {
                Log.general.error(
                    "Transcription task failed: \(error.localizedDescription, privacy: .public)")
                completion(.failure(error))
            }
        }
    }

    func cancelCurrentTranscription() {
        currentTask?.cancel()
        currentTask = nil
        Log.general.debug("Cancelled current transcription")
    }
}
