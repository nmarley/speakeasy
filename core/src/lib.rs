#![allow(clippy::uninlined_format_args)]

pub mod app_state;
mod audio;

pub use app_state::{AppEvent, AppState, can_start_recording, is_busy, needs_setup, transition};
pub use audio::{
    WhisperModel, free_rust_string, transcribe_audio_blocking, whisper_context_destroy,
    whisper_context_init,
};

#[unsafe(no_mangle)]
pub extern "C" fn app_state_init() -> u8 {
    AppState::NeedsModel as u8
}
