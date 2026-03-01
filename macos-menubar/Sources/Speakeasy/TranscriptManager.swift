import Foundation

class TranscriptManager {
    static let shared = TranscriptManager()

    private var recentTranscripts: [String] = []
    private let maxRecentTranscripts = 2500

    func addTranscript(_ transcript: String) {
        Log.general.debug(
            "Adding transcript to history: \(transcript.prefix(30), privacy: .public)...")
        recentTranscripts.insert(transcript, at: 0)
        if recentTranscripts.count > maxRecentTranscripts {
            recentTranscripts.removeLast()
        }
        Log.general.debug(
            "Transcript history now contains \(self.recentTranscripts.count, privacy: .public) items"
        )
    }

    func getRecentTranscripts(limit: Int = 5) -> [String] {
        let transcripts = Array(recentTranscripts.prefix(limit))
        Log.general.debug(
            "Retrieved \(transcripts.count, privacy: .public) recent transcripts (requested: \(limit, privacy: .public))"
        )
        return transcripts
    }
}
