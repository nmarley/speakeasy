#![allow(clippy::uninlined_format_args)]

mod app_state;
mod audio;
mod cleanup;

use app_state::AppState;
pub use audio::{free_rust_string, transcribe_audio_blocking};
pub use cleanup::cleanup_transcript_blocking;

#[unsafe(no_mangle)]
pub extern "C" fn app_state_init() -> u8 {
    AppState::NeedsApiKey as u8
}
