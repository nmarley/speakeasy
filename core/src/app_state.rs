use serde::{Deserialize, Serialize};

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AppState {
    NeedsModel = 0,
    Ready = 1,
    Recording = 2,
    Transcribing = 3,
    CleaningUp = 4,
}

#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub enum AppEvent {
    ModelLoaded = 0,
    ModelRemoved = 1,
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
            0 => AppState::NeedsModel,
            1 => AppState::Ready,
            2 => AppState::Recording,
            3 => AppState::Transcribing,
            4 => AppState::CleaningUp,
            _ => AppState::NeedsModel, // Default fallback
        }
    }
}

impl From<u8> for AppEvent {
    fn from(value: u8) -> Self {
        match value {
            0 => AppEvent::ModelLoaded,
            1 => AppEvent::ModelRemoved,
            2 => AppEvent::StartRecordingRequested,
            3 => AppEvent::StopRecordingRequested,
            4 => AppEvent::TranscriptionCompleted,
            5 => AppEvent::TranscriptionFailed,
            6 => AppEvent::NoAudioRecorded,
            7 => AppEvent::CancellationRequested,
            8 => AppEvent::CleanupStarted,
            9 => AppEvent::CleanupCompleted,
            10 => AppEvent::CleanupFailed,
            _ => AppEvent::ModelLoaded, // Default fallback
        }
    }
}

fn transition(current_state: AppState, event: AppEvent) -> AppState {
    use AppEvent::*;
    use AppState::*;

    match (current_state, event) {
        // Model lifecycle
        (NeedsModel, ModelLoaded) => Ready,
        (Ready, ModelRemoved) => NeedsModel,

        // Recording flow (only works when model is loaded)
        (Ready, StartRecordingRequested) => Recording,
        (Recording, StopRecordingRequested) => Transcribing,
        (Recording, NoAudioRecorded) => Ready,
        (Transcribing, TranscriptionCompleted) => Ready,
        (Transcribing, TranscriptionFailed) => Ready,

        // Transcript cleanup flow
        (Transcribing, CleanupStarted) => CleaningUp,
        (CleaningUp, CleanupCompleted) => Ready,
        (CleaningUp, CleanupFailed) => Ready,

        // Cancellation
        (Recording, CancellationRequested) => Ready,
        (Transcribing, CancellationRequested) => Ready,
        (CleaningUp, CancellationRequested) => Ready,

        // Model removed during active states
        (Recording | Transcribing | CleaningUp, ModelRemoved) => NeedsModel,

        _ => current_state,
    }
}

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
    matches!(state, AppState::NeedsModel)
}

#[unsafe(no_mangle)]
pub extern "C" fn state_machine_transition(current_state: u8, event: u8) -> u8 {
    let state = AppState::from(current_state);
    let evt = AppEvent::from(event);
    transition(state, evt) as u8
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
pub extern "C" fn state_machine_is_valid_transition(current_state: u8, event: u8) -> bool {
    let state = AppState::from(current_state);
    let evt = AppEvent::from(event);
    transition(state, evt) != state
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_basic_flow() {
        let mut state = AppState::NeedsModel;

        state = transition(state, AppEvent::ModelLoaded);
        assert_eq!(state, AppState::Ready);
        assert!(can_start_recording(state));

        state = transition(state, AppEvent::StartRecordingRequested);
        assert_eq!(state, AppState::Recording);
        assert!(!can_start_recording(state));
        assert!(is_busy(state));

        state = transition(state, AppEvent::StopRecordingRequested);
        assert_eq!(state, AppState::Transcribing);
        assert!(is_busy(state));

        state = transition(state, AppEvent::TranscriptionCompleted);
        assert_eq!(state, AppState::Ready);
        assert!(can_start_recording(state));
        assert!(!is_busy(state));
    }

    #[test]
    fn test_invalid_transitions() {
        let state = AppState::NeedsModel;
        let new_state = transition(state, AppEvent::StartRecordingRequested);
        assert_eq!(new_state, AppState::NeedsModel);

        let state = AppState::Recording;
        let new_state = transition(state, AppEvent::StartRecordingRequested);
        assert_eq!(new_state, AppState::Recording);
    }

    #[test]
    fn test_model_lifecycle_flow() {
        let mut state = AppState::NeedsModel;

        assert!(!can_start_recording(state));
        assert!(needs_setup(state));

        state = transition(state, AppEvent::ModelLoaded);
        assert_eq!(state, AppState::Ready);
        assert!(can_start_recording(state));
        assert!(!needs_setup(state));

        state = transition(state, AppEvent::StartRecordingRequested);
        assert_eq!(state, AppState::Recording);
        state = transition(state, AppEvent::StopRecordingRequested);
        assert_eq!(state, AppState::Transcribing);
        state = transition(state, AppEvent::TranscriptionCompleted);
        assert_eq!(state, AppState::Ready);

        state = transition(state, AppEvent::StartRecordingRequested);
        state = transition(state, AppEvent::StopRecordingRequested);
        state = transition(state, AppEvent::TranscriptionFailed);
        assert_eq!(state, AppState::Ready);

        state = transition(state, AppEvent::StartRecordingRequested);
        state = transition(state, AppEvent::NoAudioRecorded);
        assert_eq!(state, AppState::Ready);

        state = transition(state, AppEvent::ModelRemoved);
        assert_eq!(state, AppState::NeedsModel);
        assert!(!can_start_recording(state));
        assert!(needs_setup(state));
    }

    #[test]
    fn test_model_removed_during_recording() {
        let mut state = AppState::Ready;

        state = transition(state, AppEvent::StartRecordingRequested);
        assert_eq!(state, AppState::Recording);

        state = transition(state, AppEvent::ModelRemoved);
        assert_eq!(state, AppState::NeedsModel);

        state = AppState::Transcribing;
        state = transition(state, AppEvent::ModelRemoved);
        assert_eq!(state, AppState::NeedsModel);
    }

    #[test]
    fn test_ffi_interface() {
        let state = AppState::NeedsModel as u8;
        let event = AppEvent::ModelLoaded as u8;

        let new_state = state_machine_transition(state, event);
        assert_eq!(new_state, AppState::Ready as u8);

        assert!(!state_machine_can_start_recording(state));
        assert!(state_machine_can_start_recording(new_state));
        assert!(state_machine_needs_setup(state));
        assert!(!state_machine_needs_setup(new_state));
    }

    #[test]
    fn test_cleanup_flow() {
        let mut state = AppState::Ready;

        state = transition(state, AppEvent::StartRecordingRequested);
        assert_eq!(state, AppState::Recording);

        state = transition(state, AppEvent::StopRecordingRequested);
        assert_eq!(state, AppState::Transcribing);

        state = transition(state, AppEvent::CleanupStarted);
        assert_eq!(state, AppState::CleaningUp);
        assert!(is_busy(state));

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
    fn test_cleanup_model_removed() {
        let mut state = AppState::CleaningUp;

        state = transition(state, AppEvent::ModelRemoved);
        assert_eq!(state, AppState::NeedsModel);
    }

    #[test]
    fn test_cleanup_only_from_transcribing() {
        let state = AppState::Ready;
        assert_eq!(transition(state, AppEvent::CleanupStarted), AppState::Ready);

        let state = AppState::Recording;
        assert_eq!(
            transition(state, AppEvent::CleanupStarted),
            AppState::Recording
        );

        let state = AppState::NeedsModel;
        assert_eq!(
            transition(state, AppEvent::CleanupStarted),
            AppState::NeedsModel
        );
    }

    #[test]
    fn test_cancellation_transitions() {
        let state = AppState::Recording;
        let new_state = transition(state, AppEvent::CancellationRequested);
        assert_eq!(new_state, AppState::Ready);

        let state = AppState::Transcribing;
        let new_state = transition(state, AppEvent::CancellationRequested);
        assert_eq!(new_state, AppState::Ready);

        let state = AppState::NeedsModel;
        let new_state = transition(state, AppEvent::CancellationRequested);
        assert_eq!(new_state, AppState::NeedsModel);

        let state = AppState::Ready;
        let new_state = transition(state, AppEvent::CancellationRequested);
        assert_eq!(new_state, AppState::Ready);
    }
}
