use std::fs;
use std::path::PathBuf;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use speakeasy_core::{AppEvent, AppState, WhisperModel, can_start_recording, transition};

use crate::audio::{AudioError, AudioRecorder};
use crate::clipboard::{self, ClipboardError};
use crate::paths::{Paths, PathsError};

#[derive(Debug)]
pub enum EngineError {
    Paths(PathsError),
    Io(std::io::Error),
    ModelMissing(PathBuf),
    Model(String),
    NotReady(AppState),
    Audio(AudioError),
    Transcription(String),
    Clipboard(ClipboardError),
}

impl std::fmt::Display for EngineError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Paths(err) => write!(f, "{err}"),
            Self::Io(err) => write!(f, "I/O error: {err}"),
            Self::ModelMissing(path) => write!(
                f,
                "Whisper model not found at {}\nRun: speakeasy download-model",
                path.display()
            ),
            Self::Model(msg) => write!(f, "{msg}"),
            Self::NotReady(state) => write!(f, "cannot start recording in state {state:?}"),
            Self::Audio(err) => write!(f, "{err}"),
            Self::Transcription(msg) => write!(f, "transcription failed: {msg}"),
            Self::Clipboard(err) => write!(f, "{err}"),
        }
    }
}

impl std::error::Error for EngineError {}

impl From<PathsError> for EngineError {
    fn from(value: PathsError) -> Self {
        Self::Paths(value)
    }
}

impl From<std::io::Error> for EngineError {
    fn from(value: std::io::Error) -> Self {
        Self::Io(value)
    }
}

impl From<AudioError> for EngineError {
    fn from(value: AudioError) -> Self {
        Self::Audio(value)
    }
}

impl From<ClipboardError> for EngineError {
    fn from(value: ClipboardError) -> Self {
        Self::Clipboard(value)
    }
}

pub struct Engine {
    paths: Paths,
    state: AppState,
    model: WhisperModel,
    recorder: AudioRecorder,
    wav_path: Option<PathBuf>,
}

impl Engine {
    pub fn open(paths: Paths) -> Result<Self, EngineError> {
        paths.ensure_dirs()?;
        let model_path = paths.default_model_path();
        if !model_path.is_file() {
            return Err(EngineError::ModelMissing(model_path));
        }

        let model = WhisperModel::load(&model_path).map_err(EngineError::Model)?;
        let state = transition(AppState::NeedsModel, AppEvent::ModelLoaded);

        Ok(Self {
            paths,
            state,
            model,
            recorder: AudioRecorder::new(),
            wav_path: None,
        })
    }

    pub fn state(&self) -> AppState {
        self.state
    }

    pub fn start_recording(&mut self) -> Result<(), EngineError> {
        if !can_start_recording(self.state) {
            return Err(EngineError::NotReady(self.state));
        }

        let stamp = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0);
        let path = self.paths.cache_dir.join(format!("recording-{stamp}.wav"));

        self.recorder.start(&path)?;
        self.wav_path = Some(path);
        self.state = transition(self.state, AppEvent::StartRecordingRequested);
        Ok(())
    }

    pub fn stop_and_transcribe(&mut self) -> Result<String, EngineError> {
        let wav_path = match self.recorder.stop() {
            Ok(path) => {
                self.state = transition(self.state, AppEvent::StopRecordingRequested);
                path
            }
            Err(AudioError::NoAudioRecorded) => {
                self.state = transition(self.state, AppEvent::NoAudioRecorded);
                self.wav_path = None;
                return Err(EngineError::Audio(AudioError::NoAudioRecorded));
            }
            Err(err) => {
                self.state = transition(self.state, AppEvent::CancellationRequested);
                self.wav_path = None;
                return Err(EngineError::Audio(err));
            }
        };
        self.wav_path = None;

        match self.model.transcribe(&wav_path) {
            Ok(text) => {
                self.state = transition(self.state, AppEvent::TranscriptionCompleted);
                let _ = fs::remove_file(&wav_path);
                Ok(text)
            }
            Err(msg) => {
                self.state = transition(self.state, AppEvent::TranscriptionFailed);
                let _ = fs::remove_file(&wav_path);
                Err(EngineError::Transcription(msg))
            }
        }
    }

    pub fn run_once(&mut self, duration: Duration) -> Result<String, EngineError> {
        self.start_recording()?;
        std::thread::sleep(duration);
        let text = self.stop_and_transcribe()?;
        clipboard::copy_text(&text)?;
        Ok(text)
    }
}
