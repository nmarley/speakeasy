import Foundation
import OSLog

// Swift wrapper for Rust FFI functions
struct RustFFI {

    // Function declarations matching the C header
    @_silgen_name("state_machine_transition")
    private static func stateMachineTransition(_ currentState: UInt8, _ event: UInt8) -> UInt8

    @_silgen_name("state_machine_can_start_recording")
    private static func stateMachineCanStartRecording(_ state: UInt8) -> Bool

    @_silgen_name("state_machine_is_busy")
    private static func stateMachineIsBusy(_ state: UInt8) -> Bool

    @_silgen_name("state_machine_needs_setup")
    private static func stateMachineNeedsSetup(_ state: UInt8) -> Bool

    // Transcription function declarations
    @_silgen_name("transcribe_audio_blocking")
    private static func transcribeAudioBlocking(
        _ audioFilePath: UnsafePointer<CChar>,
        _ apiKey: UnsafePointer<CChar>,
        _ timeoutThreshold: Double
    ) -> UnsafeMutablePointer<CChar>?

    // Transcript cleanup function declarations
    @_silgen_name("cleanup_transcript_blocking")
    private static func cleanupTranscriptBlocking(
        _ transcript: UnsafePointer<CChar>,
        _ apiKey: UnsafePointer<CChar>
    ) -> UnsafeMutablePointer<CChar>?

    @_silgen_name("free_rust_string")
    private static func freeRustString(_ ptr: UnsafeMutablePointer<CChar>)

    // Public Swift interface for state machine
    static func transition(currentState: UInt8, event: UInt8) -> UInt8 {
        return stateMachineTransition(currentState, event)
    }

    static func canStartRecording(state: UInt8) -> Bool {
        return stateMachineCanStartRecording(state)
    }

    static func isBusy(state: UInt8) -> Bool {
        return stateMachineIsBusy(state)
    }

    static func needsSetup(state: UInt8) -> Bool {
        return stateMachineNeedsSetup(state)
    }

    // Public Swift interface for transcription
    static func transcribeAudio(audioFilePath: String, apiKey: String, timeoutThreshold: Double)
        -> String?
    {
        return audioFilePath.withCString { audioPathPtr in
            apiKey.withCString { apiKeyPtr in
                guard
                    let resultPtr = transcribeAudioBlocking(
                        audioPathPtr, apiKeyPtr, timeoutThreshold)
                else {
                    return nil
                }
                defer { freeRustString(resultPtr) }
                return String(cString: resultPtr)
            }
        }
    }

    // Public Swift interface for transcript cleanup
    static func cleanupTranscript(text: String, apiKey: String) -> String? {
        return text.withCString { textPtr in
            apiKey.withCString { apiKeyPtr in
                guard let resultPtr = cleanupTranscriptBlocking(textPtr, apiKeyPtr) else {
                    return nil
                }
                defer { freeRustString(resultPtr) }
                return String(cString: resultPtr)
            }
        }
    }
}
