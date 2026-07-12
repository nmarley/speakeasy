#[derive(Debug)]
pub enum ClipboardError {
    Backend(String),
}

impl std::fmt::Display for ClipboardError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Backend(msg) => write!(f, "clipboard error: {msg}"),
        }
    }
}

impl std::error::Error for ClipboardError {}

pub fn copy_text(text: &str) -> Result<(), ClipboardError> {
    let mut clipboard =
        arboard::Clipboard::new().map_err(|err| ClipboardError::Backend(err.to_string()))?;
    clipboard
        .set_text(text.to_owned())
        .map_err(|err| ClipboardError::Backend(err.to_string()))?;
    Ok(())
}
