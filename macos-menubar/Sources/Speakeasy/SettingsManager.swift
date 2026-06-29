import Foundation

class SettingsManager {
    static let shared = SettingsManager()

    // Determine the URL for the settings file within Application Support.
    private let settingsURL: URL

    // Application Support directory for Speakeasy
    let appDirectory: URL

    // Models directory inside Application Support
    var modelsDirectory: URL {
        appDirectory.appendingPathComponent("models", isDirectory: true)
    }

    // Default model path inside Application Support
    var defaultModelPath: String {
        modelsDirectory
            .appendingPathComponent("ggml-small.en.bin")
            .path
    }

    // Human-readable name of the default model
    static let defaultModelName = "small.en"

    // Size of the default model (for display purposes)
    static let defaultModelSize = "466 MB"

    // Download URL for the default model
    static let defaultModelURL = URL(
        string:
            "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin"
    )!

    private init() {
        let fileManager = FileManager.default
        let appSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let appDir = appSupportDirectory.appendingPathComponent(
            "Speakeasy", isDirectory: true)
        self.appDirectory = appDir
        self.settingsURL = appDir.appendingPathComponent("settings.json")

        Log.general.debug("Using settings file: \(self.settingsURL.path, privacy: .public)")
    }

    // Loads and returns the JSON settings if available.
    func loadSettings() -> [String: Any]? {
        if !FileManager.default.fileExists(atPath: settingsURL.path) {
            return nil
        }

        do {
            let data = try Data(contentsOf: settingsURL)
            let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
            return json
        } catch {
            Log.general.error(
                "Failed to load settings: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func saveSettings(_ settings: [String: Any]) {
        do {
            let data = try JSONSerialization.data(
                withJSONObject: settings, options: [.prettyPrinted])
            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil)
            try data.write(to: settingsURL)
        } catch {
            Log.general.error(
                "Failed to save settings: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Whisper Model

    // Returns the stored model path, or the default path if none is stored.
    func modelPath() -> String {
        let settings = loadSettings() ?? [:]
        if let stored = settings["model_path"] as? String, !stored.isEmpty {
            return stored
        }
        return defaultModelPath
    }

    // Store a custom model path.
    func setModelPath(_ path: String) {
        var settings = loadSettings() ?? [:]
        settings["model_path"] = path
        saveSettings(settings)
        Log.general.debug("Stored model path: \(path, privacy: .public)")
    }

    // Ensure the models directory exists, creating it if necessary.
    func ensureModelsDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: modelsDirectory,
            withIntermediateDirectories: true,
            attributes: nil
        )
    }

    // Check whether the model file exists on disk at the configured path.
    func hasModel() -> Bool {
        let path = modelPath()
        let exists = FileManager.default.fileExists(atPath: path)
        Log.general.debug(
            "Model check: path=\(path, privacy: .public) exists=\(exists, privacy: .public)")
        return exists
    }

    // Returns the file size of the model on disk, or nil if it does not exist.
    func modelFileSize() -> Int64? {
        let path = modelPath()
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
            let size = attrs[.size] as? Int64
        else {
            return nil
        }
        return size
    }

    // Delete the downloaded model file.
    func deleteModel() throws {
        let path = modelPath()
        guard FileManager.default.fileExists(atPath: path) else { return }
        try FileManager.default.removeItem(atPath: path)
        Log.general.info("Deleted model at: \(path, privacy: .public)")
    }

    // MARK: - Transcript Cleanup

    func isTranscriptCleanupEnabled() -> Bool {
        let settings = loadSettings() ?? [:]
        // Default to true now that cleanup runs locally via MLX.
        // The setting key may be absent on first launch or after
        // upgrading from an older version that defaulted to false.
        if let value = settings["transcript_cleanup_enabled"] as? Bool {
            return value
        }
        return true
    }

    func setTranscriptCleanupEnabled(_ enabled: Bool) {
        var settings = loadSettings() ?? [:]
        settings["transcript_cleanup_enabled"] = enabled
        saveSettings(settings)
        Log.general.debug(
            "Transcript cleanup \(enabled ? "enabled" : "disabled", privacy: .public)")
    }
}
