# Local Whisper Transcription

Replace the OpenAI Whisper API with local inference using whisper.cpp
(via the `whisper-rs` Rust crate) with Metal acceleration on Apple
Silicon.

## Motivation

The current pipeline sends audio to OpenAI's hosted Whisper endpoint.
This introduces network round-trip latency (1-3 seconds minimum),
requires an API key, incurs per-request costs, and sends audio data
off-device. On an Apple Silicon Mac with a capable GPU, local Whisper
inference can match or beat the API's latency for short dictation clips
while removing all of those downsides.

## Current Pipeline

1. Swift captures microphone audio via AVAudioEngine
2. Audio is encoded to M4A/AAC (64kbps mono) and written to a temp file
3. Rust reads the file and POSTs it to `POST /v1/audio/transcriptions`
   using the `async-openai` crate with model `whisper-1`
4. A backup request fires after a dynamic threshold to hedge against
   slow API responses
5. Transcript text crosses FFI back to Swift and is pasted

Key files:
- `core/src/audio.rs`: API calls, threshold/backup logic, FFI entry
- `macos-menubar/Sources/Speakeasy/AudioRecorder.swift`: audio capture
- `macos-menubar/Sources/Speakeasy/RustFFI.swift`: Swift-to-C bridge
- `macos-menubar/Sources/Speakeasy/SettingsManager.swift`: API key storage

## Proposed Pipeline

1. Swift captures microphone audio (unchanged)
2. Audio is written to a temp file (format may change; see below)
3. Rust decodes the audio to 16kHz mono f32 PCM using symphonia
   (already a dependency)
4. Rust runs whisper.cpp inference via `whisper-rs` with Metal
   acceleration
5. Transcript text crosses FFI back to Swift and is pasted (unchanged)

The FFI boundary (`transcribe_audio_blocking` returning `*const c_char`)
does not change. Swift code beyond the settings UI requires no
modification.

## Rust Core Changes

### Dependencies

Add to `core/Cargo.toml`:

```toml
whisper-rs = { version = "0.14", features = ["metal"] }
```

The `async-openai` dependency can be removed entirely if the cleanup
feature is migrated to use `reqwest` directly (it already does; see
`core/src/cleanup.rs`). If we want to keep an option for remote
transcription as a fallback, gate `async-openai` behind a cargo feature.

### Audio Decoding

Whisper requires 16kHz mono f32 PCM. The app currently writes M4A/AAC.
Two options:

**Option A (preferred):** Decode in Rust using symphonia, which is
already a dependency (currently used only for duration detection). Add
the `symphonia-codec-aac` and `symphonia-format-isomp4` features if not
already enabled (they are; the crate is pulled with all features). After
decoding, resample to 16kHz if the source sample rate differs. The
`rubato` crate or a simple linear resampler would handle this.

**Option B:** Change the Swift AudioRecorder to output 16kHz mono f32
PCM in WAV format instead of M4A. This avoids decoding/resampling in
Rust but changes the recording pipeline. Less desirable because the
current M4A path is well-tested and the cleanup feature may eventually
want the compressed file for other purposes.

### Transcription Function

Replace the body of `transcribe_audio_blocking` in `core/src/audio.rs`:

1. Load the whisper model (see Model Management below)
2. Decode the audio file to 16kHz mono f32 PCM via symphonia
3. Create a `WhisperContext` and `WhisperState`
4. Run `whisper_full()` with default parameters (greedy decoding,
   single-threaded decode, language auto-detect or English)
5. Collect segment text and return the concatenated transcript

The backup-request/threshold logic (lines 181-243) becomes unnecessary
with no network variability. Remove it. The cancellation token support
should remain so the user can cancel a long transcription by pressing
the hotkey again.

### Model Management

The whisper.cpp GGML model file needs to live on disk. Proposed
location: `~/Library/Application Support/Speakeasy/models/`.

Strategy:
- Ship no model in the app bundle (keeps the DMG small)
- On first launch (or when no model is found), download the selected
  model from Hugging Face and store it in the models directory
- Show download progress in the menu bar UI
- Default model: `ggml-medium.bin` (good quality/speed tradeoff)

Model sizes (quantized q5_0 variants where available):

| Model     | Size     | Notes                              |
|-----------|----------|------------------------------------|
| tiny      | ~40 MB   | Fastest; fine for clear speech     |
| base      | ~80 MB   | Fast; slightly better accuracy     |
| small     | ~250 MB  | Good balance                       |
| medium    | ~800 MB  | High quality; recommended default  |
| large-v3  | ~1.7 GB  | Highest quality                    |

The `WhisperContext` should be initialized once and kept in memory
(behind a `Mutex` or `OnceLock`) rather than reloaded on every
transcription. Model loading takes a few seconds; inference itself is
fast. This means the Rust library needs a lifecycle: init (load model),
transcribe (use loaded model), and optionally reload (when the user
changes model selection).

New FFI functions:

```c
// Load or reload the whisper model. Returns 0 on success, -1 on error.
int32_t speakeasy_load_model(const char *model_path);

// Check if a model is currently loaded. Returns 1 if yes, 0 if no.
int32_t speakeasy_model_loaded(void);
```

The existing `transcribe_audio_blocking` signature stays the same but
now uses the pre-loaded model internally instead of making an API call.

## Swift App Changes

### Settings

- Remove the API key as a required field. The OpenAI API key is still
  needed if the user enables transcript cleanup (which calls GPT), so
  keep it as an optional setting.
- Add a model selection setting (dropdown: tiny, base, small, medium,
  large-v3) with medium as the default.
- Add a model download/management UI element that shows download
  progress or "Ready" status.

### Startup

- On app launch, check for the selected model file in the models
  directory.
- If present, call `speakeasy_load_model()` via FFI.
- If absent, prompt the user to download it (or start downloading
  automatically with a progress indicator in the menu bar).

### Recording Flow

No changes to AudioRecorder.swift. The M4A file is still written to
disk; the Rust side handles decoding.

### Onboarding

The current first-launch experience likely asks for an API key. Update
this to instead show model download progress, with the API key as an
optional "advanced" setting for the cleanup feature.

## Build Changes

### whisper.cpp Compilation

The `whisper-rs` crate builds whisper.cpp from source via its `-sys`
crate. This requires:
- A C/C++ compiler (Xcode provides this)
- Metal framework headers (included in Xcode)
- The `metal` feature flag on `whisper-rs`

For the universal binary build (`just build` in `core/`), whisper.cpp
will be compiled twice (arm64 and x86_64) and lipo'd together along with
the rest of the static library. The existing build process should handle
this without modification since it already builds for both architectures.

Metal acceleration only applies on arm64. The x86_64 build will fall
back to CPU-only inference via Accelerate framework, which is still
reasonable on Intel Macs.

### App Bundle

The model file is not bundled in the .app; it is downloaded at runtime
to Application Support. No changes to the bundle/codesign/notarize
pipeline.

## Performance Expectations

On an M4 Max (40-core GPU, ~400 GB/s memory bandwidth):

| Model    | ~Realtime Factor | 10s clip    |
|----------|------------------|-------------|
| tiny     | 50-100x          | ~0.1-0.2s   |
| base     | 30-60x           | ~0.2-0.3s   |
| small    | 20-40x           | ~0.3-0.5s   |
| medium   | 15-25x           | ~0.4-0.7s   |
| large-v3 | 5-10x            | ~1-2s       |

Compare to the current API path: 1-3 seconds of network latency plus
server-side inference time, with a 60-second timeout. For short
dictation clips, even the large model will likely be faster than the
API.

Model loading (one-time at app startup): 1-3 seconds depending on model
size. This is amortized across all transcriptions in a session.

## Quality Notes

- OpenAI's hosted `whisper-1` is believed to be based on large-v2 with
  proprietary fine-tuning.
- Local large-v3 is generally comparable or slightly better for most
  languages.
- Local medium is a small step down but very good for clear microphone
  speech in English.
- For dictation (clear speech, single speaker, low noise), even the
  small model performs well.
- The existing transcript cleanup feature (GPT-4.1-nano for
  punctuation/capitalization) can still be used on top of local
  transcription.

## Migration Path

To avoid a hard cutover, the implementation can be staged:

1. Add whisper-rs integration and model management to the Rust core,
   behind a feature flag or runtime toggle
2. Add model download and selection UI to the Swift app
3. Default new installs to local transcription
4. Keep the API path available as a fallback setting
5. Once local is proven stable, remove the API transcription code

## Open Questions

- Should the app support both local and API transcription as a user
  preference, or fully replace the API path?
- Should we quantize models ourselves or pull pre-quantized GGML files
  from Hugging Face? (Pre-quantized is simpler and standard practice.)
- Is there value in supporting CoreML-optimized models (whisper.cpp
  supports them) for potentially faster inference, at the cost of a more
  complex model download/conversion step?
- Should the model download happen automatically on first launch or
  require explicit user action?
