import Foundation

// Error types for transcription
enum TranscriptionError: Error, LocalizedError {
    case unknownError
    case noAPIKey
    case invalidAudioFile
    case invalidResponse
    case apiError(String)
    case retryableError(String)
    case networkError(String)
    case fileError(String)
    case timeout
    case runtimeError(String)

    var isRetryable: Bool {
        switch self {
        case .retryableError, .networkError, .timeout:
            return true
        case .noAPIKey, .invalidAudioFile, .invalidResponse, .apiError, .fileError, .runtimeError,
            .unknownError:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .unknownError:
            return "Unknown transcription error"
        case .noAPIKey:
            return "OpenAI API key is required"
        case .invalidAudioFile:
            return "Invalid audio file"
        case .invalidResponse:
            return "Invalid response from transcription service"
        case .apiError(let message):
            return "API error: \(message)"
        case .retryableError(let message):
            return "Retryable error: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .fileError(let message):
            return "File error: \(message)"
        case .timeout:
            return "Transcription request timed out"
        case .runtimeError(let message):
            return "Runtime error: \(message)"
        }
    }
}

class TranscriptionService {
    static let shared = TranscriptionService()

    private var currentTask: Task<String, Error>?

    private init() {}

    func transcribe(audioURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        Log.general.debug("TranscriptionService.transcribe() called")
        Log.general.debug("Audio file path: \(audioURL.path, privacy: .public)")

        guard SettingsManager.shared.hasOpenAIKey() else {
            Log.general.error("Transcription failed: No OpenAI API key available")
            completion(.failure(TranscriptionError.noAPIKey))
            return
        }

        guard let apiKey = SettingsManager.shared.getOpenAIKey() else {
            Log.general.error("Transcription failed: Could not retrieve OpenAI API key")
            completion(.failure(TranscriptionError.noAPIKey))
            return
        }

        Log.general.debug("API key is available, starting transcription with Rust implementation")
        Log.general.debug("API key length: \(apiKey.count, privacy: .public) characters")

        currentTask = Task.detached {
            let audioPath = audioURL.path
            let timeoutThreshold = 30.0

            Log.general.debug("Transcription task started - calling Rust FFI")
            Log.general.debug("Timeout threshold: \(timeoutThreshold, privacy: .public) seconds")

            let startTime = Date()

            guard
                let result = RustFFI.transcribeAudio(
                    audioFilePath: audioPath,
                    apiKey: apiKey,
                    timeoutThreshold: timeoutThreshold
                )
            else {
                Log.general.error("Rust FFI transcribeAudio returned nil")
                throw TranscriptionError.unknownError
            }

            let elapsedTime = Date().timeIntervalSince(startTime)
            Log.general.debug("Rust FFI call completed in \(elapsedTime, privacy: .public) seconds")
            Log.general.debug("Raw result from Rust: \(result, privacy: .public)")

            if result.starts(with: "{") {
                Log.general.debug("Result appears to be an error JSON, parsing error")
                throw self.parseRustError(result)
            } else {
                Log.general.debug("Result appears to be successful transcription")
                Log.general.debug("Transcription result: \(result, privacy: .public)")
                return result
            }
        }

        Task {
            do {
                Log.general.debug("Awaiting transcription task completion")
                let result = try await currentTask!.value
                Log.general.debug("Transcription task completed successfully")
                Log.general.debug(
                    "Final transcription result being passed to completion handler: \(result, privacy: .public)"
                )
                completion(.success(result))
            } catch {
                Log.general.error(
                    "Transcription task failed with error: \(error.localizedDescription, privacy: .public)"
                )
                Log.general.debug("Detailed transcription error: \(error, privacy: .public)")
                completion(.failure(error))
            }
        }
    }

    func cancelCurrentTranscription() {
        currentTask?.cancel()
        currentTask = nil
        Log.general.debug("Cancelled current transcription")
    }

    private func parseRustError(_ errorJson: String) -> TranscriptionError {
        guard let data = errorJson.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let errorType = json["error_type"] as? String
        else {
            return .unknownError
        }

        let message = json["message"] as? String ?? "Unknown error"

        switch errorType {
        case "NoAPIKey":
            return .noAPIKey
        case "InvalidAudioFile":
            return .invalidAudioFile
        case "InvalidResponse":
            return .invalidResponse
        case "ApiError":
            return .apiError(message)
        case "RetryableError":
            return .retryableError(message)
        case "NetworkError":
            return .networkError(message)
        case "FileError":
            return .fileError(message)
        case "Timeout":
            return .timeout
        case "RuntimeError":
            return .runtimeError(message)
        default:
            return .unknownError
        }
    }
}
