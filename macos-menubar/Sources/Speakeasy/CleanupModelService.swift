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

/// The result of one cleanup attempt: the text to paste, the reason
/// the final text failed validation (nil when it passed), and the
/// sanitized model output that was chosen. The raw transcript is
/// never returned as the result when the model produced any output;
/// a cleanup that fails validation is still pasted because a
/// slightly imperfect cleanup beats losing all punctuation.
struct CleanupOutcome {
    let text: String
    let rejectionReason: String?
    let rawOutput: String?
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
    /// Returns the cleaned transcript. Cleanup always runs: if the
    /// first attempt fails validation, a corrective retry runs, and
    /// the best cleaned output is pasted even when both attempts
    /// fail validation. The raw transcript is returned only when the
    /// model is not loaded or inference fails outright.
    func cleanupTranscript(_ transcript: String) async -> String {
        await cleanupTranscriptOutcome(transcript).text
    }

    /// Run transcript cleanup and report the validation status of the
    /// final text. Production callers use cleanupTranscript; the debug
    /// probe uses this to see the raw validation outcome.
    ///
    /// The transcript is always cleaned: the first attempt runs, and
    /// if validation rejects it, a second attempt runs with corrective
    /// feedback naming the exact dropped and added words. If both
    /// attempts fail validation, the best cleaned output is pasted
    /// anyway. The raw transcript comes back only when the model is
    /// not loaded or inference produced no output at all.
    func cleanupTranscriptOutcome(_ transcript: String) async -> CleanupOutcome {
        guard isLoaded, let container = modelContainer else {
            Log.general.error("Cleanup model not loaded, returning original transcript")
            return finishOutcome(
                input: transcript, text: transcript, reason: "model not loaded", attempts: 0
            )
        }

        let userMessage = "<transcript>\(transcript)</transcript>"

        // Cap generated tokens proportional to input length. Cleanup
        // should only add punctuation and fix capitalization, so the
        // output is slightly longer than the input. The estimate uses
        // 3 characters per token: English with punctuation added runs
        // close to that, so a 4-char estimate would truncate the
        // longest transcripts and get every word-count check rejected.
        // The floor handles very short transcripts and the cap
        // prevents runaway generation.
        let maxTokens = min(1024, max(64, transcript.count / 3))

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
            let firstRaw = try await session.respond(to: userMessage)
            let firstSanitized = CleanupContract.sanitizeOutput(firstRaw)

            if CleanupContract.validateCleanup(
                input: transcript, output: firstSanitized
            ) == nil {
                return finishOutcome(
                    input: transcript, text: firstSanitized, reason: nil, attempts: 1
                )
            }

            // The first attempt failed validation. Retry with
            // corrective feedback naming the exact dropped and added
            // words, and re-anchoring the transcript so the model
            // re-cleans the text instead of discussing the feedback.
            let firstDiff = CleanupContract.contentDiff(
                input: transcript, output: firstSanitized
            )
            let retryRaw = try await session.respond(
                to: CleanupContract.correctiveMessage(
                    firstDiff, transcript: transcript
                )
            )
            let retrySanitized = CleanupContract.sanitizeOutput(retryRaw)

            if CleanupContract.validateCleanup(
                input: transcript, output: retrySanitized
            ) == nil {
                Log.general.info("Cleanup retry passed validation")
                return finishOutcome(
                    input: transcript, text: retrySanitized, reason: nil, attempts: 2
                )
            }

            // Both attempts failed validation. Paste whichever
            // attempt kept the most of the transcript's words: a
            // slightly imperfect cleanup beats losing all
            // punctuation, so the raw transcript is never used when
            // the model produced any output.
            let retryDiff = CleanupContract.contentDiff(
                input: transcript, output: retrySanitized
            )
            let inputWordCount = CleanupContract.normalizedWords(transcript).count
            let useRetry =
                Self.cleanupScore(
                    retryDiff, inputWordCount: inputWordCount
                ) > Self.cleanupScore(firstDiff, inputWordCount: inputWordCount)
            let chosenText = useRetry ? retrySanitized : firstSanitized
            let chosenDiff = useRetry ? retryDiff : firstDiff

            if chosenText.isEmpty {
                // The model produced nothing usable twice. There is
                // no cleaned text to paste, so the raw transcript is
                // the only remaining option.
                return finishOutcome(
                    input: transcript,
                    text: transcript,
                    reason: "cleanup produced no output after retry",
                    attempts: 2
                )
            }
            let reason =
                (chosenDiff.rejectionReason ?? "empty output")
                + " (pasting cleaned output anyway)"
            return finishOutcome(
                input: transcript, text: chosenText, reason: reason, attempts: 2
            )
        } catch {
            Log.general.error(
                "Cleanup failed: \(error.localizedDescription, privacy: .public), no cleaned output available, returning original transcript"
            )
            return finishOutcome(
                input: transcript,
                text: transcript,
                reason: "inference error: \(error.localizedDescription)",
                attempts: 0
            )
        }
    }

    /// Log one cleanup run to the unified log and return the
    /// outcome. This is the single exit path for every cleanup
    /// result so the log always records exactly what was pasted and
    /// why. Details use public privacy so the full input, output,
    /// and reason are visible in `log show` / Console.
    private func finishOutcome(
        input: String, text: String, reason: String?, attempts: Int
    ) -> CleanupOutcome {
        if let reason {
            Log.cleanup.error(
                "Cleanup output not fully validated (\(reason, privacy: .public)), attempts: \(attempts, privacy: .public), input: \(input, privacy: .public), output: \(text, privacy: .public)"
            )
        } else {
            Log.cleanup.info(
                "Transcript cleanup completed: attempts: \(attempts, privacy: .public), \(input.count, privacy: .public) chars in, \(text.count, privacy: .public) chars out, input: \(input, privacy: .public), output: \(text, privacy: .public)"
            )
        }
        return CleanupOutcome(text: text, rejectionReason: reason, rawOutput: text)
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

    /// Score a failed cleanup attempt by how much of the input it
    /// kept: input words minus dropped minus added. Higher is closer
    /// to a faithful cleanup.
    private static func cleanupScore(
        _ diff: CleanupContract.ContentDiff, inputWordCount: Int
    ) -> Int {
        inputWordCount - diff.droppedWords.count - diff.addedWords.count
    }

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
