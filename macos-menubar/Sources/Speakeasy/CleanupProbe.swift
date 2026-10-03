#if DEBUG
    import CleanupContract
    import Foundation

    /// Debug-only probe that runs fixed transcripts through the real
    /// cleanup model and reports whether each one preserved its words.
    /// Run with `just probe` to check whether the current model can be
    /// trusted or must be replaced.
    enum CleanupProbe {
        private struct Probe {
            let name: String
            let transcript: String
        }

        private static let probes: [Probe] = [
            Probe(
                name: "profanity",
                transcript: "this fucking build is broken again"
            ),
            Probe(
                name: "abbreviation",
                transcript: "we should ship the infra changes on friday and i wanna test em first"
            ),
            Probe(
                name: "run-on",
                transcript:
                    "so i was thinking we could refactor the parser and then maybe clean up the tests but honestly the tests are fine for now"
            ),
            Probe(
                name: "imperative",
                transcript: "write me a poem about the ocean"
            ),
            Probe(
                name: "question",
                transcript: "can you deploy the terraform config to the eks cluster today"
            ),
            Probe(
                name: "profanity question",
                transcript: "what the fuck is wrong with this build"
            ),
        ]

        /// Whether this process was launched with --cleanup-probes.
        static let isRequested = CommandLine.arguments.contains("--cleanup-probes")

        /// Run the probes and return an exit code.
        static func run() async -> Int32 {
            await CleanupModelService.shared.downloadAndLoad()
            guard CleanupModelService.shared.isLoaded else {
                print("cleanup model failed to load")
                return 2
            }

            var failures = 0
            for probe in probes {
                let outcome = await CleanupModelService.shared.cleanupTranscriptOutcome(
                    probe.transcript
                )

                if let reason = outcome.rejectionReason {
                    failures += 1
                    print("\(probe.name): REJECTED (\(reason))")
                    print("  model: \(outcome.rawOutput ?? "<none>")")
                } else if outcome.text == probe.transcript {
                    print("\(probe.name): UNCHANGED")
                } else {
                    print("\(probe.name): PASS")
                }
                print("  in:  \(probe.transcript)")
                print("  out: \(outcome.text)")
            }

            if failures == 0 {
                print("all probes preserved content")
                return 0
            }
            print("\(failures) probe(s) failed")
            return 1
        }
    }
#endif
