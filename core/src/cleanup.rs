use reqwest::header::{AUTHORIZATION, CONTENT_TYPE};
use serde::{Deserialize, Serialize};
use std::time::Duration;

const CLEANUP_MODEL: &str = "gpt-4.1-nano";
const CLEANUP_TIMEOUT_SECS: u64 = 30;

const SYSTEM_PROMPT: &str = "\
You are a transcription editor. Your only job is to add proper punctuation \
and fix capitalization. Do not change any words, add words, remove words, \
reorder anything, or alter the content in any way.

Rules:
- Add periods, commas, question marks, and other punctuation where appropriate
- Capitalize the first letter of sentences
- Capitalize proper nouns and acronyms (e.g., Terraform, EKS)
- Preserve all original words exactly as spoken
- Do not add filler removal, do not paraphrase, do not summarize

Output the corrected transcript only, with no commentary.";

#[derive(Serialize)]
struct ChatMessage {
    role: String,
    content: String,
}

#[derive(Serialize)]
struct ChatRequest {
    model: String,
    messages: Vec<ChatMessage>,
}

#[derive(Deserialize)]
struct ChatResponse {
    choices: Vec<ChatChoice>,
}

#[derive(Deserialize)]
struct ChatChoice {
    message: ChatChoiceMessage,
}

#[derive(Deserialize)]
struct ChatChoiceMessage {
    content: String,
}

async fn cleanup_transcript(
    transcript: &str,
    api_key: &str,
) -> Result<String, Box<dyn std::error::Error + Send + Sync>> {
    let client = reqwest::Client::new();

    let request_body = ChatRequest {
        model: CLEANUP_MODEL.to_string(),
        messages: vec![
            ChatMessage {
                role: "system".to_string(),
                content: SYSTEM_PROMPT.to_string(),
            },
            ChatMessage {
                role: "user".to_string(),
                content: transcript.to_string(),
            },
        ],
    };

    let response = client
        .post("https://api.openai.com/v1/chat/completions")
        .header(AUTHORIZATION, format!("Bearer {}", api_key))
        .header(CONTENT_TYPE, "application/json")
        .timeout(Duration::from_secs(CLEANUP_TIMEOUT_SECS))
        .json(&request_body)
        .send()
        .await?;

    if !response.status().is_success() {
        let status = response.status();
        let body = response.text().await.unwrap_or_default();
        return Err(format!("API error {}: {}", status, body).into());
    }

    let chat_response: ChatResponse = response.json().await?;

    chat_response
        .choices
        .into_iter()
        .next()
        .map(|c| c.message.content)
        .ok_or_else(|| "No response from cleanup model".into())
}

/// # Safety
///
/// This function is unsafe because it dereferences raw pointers.
/// The caller must ensure that:
/// - `transcript` is either null or points to a valid, null-terminated C string
/// - `api_key` is either null or points to a valid, null-terminated C string
/// - All pointers remain valid for the duration of the call
/// - The returned pointer must be freed using `free_rust_string`
#[unsafe(no_mangle)]
pub unsafe extern "C" fn cleanup_transcript_blocking(
    transcript: *const std::os::raw::c_char,
    api_key: *const std::os::raw::c_char,
) -> *mut std::os::raw::c_char {
    if transcript.is_null() || api_key.is_null() {
        return std::ptr::null_mut();
    }

    let transcript_str = match unsafe { std::ffi::CStr::from_ptr(transcript) }.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let api_key_str = match unsafe { std::ffi::CStr::from_ptr(api_key) }.to_str() {
        Ok(s) => s,
        Err(_) => return std::ptr::null_mut(),
    };

    let rt = match tokio::runtime::Runtime::new() {
        Ok(rt) => rt,
        Err(_) => return std::ptr::null_mut(),
    };

    let result = rt.block_on(cleanup_transcript(transcript_str, api_key_str));

    match result {
        Ok(text) => {
            println!(
                "Transcript cleanup completed: {} chars in, {} chars out",
                transcript_str.len(),
                text.len()
            );
            let c_string = match std::ffi::CString::new(text) {
                Ok(s) => s,
                Err(_) => return std::ptr::null_mut(),
            };
            c_string.into_raw()
        }
        Err(e) => {
            eprintln!("Transcript cleanup failed: {}", e);
            std::ptr::null_mut()
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_system_prompt_not_empty() {
        assert!(!SYSTEM_PROMPT.is_empty());
    }

    #[test]
    fn test_model_name() {
        assert_eq!(CLEANUP_MODEL, "gpt-4.1-nano");
    }

    /// Integration test that calls the real OpenAI API.
    /// Run with: OPENAI_API_KEY=sk-... cargo test test_cleanup_changes_messy_input -- --ignored
    #[tokio::test]
    #[ignore]
    async fn test_cleanup_changes_messy_input() {
        let api_key = std::env::var("OPENAI_API_KEY")
            .expect("OPENAI_API_KEY env var required for integration test");

        let input = "yeah so I'm not sure how they plan to deploy it though they literally \
                     can't go and click and start creating that stuff until you know they have \
                     to stand it up at least through Terraform even though it's not gonna be \
                     the way we want through EKS and such they still have to go through \
                     Terraform you know";

        let result = cleanup_transcript(input, &api_key).await.unwrap();

        println!("Original ({} chars): {}", input.len(), input);
        println!("Cleaned  ({} chars): {}", result.len(), result);
        println!("Changed: {}", input != result);

        // Output should differ from input (punctuation added)
        assert_ne!(input, result, "Cleanup should modify the transcript");

        // Output should contain punctuation that the input lacks
        assert!(
            result.contains('.') || result.contains(',') || result.contains('?'),
            "Cleaned output should contain punctuation"
        );

        // Output should be roughly similar length (not a summary or rewrite)
        let len_ratio = result.len() as f64 / input.len() as f64;
        assert!(
            len_ratio > 0.9 && len_ratio < 1.3,
            "Output length ratio {:.2} is outside expected range (0.9-1.3)",
            len_ratio
        );
    }
}
