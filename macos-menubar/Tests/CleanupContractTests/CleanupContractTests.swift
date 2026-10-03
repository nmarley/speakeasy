import CleanupContract
import XCTest

final class CleanupContractTests: XCTestCase {
    func testNormalizedContentIgnoresCaseAndPunctuation() {
        XCTAssertEqual(CleanupContract.normalizedContent("Hello, World!"), "helloworld")
        XCTAssertEqual(CleanupContract.normalizedContent("Don't stop"), "dontstop")
        XCTAssertEqual(CleanupContract.normalizedContent("well-known"), "wellknown")
        XCTAssertEqual(CleanupContract.normalizedContent("well known"), "wellknown")
    }

    func testNormalizedContentKeepsAccentsAndTreatsCompositionAlike() {
        XCTAssertEqual(
            CleanupContract.normalizedContent("caf\u{00E9}"),
            CleanupContract.normalizedContent("cafe\u{0301}")
        )
        XCTAssertNotEqual(
            CleanupContract.normalizedContent("caf\u{00E9}"),
            CleanupContract.normalizedContent("cafe")
        )
    }

    func testValidationAcceptsPunctuationAndCaseChanges() {
        XCTAssertNil(
            CleanupContract.validateCleanup(
                input: "hello world lets grab lunch",
                output: "Hello, world. Let's grab lunch!"
            )
        )
    }

    func testValidationAcceptsUnchangedText() {
        XCTAssertNil(
            CleanupContract.validateCleanup(
                input: "this fucking build is broken again",
                output: "this fucking build is broken again"
            )
        )
    }

    func testValidationAcceptsTypographicApostrophe() {
        XCTAssertNil(
            CleanupContract.validateCleanup(
                input: "dont stop",
                output: "Don\u{2019}t stop."
            )
        )
    }

    func testValidationAcceptsHyphenInsertion() {
        XCTAssertNil(
            CleanupContract.validateCleanup(
                input: "a well known problem",
                output: "A well-known problem."
            )
        )
    }

    func testValidationRejectsDroppedWord() {
        XCTAssertNotNil(
            CleanupContract.validateCleanup(
                input: "this fucking build is broken again",
                output: "This build is broken again."
            )
        )
    }

    func testValidationRejectsSubstitutedWord() {
        XCTAssertNotNil(
            CleanupContract.validateCleanup(
                input: "ship the infra changes",
                output: "Ship the infrastructure changes."
            )
        )
    }

    func testValidationRejectsExpandedContraction() {
        XCTAssertNotNil(
            CleanupContract.validateCleanup(
                input: "i wanna go now",
                output: "I want to go now."
            )
        )
    }

    func testValidationRejectsAddedWord() {
        XCTAssertNotNil(
            CleanupContract.validateCleanup(
                input: "hello there",
                output: "Hello there, friend."
            )
        )
    }

    func testValidationRejectsReorderedWords() {
        XCTAssertNotNil(
            CleanupContract.validateCleanup(
                input: "deploy the parser now",
                output: "Deploy now the parser."
            )
        )
    }

    func testValidationRejectsEmptyOutput() {
        XCTAssertNotNil(
            CleanupContract.validateCleanup(input: "hello", output: "")
        )
    }

    func testValidationRejectsPromptLeak() {
        XCTAssertEqual(
            CleanupContract.validateCleanup(
                input: "hello",
                output: "I am a punctuation and capitalization engine."
            ),
            "system prompt leak detected"
        )
    }

    func testFewShotExamplesPreserveTheirTranscripts() {
        for example in CleanupContract.fewShotExamples {
            let transcript = example.user
                .replacingOccurrences(of: "<transcript>", with: "")
                .replacingOccurrences(of: "</transcript>", with: "")
            XCTAssertNil(
                CleanupContract.validateCleanup(
                    input: transcript, output: example.assistant
                ),
                "few-shot example changed content: \(example.user)"
            )
        }
    }

    func testSanitizeOutputStripsTagsAndWrappingQuotes() {
        XCTAssertEqual(
            CleanupContract.sanitizeOutput("<transcript>hello there</transcript>"),
            "hello there"
        )
        XCTAssertEqual(CleanupContract.sanitizeOutput("\"Hello there.\""), "Hello there.")
        XCTAssertEqual(CleanupContract.sanitizeOutput("'Hello there.'"), "Hello there.")
    }
}
