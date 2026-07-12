use std::fs::{self, File};
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::time::Duration;

use crate::paths::{DEFAULT_MODEL_NAME, DEFAULT_MODEL_URL, Paths};

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

pub fn download_default_model(paths: &Paths, force: bool) -> Result<PathBuf, DownloadError> {
    paths.ensure_dirs()?;

    let dest = paths.default_model_path();
    if dest.is_file() && !force {
        return Err(DownloadError::AlreadyPresent(dest));
    }

    let partial = paths.cache_dir.join(format!(
        "{}.partial",
        dest.file_name().unwrap().to_string_lossy()
    ));

    eprintln!("Downloading Whisper model {DEFAULT_MODEL_NAME} from {DEFAULT_MODEL_URL}");
    eprintln!("Destination: {}", dest.display());

    let response = ureq::get(DEFAULT_MODEL_URL)
        .timeout(Duration::from_secs(600))
        .call()
        .map_err(|err| DownloadError::Http(err.to_string()))?;

    if !(200..300).contains(&response.status()) {
        return Err(DownloadError::Http(format!("HTTP {}", response.status())));
    }

    let total = response
        .header("Content-Length")
        .and_then(|v| v.parse::<u64>().ok());

    let mut reader = response.into_reader();
    let mut file = File::create(&partial)?;
    let mut buf = [0u8; 64 * 1024];
    let mut written: u64 = 0;
    let mut last_pct: u8 = 255;

    loop {
        let n = reader.read(&mut buf)?;
        if n == 0 {
            break;
        }
        file.write_all(&buf[..n])?;
        written += n as u64;

        if let Some(total) = total {
            let pct = ((written * 100) / total).min(100) as u8;
            if pct != last_pct {
                eprint!("\rProgress: {pct}% ({written}/{total} bytes)");
                let _ = io::stderr().flush();
                last_pct = pct;
            }
        } else if written % (8 * 1024 * 1024) < 64 * 1024 {
            eprint!("\rDownloaded: {written} bytes");
            let _ = io::stderr().flush();
        }
    }

    file.sync_all()?;
    drop(file);
    eprintln!();

    if dest.exists() {
        fs::remove_file(&dest)?;
    }
    rename_or_copy(&partial, &dest)?;
    let _ = fs::remove_file(&partial);

    eprintln!("Model ready at {}", dest.display());
    Ok(dest)
}

fn rename_or_copy(from: &Path, to: &Path) -> io::Result<()> {
    match fs::rename(from, to) {
        Ok(()) => Ok(()),
        Err(err) if err.kind() == io::ErrorKind::CrossesDevices => {
            fs::copy(from, to)?;
            fs::remove_file(from)?;
            Ok(())
        }
        Err(err) => Err(err),
    }
}
