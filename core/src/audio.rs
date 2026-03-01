use async_openai::{Client, types::CreateTranscriptionRequest};
use std::time::Duration;
use symphonia::core::{
    formats::FormatOptions, io::MediaSourceStream, meta::MetadataOptions, probe::Hint,
};
use tokio::time::{sleep, timeout};
use tokio_util::sync::CancellationToken;

pub fn get_duration(file_path: &str) -> Result<f64, Box<dyn std::error::Error>> {
    let file = std::fs::File::open(file_path)?;
    let stream = MediaSourceStream::new(Box::new(file), Default::default());

    let mut hint = Hint::new();
    hint.with_extension("m4a");

    let format_opts = FormatOptions::default();
    let metadata_opts = MetadataOptions::default();

    let probe =
        symphonia::default::get_probe().format(&hint, stream, &format_opts, &metadata_opts)?;

    let format = probe.format;
    let track = format
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != symphonia::core::codecs::CODEC_TYPE_NULL)
        .ok_or("No audio track found")?;

    let time_base = track.codec_params.time_base;
    let n_frames = track.codec_params.n_frames;

    if let (Some(time_base), Some(n_frames)) = (time_base, n_frames) {
        let duration = (n_frames as f64) * time_base.numer as f64 / time_base.denom as f64;
        Ok(duration)
    } else {
        Err("Could not determine duration".into())
    }
}

pub fn calculate_threshold(audio_duration: f64) -> f64 {
    let threshold = audio_duration.sqrt() * 0.8;
    threshold.clamp(3.0, 30.0)
}

pub async fn transcribe_audio(
    file_path: &str,
    cancel_token: CancellationToken,
) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let client = Client::new();

    let request = CreateTranscriptionRequest {
        file: file_path.into(),
        model: "whisper-1".to_string(),
        language: None,
        prompt: None,
        response_format: None,
        temperature: None,
        timestamp_granularities: None,
    };

    // Add timeout as a safety net (60 seconds)
    let timeout_duration = Duration::from_secs(60);
    let audio_client = client.audio();

    // Use tokio::select! to race the transcription request against cancellation and timeout
    tokio::select! {
        result = timeout(timeout_duration, audio_client.transcribe(request)) => {
            match result {
                Ok(response) => {
                    let response = response?;
                    Ok(response.text)
                }
                Err(_) => Err("Request timed out".into()),
            }
        }
        _ = cancel_token.cancelled() => {
            Err("Request cancelled".into())
        }
    }
}

pub async fn transcribe_audio_with_api_key(
    file_path: &str,
    api_key: &str,
    cancel_token: CancellationToken,
) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let client =
        Client::with_config(async_openai::config::OpenAIConfig::new().with_api_key(api_key));

    let request = CreateTranscriptionRequest {
        file: file_path.into(),
        model: "whisper-1".to_string(),
        language: None,
        prompt: None,
        response_format: None,
        temperature: None,
        timestamp_granularities: None,
    };

    // Add timeout as a safety net (60 seconds)
    let timeout_duration = Duration::from_secs(60);
    let audio_client = client.audio();

    // Use tokio::select! to race the transcription request against cancellation and timeout
    tokio::select! {
        result = timeout(timeout_duration, audio_client.transcribe(request)) => {
            match result {
                Ok(response) => {
                    let response = response?;
                    Ok(response.text)
                }
                Err(_) => Err("Request timed out".into()),
            }
        }
        _ = cancel_token.cancelled() => {
            Err("Request cancelled".into())
        }
    }
}

pub async fn transcribe_audio_with_threshold(
    file_path: &str,
    audio_duration: f64,
) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let threshold_seconds = calculate_threshold(audio_duration);
    println!("Calculated threshold: {:.2} seconds", threshold_seconds);

    let file_path = file_path.to_string();
    let file_path_clone = file_path.clone();

    // Create cancellation tokens for both requests
    let primary_cancel_token = CancellationToken::new();
    let backup_cancel_token = CancellationToken::new();

    let primary_cancel_clone = primary_cancel_token.clone();
    let backup_cancel_clone = backup_cancel_token.clone();

    let primary_task =
        tokio::spawn(async move { transcribe_audio(&file_path, primary_cancel_clone).await });

    let backup_task = tokio::spawn(async move {
        sleep(Duration::from_secs_f64(threshold_seconds)).await;
        eprintln!("Threshold exceeded, starting backup transcription request");
        transcribe_audio(&file_path_clone, backup_cancel_clone).await
    });

    tokio::select! {
        primary_result = primary_task => {
            // Cancel the backup request since primary completed
            backup_cancel_token.cancel();
            match primary_result {
                Ok(Ok(result)) => {
                    println!("Primary transcription completed successfully");
                    Ok(result)
                }
                Ok(Err(e)) => {
                    eprintln!("Primary transcription failed: {}", e);
                    Err(e)
                }
                Err(e) => Err(format!("Primary transcription task failed: {}", e).into()),
            }
        }
        backup_result = backup_task => {
            // Cancel the primary request since backup completed
            primary_cancel_token.cancel();
            match backup_result {
                Ok(Ok(result)) => {
                    println!("Backup transcription completed successfully");
                    Ok(result)
                }
                Ok(Err(e)) => {
                    eprintln!("Backup transcription failed: {}", e);
                    Err(e)
                }
                Err(e) => Err(format!("Backup transcription task failed: {}", e).into()),
            }
        }
    }
}

pub async fn transcribe_audio_with_threshold_and_api_key(
    file_path: &str,
    api_key: &str,
    audio_duration: f64,
) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let threshold_seconds = calculate_threshold(audio_duration);
    println!("Calculated threshold: {:.2} seconds", threshold_seconds);

    let file_path = file_path.to_string();
    let file_path_clone = file_path.clone();
    let api_key = api_key.to_string();
    let api_key_clone = api_key.clone();

    // Create cancellation tokens for both requests
    let primary_cancel_token = CancellationToken::new();
    let backup_cancel_token = CancellationToken::new();

    let primary_cancel_clone = primary_cancel_token.clone();
    let backup_cancel_clone = backup_cancel_token.clone();

    let primary_task = tokio::spawn(async move {
        transcribe_audio_with_api_key(&file_path, &api_key, primary_cancel_clone).await
    });

    let backup_task = tokio::spawn(async move {
        sleep(Duration::from_secs_f64(threshold_seconds)).await;
        eprintln!("Threshold exceeded, starting backup transcription request");
        transcribe_audio_with_api_key(&file_path_clone, &api_key_clone, backup_cancel_clone).await
    });

    tokio::select! {
        primary_result = primary_task => {
            // Cancel the backup request since primary completed
            backup_cancel_token.cancel();
            match primary_result {
                Ok(Ok(result)) => {
                    println!("Primary transcription completed successfully");
                    Ok(result)
                }
                Ok(Err(e)) => {
                    eprintln!("Primary transcription failed: {}", e);
                    Err(e)
                }
                Err(e) => Err(format!("Primary transcription task failed: {}", e).into()),
            }
        }
        backup_result = backup_task => {
            // Cancel the primary request since backup completed
            primary_cancel_token.cancel();
            match backup_result {
                Ok(Ok(result)) => {
                    println!("Backup transcription completed successfully");
                    Ok(result)
                }
                Ok(Err(e)) => {
                    eprintln!("Backup transcription failed: {}", e);
                    Err(e)
                }
                Err(e) => Err(format!("Backup transcription task failed: {}", e).into()),
            }
        }
    }
}

// FFI Interface for blocking transcription
/// # Safety
///
/// This function is unsafe because it dereferences raw pointers and writes to caller-provided buffers.
/// The caller must ensure that:
/// - `audio_file_path` is either null or points to a valid, null-terminated C string
/// - `api_key` is either null or points to a valid, null-terminated C string
/// - All pointers remain valid for the duration of the call
/// - The returned pointer must be freed using `free_rust_string`
#[unsafe(no_mangle)]
pub unsafe extern "C" fn transcribe_audio_blocking(
    audio_file_path: *const std::os::raw::c_char,
    api_key: *const std::os::raw::c_char,
    timeout_threshold: f64,
) -> *mut std::os::raw::c_char {
    if audio_file_path.is_null() || api_key.is_null() {
        return std::ptr::null_mut();
    }

    let audio_path = match unsafe { std::ffi::CStr::from_ptr(audio_file_path) }.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let api_key_str = match unsafe { std::ffi::CStr::from_ptr(api_key) }.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    // Create a new tokio runtime for this blocking call
    let rt = match tokio::runtime::Runtime::new() {
        Ok(rt) => rt,
        Err(_) => return std::ptr::null_mut(),
    };

    let result = rt.block_on(async {
        // Get audio duration first
        let audio_duration = match get_duration(audio_path) {
            Ok(duration) => duration,
            Err(_) => return None,
        };

        // Use the threshold-based transcription if timeout_threshold is positive
        let transcription_result = if timeout_threshold > 0.0 {
            transcribe_audio_with_threshold_and_api_key(audio_path, api_key_str, audio_duration)
                .await
        } else {
            let cancel_token = CancellationToken::new();
            transcribe_audio_with_api_key(audio_path, api_key_str, cancel_token).await
        };

        transcription_result.ok()
    });

    match result {
        Some(text) => {
            let c_string = match std::ffi::CString::new(text) {
                Ok(s) => s,
                Err(_) => return std::ptr::null_mut(),
            };
            c_string.into_raw()
        }
        None => std::ptr::null_mut(),
    }
}

/// # Safety
///
/// This function is unsafe because it takes ownership of a raw pointer.
/// The caller must ensure that:
/// - `ptr` is either null or a valid pointer returned by `transcribe_audio_blocking`
/// - `ptr` has not been freed previously
/// - `ptr` is not used after calling this function
#[unsafe(no_mangle)]
pub unsafe extern "C" fn free_rust_string(ptr: *mut std::os::raw::c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = std::ffi::CString::from_raw(ptr);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_threshold_calculations() {
        let test_cases = vec![(1.0, 3.0), (16.0, 3.2), (100.0, 8.0), (1600.0, 30.0)];

        for (audio_duration, expected_threshold) in test_cases {
            let actual_threshold = calculate_threshold(audio_duration);
            assert!(
                (actual_threshold - expected_threshold).abs() < 0.01,
                "For duration {:.1}s, expected threshold {:.1}s but got {:.1}s",
                audio_duration,
                expected_threshold,
                actual_threshold
            );
        }
    }

    #[test]
    fn test_threshold_bounds() {
        assert_eq!(calculate_threshold(0.1), 3.0);
        assert_eq!(calculate_threshold(10000.0), 30.0);

        let mid_threshold = calculate_threshold(25.0);
        assert!(mid_threshold > 3.0 && mid_threshold < 30.0);
    }

    #[tokio::test]
    async fn test_cancellation_token_cancellation() {
        let cancel_token = CancellationToken::new();

        // Create a task that would normally take a long time
        let task = tokio::spawn({
            let token = cancel_token.clone();
            async move {
                tokio::select! {
                    _ = sleep(Duration::from_secs(10)) => {
                        Ok("Should not complete".to_string())
                    }
                    _ = token.cancelled() => {
                        Err("Request cancelled".into())
                    }
                }
            }
        });

        // Cancel the token after a short delay
        tokio::spawn({
            let token = cancel_token.clone();
            async move {
                sleep(Duration::from_millis(100)).await;
                token.cancel();
            }
        });

        // The task should be cancelled
        let result: Result<String, Box<dyn std::error::Error + Send + Sync>> = task.await.unwrap();
        assert!(result.is_err());
        assert_eq!(result.unwrap_err().to_string(), "Request cancelled");
    }

    #[tokio::test]
    async fn test_cancellation_token_completion() {
        let cancel_token = CancellationToken::new();

        // Create a task that completes quickly
        let task = tokio::spawn({
            let token = cancel_token.clone();
            async move {
                tokio::select! {
                    _ = sleep(Duration::from_millis(50)) => {
                        Ok("Completed successfully".to_string())
                    }
                    _ = token.cancelled() => {
                        Err("Request cancelled".into())
                    }
                }
            }
        });

        // The task should complete before any cancellation
        let result: Result<String, Box<dyn std::error::Error + Send + Sync>> = task.await.unwrap();
        assert!(result.is_ok());
        assert_eq!(result.unwrap(), "Completed successfully");
    }
}
