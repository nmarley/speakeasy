#![allow(clippy::uninlined_format_args)]

mod app_state;
mod audio;
mod cleanup;

use app_state::AppState;
pub use audio::{
    free_rust_string, transcribe_audio_blocking, whisper_context_destroy, whisper_context_init,
};
pub use cleanup::cleanup_transcript_blocking;

#[unsafe(no_mangle)]
pub extern "C" fn app_state_init() -> u8 {
    AppState::NeedsModel as u8
}
