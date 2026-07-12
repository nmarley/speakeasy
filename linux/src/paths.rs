use std::fs;
use std::io;
use std::path::PathBuf;

pub const APP_NAME: &str = "speakeasy";
pub const DEFAULT_MODEL_FILENAME: &str = "ggml-small.en.bin";
pub const DEFAULT_MODEL_URL: &str =
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin";
pub const DEFAULT_MODEL_NAME: &str = "small.en";

#[derive(Debug, Clone)]
pub struct Paths {
    pub data_dir: PathBuf,
    pub config_dir: PathBuf,
    pub cache_dir: PathBuf,
    pub models_dir: PathBuf,
}

impl Paths {
    pub fn resolve() -> Result<Self, PathsError> {
        let data_dir = dirs::data_dir()
            .ok_or(PathsError::MissingHome)?
            .join(APP_NAME);
        let config_dir = dirs::config_dir()
            .ok_or(PathsError::MissingHome)?
            .join(APP_NAME);
        let cache_dir = dirs::cache_dir()
            .ok_or(PathsError::MissingHome)?
            .join(APP_NAME);
        let models_dir = data_dir.join("models");

        Ok(Self {
            data_dir,
            config_dir,
            cache_dir,
            models_dir,
        })
    }

    pub fn default_model_path(&self) -> PathBuf {
        self.models_dir.join(DEFAULT_MODEL_FILENAME)
    }

    pub fn model_is_present(&self) -> bool {
        self.default_model_path().is_file()
    }

    pub fn ensure_dirs(&self) -> io::Result<()> {
        fs::create_dir_all(&self.data_dir)?;
        fs::create_dir_all(&self.config_dir)?;
        fs::create_dir_all(&self.cache_dir)?;
        fs::create_dir_all(&self.models_dir)?;
        Ok(())
    }
}

#[derive(Debug)]
pub enum PathsError {
    MissingHome,
}

impl std::fmt::Display for PathsError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::MissingHome => {
                write!(f, "could not resolve XDG directories (HOME unset?)")
            }
        }
    }
}

impl std::error::Error for PathsError {}
