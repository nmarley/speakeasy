use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use whisper_rs::{FullParams, SamplingStrategy, WhisperContext, WhisperContextParameters};

/// Load a WAV file and return 16KHz mono f32 PCM samples.
///
/// The WAV must be 16KHz, mono, 16-bit PCM (the format produced by
/// the Swift AudioRecorder). The samples are converted to f32 in the
/// range [-1.0, 1.0] as required by whisper.cpp.
fn load_wav_samples(path: &str) -> Result<Vec<f32>, Box<dyn std::error::Error>> {
    let reader = hound::WavReader::open(path)?;
    let spec = reader.spec();

    if spec.channels != 1 {
        return Err(format!("Expected mono audio, got {} channels", spec.channels).into());
    }

    if spec.sample_rate != 16000 {
        return Err(format!("Expected 16KHz sample rate, got {} Hz", spec.sample_rate).into());
    }

    let samples: Vec<f32> = match spec.sample_format {
        hound::SampleFormat::Int => {
            let max_val = (1_i64 << (spec.bits_per_sample - 1)) as f32;
            reader
                .into_samples::<i32>()
                .filter_map(|s| s.ok())
                .map(|s| s as f32 / max_val)
                .collect()
        }
        hound::SampleFormat::Float => reader
            .into_samples::<f32>()
            .filter_map(|s| s.ok())
            .collect(),
    };

    Ok(samples)
}

/// Run local Whisper inference on a WAV file using an existing context.
fn transcribe_local(
    ctx: &WhisperContext,
    audio_path: &str,
) -> Result<String, Box<dyn std::error::Error>> {
    let samples = load_wav_samples(audio_path)?;

    let mut state = ctx.create_state()?;

    let mut params = FullParams::new(SamplingStrategy::Greedy { best_of: 1 });
    params.set_language(Some("en"));
    params.set_print_progress(false);
    params.set_print_realtime(false);
    params.set_print_timestamps(false);
    params.set_print_special(false);
    params.set_single_segment(false);
    params.set_no_context(true);

    state.full(params, &samples)?;

    let mut text = String::new();
    for segment in state.as_iter() {
        if let Ok(s) = segment.to_str() {
            text.push_str(s);
        }
    }

    Ok(text.trim().to_string())
}

/// Initialize a Whisper context from a model file path.
///
/// # Safety
///
/// `model_path` must be a valid, null-terminated C string pointing to a
/// GGML model file. The returned pointer must eventually be freed with
/// `whisper_context_destroy`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn whisper_context_init(model_path: *const c_char) -> *mut WhisperContext {
    if model_path.is_null() {
        return std::ptr::null_mut();
    }

    let path = match unsafe { CStr::from_ptr(model_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let params = WhisperContextParameters::default();
    match WhisperContext::new_with_params(path, params) {
        Ok(ctx) => Box::into_raw(Box::new(ctx)),
        Err(e) => {
            eprintln!("Failed to load Whisper model: {}", e);
            std::ptr::null_mut()
        }
    }
}

/// Destroy a Whisper context and free its resources.
///
/// # Safety
///
/// `ctx` must be a pointer returned by `whisper_context_init` that has
/// not been freed previously, or null (which is a no-op).
#[unsafe(no_mangle)]
pub unsafe extern "C" fn whisper_context_destroy(ctx: *mut WhisperContext) {
    if !ctx.is_null() {
        unsafe {
            let _ = Box::from_raw(ctx);
        }
    }
}

/// Transcribe a WAV file using an existing Whisper context.
///
/// # Safety
///
/// - `ctx` must be a valid pointer returned by `whisper_context_init`
/// - `audio_file_path` must be a valid, null-terminated C string
/// - The returned pointer must be freed using `free_rust_string`
#[unsafe(no_mangle)]
pub unsafe extern "C" fn transcribe_audio_blocking(
    ctx: *const WhisperContext,
    audio_file_path: *const c_char,
) -> *mut c_char {
    if ctx.is_null() || audio_file_path.is_null() {
        return std::ptr::null_mut();
    }

    let context = unsafe { &*ctx };

    let audio_path = match unsafe { CStr::from_ptr(audio_file_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    match transcribe_local(context, audio_path) {
        Ok(text) => {
            let c_string = match CString::new(text) {
                Ok(s) => s,
                Err(_) => return std::ptr::null_mut(),
            };
            c_string.into_raw()
        }
        Err(e) => {
            eprintln!("Transcription failed: {}", e);
            std::ptr::null_mut()
        }
    }
}

/// # Safety
///
/// `ptr` must be either null or a valid pointer returned by
/// `transcribe_audio_blocking`. It must not have been freed previously.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn free_rust_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_load_wav_rejects_missing_file() {
        let result = load_wav_samples("/nonexistent/file.wav");
        assert!(result.is_err());
    }
}
