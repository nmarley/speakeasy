use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use cpal::{Sample, SampleFormat, Stream, StreamConfig};

pub const WHISPER_SAMPLE_RATE: u32 = 16_000;

#[derive(Debug)]
pub enum AudioError {
    NoInputDevice,
    Device(String),
    Stream(String),
    NotRecording,
    NoAudioRecorded,
    Io(std::io::Error),
    Wav(hound::Error),
}

impl std::fmt::Display for AudioError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::NoInputDevice => write!(f, "no default input device found"),
            Self::Device(msg) => write!(f, "audio device error: {msg}"),
            Self::Stream(msg) => write!(f, "audio stream error: {msg}"),
            Self::NotRecording => write!(f, "not currently recording"),
            Self::NoAudioRecorded => write!(f, "no audio data was recorded"),
            Self::Io(err) => write!(f, "I/O error: {err}"),
            Self::Wav(err) => write!(f, "WAV error: {err}"),
        }
    }
}

impl std::error::Error for AudioError {}

impl From<std::io::Error> for AudioError {
    fn from(value: std::io::Error) -> Self {
        Self::Io(value)
    }
}

impl From<hound::Error> for AudioError {
    fn from(value: hound::Error) -> Self {
        Self::Wav(value)
    }
}

pub struct AudioRecorder {
    samples: Arc<Mutex<Vec<f32>>>,
    stream: Option<Stream>,
    input_sample_rate: u32,
    input_channels: u16,
    output_path: Option<PathBuf>,
    recording: bool,
}

impl AudioRecorder {
    pub fn new() -> Self {
        Self {
            samples: Arc::new(Mutex::new(Vec::new())),
            stream: None,
            input_sample_rate: 0,
            input_channels: 0,
            output_path: None,
            recording: false,
        }
    }

    pub fn start<P: AsRef<Path>>(&mut self, output_path: P) -> Result<(), AudioError> {
        if self.recording {
            self.stop_stream_only();
        }

        let host = cpal::default_host();
        let device = host
            .default_input_device()
            .ok_or(AudioError::NoInputDevice)?;

        let supported = device
            .default_input_config()
            .map_err(|err| AudioError::Device(err.to_string()))?;

        let sample_format = supported.sample_format();
        let config: StreamConfig = supported.clone().into();
        let input_sample_rate = config.sample_rate.0;
        let input_channels = config.channels;

        {
            let mut buf = self.samples.lock().expect("samples mutex poisoned");
            buf.clear();
        }

        let samples = Arc::clone(&self.samples);
        let channels = input_channels as usize;
        let err_fn = |err| eprintln!("audio stream error: {err}");

        let stream = match sample_format {
            SampleFormat::F32 => {
                build_input_stream::<f32>(&device, &config, samples, channels, err_fn)?
            }
            SampleFormat::I16 => {
                build_input_stream::<i16>(&device, &config, samples, channels, err_fn)?
            }
            SampleFormat::U16 => {
                build_input_stream::<u16>(&device, &config, samples, channels, err_fn)?
            }
            other => {
                return Err(AudioError::Device(format!(
                    "unsupported sample format: {other:?}"
                )));
            }
        };

        stream
            .play()
            .map_err(|err| AudioError::Stream(err.to_string()))?;

        self.stream = Some(stream);
        self.input_sample_rate = input_sample_rate;
        self.input_channels = input_channels;
        self.output_path = Some(output_path.as_ref().to_path_buf());
        self.recording = true;
        Ok(())
    }

    pub fn stop(&mut self) -> Result<PathBuf, AudioError> {
        if !self.recording {
            return Err(AudioError::NotRecording);
        }

        self.stop_stream_only();
        self.recording = false;

        let output_path = self.output_path.take().ok_or(AudioError::NotRecording)?;

        let raw = {
            let buf = self.samples.lock().expect("samples mutex poisoned");
            buf.clone()
        };

        if raw.is_empty() {
            return Err(AudioError::NoAudioRecorded);
        }

        let mono_16k = resample_linear(&raw, self.input_sample_rate, WHISPER_SAMPLE_RATE);
        if mono_16k.is_empty() {
            return Err(AudioError::NoAudioRecorded);
        }

        if let Some(parent) = output_path.parent() {
            std::fs::create_dir_all(parent)?;
        }

        write_wav_i16(&output_path, &mono_16k, WHISPER_SAMPLE_RATE)?;
        Ok(output_path)
    }

    pub fn cancel(&mut self) {
        self.stop_stream_only();
        self.output_path = None;
        if let Ok(mut buf) = self.samples.lock() {
            buf.clear();
        }
    }

    fn stop_stream_only(&mut self) {
        if let Some(stream) = self.stream.take() {
            let _ = stream.pause();
            drop(stream);
        }
        self.recording = false;
    }
}

impl Drop for AudioRecorder {
    fn drop(&mut self) {
        self.stop_stream_only();
    }
}

fn build_input_stream<T>(
    device: &cpal::Device,
    config: &StreamConfig,
    samples: Arc<Mutex<Vec<f32>>>,
    channels: usize,
    err_fn: impl FnMut(cpal::StreamError) + Send + 'static,
) -> Result<Stream, AudioError>
where
    T: Sample + cpal::SizedSample + Send + 'static,
    f32: cpal::FromSample<T>,
{
    device
        .build_input_stream(
            config,
            move |data: &[T], _| {
                let mut buf = samples.lock().expect("samples mutex poisoned");
                if channels <= 1 {
                    for &sample in data {
                        buf.push(sample.to_sample::<f32>());
                    }
                } else {
                    for frame in data.chunks_exact(channels) {
                        let sum: f32 = frame.iter().map(|s| s.to_sample::<f32>()).sum();
                        buf.push(sum / channels as f32);
                    }
                }
            },
            err_fn,
            None,
        )
        .map_err(|err| AudioError::Stream(err.to_string()))
}

fn resample_linear(input: &[f32], from_rate: u32, to_rate: u32) -> Vec<f32> {
    if input.is_empty() {
        return Vec::new();
    }
    if from_rate == to_rate || from_rate == 0 {
        return input.to_vec();
    }

    let ratio = f64::from(from_rate) / f64::from(to_rate);
    let out_len = ((input.len() as f64) / ratio).floor() as usize;
    if out_len == 0 {
        return Vec::new();
    }

    let mut out = Vec::with_capacity(out_len);
    let last = input.len() - 1;
    for i in 0..out_len {
        let src = i as f64 * ratio;
        let i0 = src.floor() as usize;
        let i1 = (i0 + 1).min(last);
        let t = (src - i0 as f64) as f32;
        out.push(input[i0] * (1.0 - t) + input[i1] * t);
    }
    out
}

fn write_wav_i16(path: &Path, samples: &[f32], sample_rate: u32) -> Result<(), AudioError> {
    let spec = hound::WavSpec {
        channels: 1,
        sample_rate,
        bits_per_sample: 16,
        sample_format: hound::SampleFormat::Int,
    };
    let mut writer = hound::WavWriter::create(path, spec)?;
    for &sample in samples {
        let clipped = sample.clamp(-1.0, 1.0);
        let amplitude = (clipped * f32::from(i16::MAX)) as i16;
        writer.write_sample(amplitude)?;
    }
    writer.finalize()?;
    Ok(())
}

pub fn record_for_duration<P: AsRef<Path>>(
    output_path: P,
    duration: Duration,
) -> Result<PathBuf, AudioError> {
    let mut recorder = AudioRecorder::new();
    recorder.start(output_path)?;
    std::thread::sleep(duration);
    recorder.stop()
}
