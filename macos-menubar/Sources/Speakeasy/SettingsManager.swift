import Foundation

class SettingsManager {
    static let shared = SettingsManager()

    // Determine the URL for the settings file within Application Support.
    private let settingsURL: URL

    private init() {
        let fileManager = FileManager.default
        // Get the user's Application Support directory.
        let appSupportDirectory = fileManager.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        // Create a directory for Speakeasy inside Application Support (conventional for macOS apps).
        let appDirectory = appSupportDirectory.appendingPathComponent(
            "Speakeasy", isDirectory: true)
        // Place settings.json inside the Speakeasy directory.
        self.settingsURL = appDirectory.appendingPathComponent("settings.json")

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

    // Get the OpenAI API key
    func getOpenAIKey() -> String? {
        let settings = loadSettings() ?? [:]
        return settings["openai_api_key"] as? String
    }

    // Store the OpenAI API key
    func storeOpenAIKey(_ key: String) {
        var settings = loadSettings() ?? [:]
        settings["openai_api_key"] = key

        do {
            let data = try JSONSerialization.data(
                withJSONObject: settings, options: [.prettyPrinted])
            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil)
            try data.write(to: settingsURL)
            Log.general.debug("Stored OpenAI API key")
        } catch {
            Log.general.error(
                "Failed to store OpenAI API key: \(error.localizedDescription, privacy: .public)")
        }
    }

    // Check if OpenAI API key exists
    func hasOpenAIKey() -> Bool {
        return getOpenAIKey() != nil && !getOpenAIKey()!.isEmpty
    }

    // Check if transcript cleanup is enabled
    func isTranscriptCleanupEnabled() -> Bool {
        let settings = loadSettings() ?? [:]
        return settings["transcript_cleanup_enabled"] as? Bool ?? false
    }

    // Set transcript cleanup enabled/disabled
    func setTranscriptCleanupEnabled(_ enabled: Bool) {
        var settings = loadSettings() ?? [:]
        settings["transcript_cleanup_enabled"] = enabled

        do {
            let data = try JSONSerialization.data(
                withJSONObject: settings, options: [.prettyPrinted])
            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil)
            try data.write(to: settingsURL)
            Log.general.debug(
                "Transcript cleanup \(enabled ? "enabled" : "disabled", privacy: .public)")
        } catch {
            Log.general.error(
                "Failed to save transcript cleanup setting: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // Clear the OpenAI API key
    func clearOpenAIKey() {
        var settings = loadSettings() ?? [:]
        settings["openai_api_key"] = nil

        do {
            let data = try JSONSerialization.data(
                withJSONObject: settings, options: [.prettyPrinted])
            try FileManager.default.createDirectory(
                at: settingsURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil)
            try data.write(to: settingsURL)
            Log.general.debug("Cleared OpenAI API key")
        } catch {
            Log.general.error(
                "Failed to clear OpenAI API key: \(error.localizedDescription, privacy: .public)")
        }
    }
}
