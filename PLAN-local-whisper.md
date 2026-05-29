# Plan: Local Whisper via whisper.cpp

Replace the OpenAI Whisper API with local inference using whisper.cpp
(via whisper-rs Rust bindings with Metal GPU acceleration). The cleanup
feature (GPT-4.1-nano) remains as an optional API-backed feature.

## Key Architecture Decisions

- **whisper-rs** crate with `metal` feature flag for Apple Silicon GPU
  acceleration. Maintained on Codeberg, published to crates.io.
- **Stateful Rust core**: model loaded once at startup, held in memory,
  destroyed on quit. New lifecycle FFI functions replace the stateless
  per-call pattern.
- **Audio format change**: Swift records 16KHz mono PCM WAV (what
  Whisper expects natively) instead of 44.1KHz AAC.
- **Model downloaded on first run**: `ggml-small.en.bin` (466 MiB) from
  HuggingFace, stored in Application Support.
- **API key becomes optional**: only needed when "Clean Up Transcripts"
  is enabled.

## Stage 1: Change audio recording to 16KHz mono PCM WAV

1a. Modify `AudioRecorder.swift` output format from AAC/.m4a to
    16-bit PCM WAV at 16KHz mono
1b. Update temp file naming (.wav instead of .m4a)
1c. Verify recording still works end-to-end with the existing API
    path (OpenAI accepts WAV)

## Stage 2: Replace API transcription with local whisper.cpp in Rust core

2a. Update `Cargo.toml`: add `whisper-rs` with `metal` feature,
    remove `async-openai`, keep `reqwest` (still needed for cleanup)
2b. Remove `tokio`, `tokio-util`, `futures-util` (no longer needed;
    whisper-rs is synchronous)
2c. Remove `symphonia` (was only used for audio duration probing for
    the backup-request threshold strategy)
2d. Implement whisper context lifecycle: `whisper_init(model_path)`
    returns an opaque pointer, `whisper_destroy(ctx)` frees it
2e. Rewrite `transcribe_audio_blocking` to accept a context pointer
    instead of an API key, load PCM from the WAV file, run local
    inference via `WhisperState::full()`, concatenate segment text,
    and return
2f. Keep `cleanup_transcript_blocking` as-is (still calls OpenAI API
    via reqwest)
2g. Update `speakeasy_core.h` with new FFI signatures

## Stage 3: Update Swift integration and state machine

3a. Update `RustFFI.swift` with new FFI bindings (`whisperInit`,
    `whisperDestroy`, updated `transcribeAudio`)
3b. Add whisper context lifecycle management in `AppDelegate` (init
    on startup, destroy on quit)
3c. Update `TranscriptionService` to pass context pointer instead of
    API key
3d. Rework `RustAppStateMachine` and Rust `app_state.rs`: replace
    `NeedsApiKey` with `NeedsModel` state, make `Ready` reachable
    once a model file exists
3e. Update `AppEvent` enum: replace `ApiKeyProvided`/`ApiKeyRemoved`
    with `ModelLoaded`/`ModelRemoved`
3f. Make API key fully optional in `SettingsManager` (only required
    when cleanup toggle is on)

## Stage 4: Model management and first-run experience

4a. Add model storage directory:
    `~/Library/Application Support/Speakeasy/models/`
4b. Implement model download from HuggingFace using `URLSession`
    (`https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.en.bin`)
4c. Replace `APIKeyViewController` with a model download/management
    view (download progress, current model display)
4d. First-run flow: detect no model, show download prompt, download,
    transition to Ready
4e. Store model path in `settings.json`, detect model file existence
    on startup
4f. Update menu: "Download Model" / "Model: small.en" status instead
    of API key management

## Stage 5: Build system and cleanup

5a. Update `core/Justfile` build to link Metal framework (whisper-rs
    with `metal` needs `-framework Metal -framework MetalKit
    -framework MetalPerformanceShaders`)
5b. Update `macos-menubar/Package.swift` linker settings if
    additional system frameworks are needed
5c. Update `.gitignore` for model files
5d. Remove dead code paths (dual-request threshold logic, API-based
    transcription)
5e. Update `RELEASING.md` and `AGENTS.md` to reflect the new
    architecture

## Notes

- **Build time**: whisper-rs compiles whisper.cpp from source via its
  `-sys` crate. First builds will be slower. CMake is required.
- **Model distribution**: 466 MiB is too large for the DMG. Download
  on first run is the right approach.
- **Memory footprint**: `small.en` uses ~852 MB RAM while loaded,
  persistent for app lifetime.
- **Universal binary**: the existing `lipo` strategy works. Metal GPU
  acceleration only applies to Apple Silicon; x86_64 uses CPU with
  AVX/SSE.
- **Cleanup feature**: users who want fully offline operation leave it
  disabled. Users who want polished output add an API key and toggle
  it on.

## Implementation Status

- [ ] Stage 1: Change audio recording to 16KHz mono PCM WAV
- [ ] Stage 2: Replace API transcription with local whisper.cpp in Rust core
- [ ] Stage 3: Update Swift integration and state machine
- [ ] Stage 4: Model management and first-run experience
- [ ] Stage 5: Build system and cleanup
