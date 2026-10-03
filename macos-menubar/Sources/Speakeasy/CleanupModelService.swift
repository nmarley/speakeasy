import CleanupContract
import Foundation
import HuggingFace
import MLX
import MLXHuggingFace
import MLXLLM
import MLXLMCommon
import Tokenizers

protocol CleanupModelServiceDelegate: AnyObject {
    func cleanupModelDidUpdateProgress(_ progress: Double)
    func cleanupModelDidComplete()
    func cleanupModelDidFail(error: Error)
}

/// Manages the local LLM used for transcript cleanup.
///
/// Downloads, loads, and runs a Qwen2.5 1.5B Instruct 4-bit model via
/// MLX on the Metal GPU. The model stays resident in memory after first
/// load for fast subsequent cleanup calls.
class CleanupModelService {
    static let shared = CleanupModelService()

    weak var delegate: CleanupModelServiceDelegate?

    static let modelName = "Qwen2.5 1.5B"
    static let modelSize = "~1 GB"

    private(set) var isDownloading = false
    private(set) var isLoaded = false

    private var modelContainer: ModelContainer?

    private init() {}

    /// Check if the cleanup model has been downloaded to the HuggingFace cache.
    ///
    /// MLX downloads models into the HuggingFace hub cache directory
    /// (typically ~/.cache/huggingface/hub on non-sandboxed macOS).
    /// We check for the model's snapshot directory to determine if a
    /// download has completed.
    func hasModel() -> Bool {
        let modelId = LLMRegistry.qwen2_5_1_5b.name
        let cacheDir = huggingFaceCacheDirectory()
        let modelDir = cacheDir.appendingPathComponent(
            "models--\(modelId.replacingOccurrences(of: "/", with: "--"))"
        )
        let snapshotsDir = modelDir.appendingPathComponent("snapshots")
        let exists = FileManager.default.fileExists(atPath: snapshotsDir.path)
        Log.general.debug(
            "Cleanup model check: \(modelDir.path, privacy: .public) exists=\(exists, privacy: .public)"
        )
        return exists
    }

    /// Download (if needed) and load the cleanup model into memory.
    ///
    /// If the model is already loaded, this returns immediately.
    /// If the model is already in the HuggingFace cache, the download
    /// step is effectively a no-op and the model loads from disk.
    /// Progress callbacks are sent to the delegate during download.
    func downloadAndLoad() async {
        if isLoaded {
            delegate?.cleanupModelDidComplete()
            return
        }

        isDownloading = true

        do {
            Log.general.info("Loading cleanup model via MLX...")

            // Install the Swift error handler before any MLX GPU
            // initialization. Without this, MLX's default C error
            // handler calls exit(-1) on any failure (e.g. missing
            // metallib), crashing the app with no recovery path.
            _ = MLXArray(0)

            let container = try await #huggingFaceLoadModelContainer(
                configuration: LLMRegistry.qwen2_5_1_5b
            ) { [weak self] progress in
                guard let self else { return }
                let fraction = progress.fractionCompleted
                Log.general.debug(
                    "Cleanup model download progress: \(fraction, privacy: .public)"
                )
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.cleanupModelDidUpdateProgress(fraction)
                }
            }

            isDownloading = false
            modelContainer = container
            isLoaded = true

            Log.general.info("Cleanup model loaded successfully")
            delegate?.cleanupModelDidComplete()
        } catch {
            isDownloading = false
            Log.general.error(
                "Failed to load cleanup model: \(error.localizedDescription, privacy: .public)"
            )
            delegate?.cleanupModelDidFail(error: error)
        }
    }

    /// Cancel an in-progress download.
    func cancelDownload() {
        // The HuggingFace download is managed internally by the HubClient.
        // We reset state; the actual download task will fail/complete on its own.
        isDownloading = false
        Log.general.info("Cleanup model download cancelled")
    }

    /// Run transcript cleanup on the given text.
    ///
    /// Returns the cleaned transcript, or the original text if cleanup
    /// fails for any reason (model not loaded, inference error, etc.).
    /// This matches the fallback behavior of the former OpenAI path.
    func cleanupTranscript(_ transcript: String) async -> String {
        guard isLoaded, let container = modelContainer else {
            Log.general.error("Cleanup model not loaded, returning original transcript")
            return transcript
        }

        let userMessage = "<transcript>\(transcript)</transcript>"

        // Cap generated tokens proportional to input length. Cleanup
        // should only add punctuation and fix capitalization, so the
        // output is at most slightly longer than the input. The floor
        // handles very short transcripts and the cap prevents runaway
        // generation. Roughly 1 token per 4 characters of input.
        let maxTokens = min(512, max(64, transcript.count / 4))

        // Build a fresh, isolated session for every cleanup. Reusing a
        // single long-lived session let its KV cache accumulate prior
        // transcripts and responses, so identical input could clean
        // differently depending on history. Constructing the session
        // per call from the cached container guarantees a clean context
        // each time. Greedy decode (temperature 0) makes each cleanup
        // deterministic and reproducible.
        let session = ChatSession(
            container,
            instructions: CleanupContract.systemPrompt,
            history: Self.chatHistory(),
            generateParameters: GenerateParameters(
                maxTokens: maxTokens,
                temperature: 0
            )
        )

        do {
            let result = try await session.respond(to: userMessage)

            let sanitized = CleanupContract.sanitizeOutput(result)

            if let rejectionReason = CleanupContract.validateCleanup(
                input: transcript, output: sanitized
            ) {
                Log.general.error(
                    "Cleanup model output rejected (\(rejectionReason, privacy: .public)), returning original transcript"
                )
                return transcript
            }

            Log.general.info(
                "Transcript cleanup completed: \(transcript.count, privacy: .public) chars in, \(sanitized.count, privacy: .public) chars out"
            )
            return sanitized
        } catch {
            Log.general.error(
                "Cleanup failed: \(error.localizedDescription, privacy: .public), returning original transcript"
            )
            return transcript
        }
    }

    /// Unload the model from memory.
    func unload() {
        modelContainer = nil
        isLoaded = false
        Log.general.info("Cleanup model unloaded")
    }

    /// Delete the downloaded model from the HuggingFace cache.
    func deleteModel() throws {
        unload()

        let modelId = LLMRegistry.qwen2_5_1_5b.name
        let cacheDir = huggingFaceCacheDirectory()
        let modelDir = cacheDir.appendingPathComponent(
            "models--\(modelId.replacingOccurrences(of: "/", with: "--"))"
        )

        if FileManager.default.fileExists(atPath: modelDir.path) {
            try FileManager.default.removeItem(at: modelDir)
            Log.general.info("Deleted cleanup model at: \(modelDir.path, privacy: .public)")
        }
    }

    /// Returns the file size of the downloaded model, or nil if not present.
    func modelFileSize() -> Int64? {
        let modelId = LLMRegistry.qwen2_5_1_5b.name
        let cacheDir = huggingFaceCacheDirectory()
        let modelDir = cacheDir.appendingPathComponent(
            "models--\(modelId.replacingOccurrences(of: "/", with: "--"))"
        )

        guard FileManager.default.fileExists(atPath: modelDir.path) else { return nil }

        return directorySize(at: modelDir)
    }

    // MARK: - Private

    /// Flatten the contract's few-shot pairs into the user/assistant
    /// message history injected before each cleanup call.
    private static func chatHistory() -> [Chat.Message] {
        CleanupContract.fewShotExamples.flatMap { example in
            [Chat.Message.user(example.user), .assistant(example.assistant)]
        }
    }

    private func huggingFaceCacheDirectory() -> URL {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        return
            home
            .appendingPathComponent(".cache")
            .appendingPathComponent("huggingface")
            .appendingPathComponent("hub")
    }

    private func directorySize(at url: URL) -> Int64 {
        var total: Int64 = 0
        if let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey])
        {
            for case let fileURL as URL in enumerator {
                if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                    let size = attrs[.size] as? Int64
                {
                    total += size
                }
            }
        }
        return total
    }
}
