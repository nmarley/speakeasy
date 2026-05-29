import Foundation

class SettingsManager {
    static let shared = SettingsManager()

    // Determine the URL for the settings file within Application Support.
    private let settingsURL: URL

    // Application Support directory for Speakeasy
    let appDirectory: URL

    // Default model path inside Application Support
    var defaultModelPath: String {
        appDirectory
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("ggml-small.en.bin")
            .path
    }

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

    // Check whether the model file exists on disk at the configured path.
    func hasModel() -> Bool {
        let path = modelPath()
        let exists = FileManager.default.fileExists(atPath: path)
        Log.general.debug(
            "Model check: path=\(path, privacy: .public) exists=\(exists, privacy: .public)")
        return exists
    }

    // MARK: - OpenAI API Key (optional, only needed for transcript cleanup)

    func getOpenAIKey() -> String? {
        let settings = loadSettings() ?? [:]
        return settings["openai_api_key"] as? String
    }

    func storeOpenAIKey(_ key: String) {
        var settings = loadSettings() ?? [:]
        settings["openai_api_key"] = key
        saveSettings(settings)
        Log.general.debug("Stored OpenAI API key")
    }

    func hasOpenAIKey() -> Bool {
        guard let key = getOpenAIKey() else { return false }
        return !key.isEmpty
    }

    func clearOpenAIKey() {
        var settings = loadSettings() ?? [:]
        settings["openai_api_key"] = nil
        saveSettings(settings)
        Log.general.debug("Cleared OpenAI API key")
    }

    // MARK: - Transcript Cleanup

    func isTranscriptCleanupEnabled() -> Bool {
        let settings = loadSettings() ?? [:]
        return settings["transcript_cleanup_enabled"] as? Bool ?? false
    }

    func setTranscriptCleanupEnabled(_ enabled: Bool) {
        var settings = loadSettings() ?? [:]
        settings["transcript_cleanup_enabled"] = enabled
        saveSettings(settings)
        Log.general.debug(
            "Transcript cleanup \(enabled ? "enabled" : "disabled", privacy: .public)")
    }
}
