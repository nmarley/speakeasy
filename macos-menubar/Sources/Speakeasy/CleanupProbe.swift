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
            Probe(
                name: "long ramble",
                transcript:
                    "ok so the plan for tomorrow is to start with the database migration and then once that's done we can move on to the api layer but i think we should really focus on getting the auth flow working first because without that nothing else really matters and honestly if we can't get the login page sorted by friday then the whole demo is going to fall apart so let's prioritize that and then circle back to the migration"
            ),
            Probe(
                name: "very long dictation",
                transcript:
                    "so this morning i woke up and checked the ci pipeline and of course it was red again which was super frustrating because i had fixed it the night before or at least i thought i had and it turns out the flaky test in the payments module was failing intermittently so i reran it three times and it passed twice which means it's still flaky and we need to quarantine it before someone spends their whole day chasing a ghost anyway after that i jumped on the standup call and we talked about the release schedule for next week and whether we should hold the release until the migration is done or ship it behind a feature flag which honestly seems like the better option because the migration is risky and if it goes sideways we'd have to roll back the whole release and that would be a nightmare so my action items from the meeting were to write up the feature flag proposal and send it to the team by end of day and also to ping the platform team about getting a staging database provisioned because apparently that request got lost somewhere in their backlog and nobody has looked at it in two weeks which is just fantastic and then in the afternoon i reviewed a couple of pull requests and left comments on both of them mostly about error handling because people keep forgetting to unwrap their optionals safely and then finally right before end of day i started writing the migration script itself and got about halfway through before i realized i needed to double check the schema on production because the docs are out of date and nobody has updated them since march so tomorrow i need to finish the migration script verify the schema and finish the feature flag proposal which should all be doable if there are no surprises"
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
