use std::io::{self, Write};
use std::path::PathBuf;

use hf_hub::HFClientSync;
use hf_hub::progress::{DownloadEvent, ProgressEvent, ProgressHandler};

use crate::paths::{
    DEFAULT_MODEL_FILENAME, DEFAULT_MODEL_NAME, DEFAULT_MODEL_REPO_NAME, DEFAULT_MODEL_REPO_OWNER,
    DEFAULT_MODEL_URL, Paths,
};

#[derive(Debug)]
pub enum DownloadError {
    Io(io::Error),
    Http(String),
    AlreadyPresent(PathBuf),
}

impl std::fmt::Display for DownloadError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(err) => write!(f, "I/O error: {err}"),
            Self::Http(msg) => write!(f, "download failed: {msg}"),
            Self::AlreadyPresent(path) => {
                write!(f, "model already present at {}", path.display())
            }
        }
    }
}

impl std::error::Error for DownloadError {}

impl From<io::Error> for DownloadError {
    fn from(value: io::Error) -> Self {
        Self::Io(value)
    }
}

struct StderrProgress;

impl ProgressHandler for StderrProgress {
    fn on_progress(&self, event: &ProgressEvent) {
        match event {
            ProgressEvent::Download(DownloadEvent::Start { total_bytes, .. }) => {
                eprintln!("Size: {total_bytes} bytes");
            }
            ProgressEvent::Download(DownloadEvent::AggregateProgress {
                bytes_completed,
                total_bytes,
                ..
            }) if *total_bytes > 0 => {
                let pct = ((*bytes_completed * 100) / *total_bytes).min(100);
                eprint!("\rProgress: {pct}% ({bytes_completed}/{total_bytes} bytes)");
                let _ = io::stderr().flush();
            }
            ProgressEvent::Download(DownloadEvent::Complete) => {
                eprintln!();
            }
            _ => {}
        }
    }
}

pub fn download_default_model(paths: &Paths, force: bool) -> Result<PathBuf, DownloadError> {
    paths.ensure_dirs()?;

    let dest = paths.default_model_path();
    if dest.is_file() && !force {
        return Err(DownloadError::AlreadyPresent(dest));
    }

    eprintln!("Downloading Whisper model {DEFAULT_MODEL_NAME} from {DEFAULT_MODEL_URL}");
    eprintln!("Destination: {}", dest.display());

    let client = HFClientSync::new().map_err(|err| DownloadError::Http(err.to_string()))?;
    let repo = client.model(DEFAULT_MODEL_REPO_OWNER, DEFAULT_MODEL_REPO_NAME);

    let path = repo
        .download_file()
        .filename(DEFAULT_MODEL_FILENAME)
        .local_dir(paths.models_dir.clone())
        .force_download(force)
        .progress(StderrProgress)
        .send()
        .map_err(|err| DownloadError::Http(err.to_string()))?;

    eprintln!("Model ready at {}", path.display());
    Ok(path)
}
