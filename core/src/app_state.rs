use serde::{Deserialize, Serialize};

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AppState {
    NeedsApiKey = 0,
    Ready = 1,
    Recording = 2,
    Transcribing = 3,
    CleaningUp = 4,
}

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AppEvent {
    ApiKeyProvided = 0,
    ApiKeyRemoved = 1,
    StartRecordingRequested = 2,
    StopRecordingRequested = 3,
    TranscriptionCompleted = 4,
    TranscriptionFailed = 5,
    NoAudioRecorded = 6,
    CancellationRequested = 7,
    CleanupStarted = 8,
    CleanupCompleted = 9,
    CleanupFailed = 10,
}

impl From<u8> for AppState {
    fn from(value: u8) -> Self {
        match value {
            0 => AppState::NeedsApiKey,
            1 => AppState::Ready,
            2 => AppState::Recording,
            3 => AppState::Transcribing,
            4 => AppState::CleaningUp,
            _ => AppState::NeedsApiKey, // Default fallback
        }
    }
}

impl From<u8> for AppEvent {
    fn from(value: u8) -> Self {
        match value {
            0 => AppEvent::ApiKeyProvided,
            1 => AppEvent::ApiKeyRemoved,
            2 => AppEvent::StartRecordingRequested,
            3 => AppEvent::StopRecordingRequested,
            4 => AppEvent::TranscriptionCompleted,
            5 => AppEvent::TranscriptionFailed,
            6 => AppEvent::NoAudioRecorded,
            7 => AppEvent::CancellationRequested,
            8 => AppEvent::CleanupStarted,
            9 => AppEvent::CleanupCompleted,
            10 => AppEvent::CleanupFailed,
            _ => AppEvent::ApiKeyProvided, // Default fallback
        }
    }
}

// Core state transition logic
fn transition(current_state: AppState, event: AppEvent) -> AppState {
    use AppEvent::*;
    use AppState::*;

    match (current_state, event) {
        // API Key management
        (NeedsApiKey, ApiKeyProvided) => Ready,
        (Ready, ApiKeyRemoved) => NeedsApiKey,

        // Recording flow (only works with API key present = Ready state)
        (Ready, StartRecordingRequested) => Recording,
        (Recording, StopRecordingRequested) => Transcribing,
        (Recording, NoAudioRecorded) => Ready,
        (Transcribing, TranscriptionCompleted) => Ready,
        (Transcribing, TranscriptionFailed) => Ready,

        // Transcript cleanup flow
        (Transcribing, CleanupStarted) => CleaningUp,
        (CleaningUp, CleanupCompleted) => Ready,
        (CleaningUp, CleanupFailed) => Ready,

        // Cancellation - return to ready from active states
        (Recording, CancellationRequested) => Ready,
        (Transcribing, CancellationRequested) => Ready,
        (CleaningUp, CancellationRequested) => Ready,

        // API key removed during active states - reset to needs setup
        (Recording | Transcribing | CleaningUp, ApiKeyRemoved) => NeedsApiKey,

        // All other transitions are invalid - no state change
        _ => current_state,
    }
}

// Query functions (pure, no side effects)
fn can_start_recording(state: AppState) -> bool {
    matches!(state, AppState::Ready)
}

fn is_busy(state: AppState) -> bool {
    matches!(
        state,
        AppState::Recording | AppState::Transcribing | AppState::CleaningUp
    )
}

fn needs_setup(state: AppState) -> bool {
    matches!(state, AppState::NeedsApiKey)
}

fn has_error(_state: AppState) -> bool {
    // In API key mode, no persistent error states
    // Errors are transient (handled by Swift layer)
    false
}

// FFI Interface - Pure functions only, no callbacks!
#[unsafe(no_mangle)]
pub extern "C" fn state_machine_transition(current_state: u8, event: u8) -> u8 {
    let state = AppState::from(current_state);
    let evt = AppEvent::from(event);
    let new_state = transition(state, evt);
    new_state as u8
}

#[unsafe(no_mangle)]
pub extern "C" fn state_machine_can_start_recording(state: u8) -> bool {
    can_start_recording(AppState::from(state))
}

#[unsafe(no_mangle)]
pub extern "C" fn state_machine_is_busy(state: u8) -> bool {
    is_busy(AppState::from(state))
}

#[unsafe(no_mangle)]
pub extern "C" fn state_machine_needs_setup(state: u8) -> bool {
    needs_setup(AppState::from(state))
}

#[unsafe(no_mangle)]
pub extern "C" fn state_machine_has_error(state: u8) -> bool {
    has_error(AppState::from(state))
}

// Validation function for debugging
#[unsafe(no_mangle)]
pub extern "C" fn state_machine_is_valid_transition(current_state: u8, event: u8) -> bool {
    let state = AppState::from(current_state);
    let evt = AppEvent::from(event);
    let new_state = transition(state, evt);
    new_state != state
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_basic_flow() {
        // Start with no API key
        let mut state = AppState::NeedsApiKey;

        // Add API key
        state = transition(state, AppEvent::ApiKeyProvided);
        assert_eq!(state, AppState::Ready);
        assert!(can_start_recording(state));

        // Start recording
        state = transition(state, AppEvent::StartRecordingRequested);
        assert_eq!(state, AppState::Recording);
        assert!(!can_start_recording(state));
        assert!(is_busy(state));

        // Stop recording
        state = transition(state, AppEvent::StopRecordingRequested);
        assert_eq!(state, AppState::Transcribing);
        assert!(is_busy(state));

        // Complete transcription
        state = transition(state, AppEvent::TranscriptionCompleted);
        assert_eq!(state, AppState::Ready);
        assert!(can_start_recording(state));
        assert!(!is_busy(state));
    }

    #[test]
    fn test_invalid_transitions() {
        // Can't record without API key
        let state = AppState::NeedsApiKey;
        let new_state = transition(state, AppEvent::StartRecordingRequested);
        assert_eq!(new_state, AppState::NeedsApiKey); // No change

        // Can't start recording while already recording
        let state = AppState::Recording;
        let new_state = transition(state, AppEvent::StartRecordingRequested);
        assert_eq!(new_state, AppState::Recording); // No change
    }

    #[test]
    fn test_api_key_only_flow() {
        // Test the complete API-key-only flow
        let mut state = AppState::NeedsApiKey;

        // Can't do anything without API key
        assert!(!can_start_recording(state));
        assert!(needs_setup(state));
        assert!(!has_error(state)); // No persistent error states

        // Add API key - now ready
        state = transition(state, AppEvent::ApiKeyProvided);
        assert_eq!(state, AppState::Ready);
        assert!(can_start_recording(state));
        assert!(!needs_setup(state));

        // Full recording cycle
        state = transition(state, AppEvent::StartRecordingRequested);
        assert_eq!(state, AppState::Recording);
        assert!(!can_start_recording(state));
        assert!(is_busy(state));

        state = transition(state, AppEvent::StopRecordingRequested);
        assert_eq!(state, AppState::Transcribing);
        assert!(!can_start_recording(state));
        assert!(is_busy(state));

        state = transition(state, AppEvent::TranscriptionCompleted);
        assert_eq!(state, AppState::Ready);
        assert!(can_start_recording(state));
        assert!(!is_busy(state));

        // Test transcription failure path
        state = transition(state, AppEvent::StartRecordingRequested);
        state = transition(state, AppEvent::StopRecordingRequested);
        state = transition(state, AppEvent::TranscriptionFailed);
        assert_eq!(state, AppState::Ready); // Back to ready after failure

        // Test no audio recorded path
        state = transition(state, AppEvent::StartRecordingRequested);
        state = transition(state, AppEvent::NoAudioRecorded);
        assert_eq!(state, AppState::Ready); // Back to ready

        // Remove API key - back to setup
        state = transition(state, AppEvent::ApiKeyRemoved);
        assert_eq!(state, AppState::NeedsApiKey);
        assert!(!can_start_recording(state));
        assert!(needs_setup(state));
    }

    #[test]
    fn test_api_key_removed_during_recording() {
        // Test what happens if API key is removed while recording/transcribing
        let mut state = AppState::Ready;

        // Start recording
        state = transition(state, AppEvent::StartRecordingRequested);
        assert_eq!(state, AppState::Recording);

        // API key removed during recording
        state = transition(state, AppEvent::ApiKeyRemoved);
        assert_eq!(state, AppState::NeedsApiKey);

        // Similar test for transcribing
        state = AppState::Transcribing;
        state = transition(state, AppEvent::ApiKeyRemoved);
        assert_eq!(state, AppState::NeedsApiKey);
    }

    #[test]
    fn test_ffi_interface() {
        // Test the FFI functions work correctly
        let state = AppState::NeedsApiKey as u8;
        let event = AppEvent::ApiKeyProvided as u8;

        let new_state = state_machine_transition(state, event);
        assert_eq!(new_state, AppState::Ready as u8);

        assert!(!state_machine_can_start_recording(state));
        assert!(state_machine_can_start_recording(new_state));
        assert!(state_machine_needs_setup(state));
        assert!(!state_machine_needs_setup(new_state));
    }

    #[test]
    fn test_cleanup_flow() {
        // Full flow with cleanup
        let mut state = AppState::Ready;

        state = transition(state, AppEvent::StartRecordingRequested);
        assert_eq!(state, AppState::Recording);

        state = transition(state, AppEvent::StopRecordingRequested);
        assert_eq!(state, AppState::Transcribing);

        // Transcription done, start cleanup
        state = transition(state, AppEvent::CleanupStarted);
        assert_eq!(state, AppState::CleaningUp);
        assert!(is_busy(state));

        // Cleanup completes
        state = transition(state, AppEvent::CleanupCompleted);
        assert_eq!(state, AppState::Ready);
        assert!(!is_busy(state));
    }

    #[test]
    fn test_cleanup_failure() {
        let mut state = AppState::Transcribing;

        state = transition(state, AppEvent::CleanupStarted);
        assert_eq!(state, AppState::CleaningUp);

        state = transition(state, AppEvent::CleanupFailed);
        assert_eq!(state, AppState::Ready);
    }

    #[test]
    fn test_cleanup_cancellation() {
        let mut state = AppState::CleaningUp;

        state = transition(state, AppEvent::CancellationRequested);
        assert_eq!(state, AppState::Ready);
    }

    #[test]
    fn test_cleanup_api_key_removed() {
        let mut state = AppState::CleaningUp;

        state = transition(state, AppEvent::ApiKeyRemoved);
        assert_eq!(state, AppState::NeedsApiKey);
    }

    #[test]
    fn test_cleanup_only_from_transcribing() {
        // CleanupStarted should be a no-op from non-Transcribing states
        let state = AppState::Ready;
        assert_eq!(transition(state, AppEvent::CleanupStarted), AppState::Ready);

        let state = AppState::Recording;
        assert_eq!(
            transition(state, AppEvent::CleanupStarted),
            AppState::Recording
        );

        let state = AppState::NeedsApiKey;
        assert_eq!(
            transition(state, AppEvent::CleanupStarted),
            AppState::NeedsApiKey
        );
    }

    #[test]
    fn test_cancellation_transitions() {
        // Test cancellation from recording state
        let state = AppState::Recording;
        let new_state = transition(state, AppEvent::CancellationRequested);
        assert_eq!(new_state, AppState::Ready);

        // Test cancellation from transcribing state
        let state = AppState::Transcribing;
        let new_state = transition(state, AppEvent::CancellationRequested);
        assert_eq!(new_state, AppState::Ready);

        // Test cancellation from other states (should not change state)
        let state = AppState::NeedsApiKey;
        let new_state = transition(state, AppEvent::CancellationRequested);
        assert_eq!(new_state, AppState::NeedsApiKey);

        let state = AppState::Ready;
        let new_state = transition(state, AppEvent::CancellationRequested);
        assert_eq!(new_state, AppState::Ready);
    }
}
