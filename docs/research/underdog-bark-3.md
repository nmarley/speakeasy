# Underdog Bark 3.0 Research

Status: parked 2026-10-21. No implementation planned.
Decision: wait for a native small-model Swift runtime. Keep Whisper
indefinitely as the supported backend.

## Summary

Underdog Bark 3.0 is a real, strong speech recognition model. It is
English-only, based on NVIDIA Parakeet TDT 0.6B v3 via Moondream
Parakeet Ultra, and licensed CC-BY-4.0. The smallest member is a
163 MB download that reports 4.94 percent average word error on the
Open ASR Leaderboard's seven English sets, beating Whisper large-v3
at 6.04 percent from a 9.26 GB download.

The catch is runtime support. Underdog ships no open native Swift
runtime for the 163 MB model. The small Core ML package provides
only an encoder plus a NumPy decoder, so a native app must port the
audio frontend and TDT decoder to Swift. The ready-made Swift path is
Bark 3.0 Pro, a 1.23 GB Core ML package that runs through FluidAudio.

The app currently uses Whisper small.en at 466 MB. Bark 3.0 small is
about 2.3 times smaller and likely more accurate, but the integration
cost is the blocker. Waiting for Underdog or FluidAudio to publish a
native small-model runtime is the lowest-risk path for now.

## Model Family

Released 2026-10-15 by Underdog (Conway Research).

| Model | Download | Average WER | Notes |
| --- | --- | --- | --- |
| Bark 3.0 | 163 MB | 4.94% | Verbatim, keeps fillers |
| Bark 3.0 Clean | 180 MB | 5.83%* | Removes fillers and false starts |
| Bark 3.0 Plus | 180 MB | 4.76% | Verbatim, larger sibling |
| Bark 3.0 Pro | 1.25 GB | 4.29% | Full precision, best accuracy |

\* Clean removes fillers on purpose. The benchmark keeps every "um",
so each dropped filler counts as an error. Against cleaned transcripts
Clean scores 4.08%; raw Bark 3.0 scores 16.53% against cleaned text
and 3.15% against verbatim text.

Selected benchmarks from Underdog's model cards. These rows use the
leaderboard's scoring code but are not yet on the leaderboard, so
treat them as self-reported.

| Model | Download | AMI | Average |
| --- | --- | --- | --- |
| Bark 3.0 Pro | 1.25 GB | 7.16 | 4.29 |
| Bark 3.0 Plus | 180 MB | 7.76 | 4.76 |
| Bark 3.0 | 163 MB | 7.82 | 4.94 |
| Parakeet TDT 0.6B v3 | 2.51 GB | 9.42 | 4.94 |
| Phonon-2 | 164 MB | 9.32 | 5.21 |
| Whisper large-v3 | 9.26 GB | 13.63 | 6.04 |
| Whisper large-v3-turbo | 1.62 GB | 13.88 | 6.58 |

Meetings are where Bark shows best: 7.82% on AMI against 13.63% for
Whisper large-v3. On DisfluencySpeech, raw Bark 3.0 scores 3.15% with
fillers counted, versus 3.39% for Phonon-2.

Bark 3.0 is English only. It has no word timings, no speaker labels,
and no custom vocabulary support yet.

## Why It Fits Speakeasy

- The current model is Whisper small.en, 466 MB, English only.
- Bark 3.0 small is roughly 200 MB as a Core ML package, so the
  download shrinks while accuracy should improve.
- The small Core ML encoder runs on the Apple Neural Engine, leaving
  the GPU free for the existing Qwen cleanup model.
- The app already has a Hugging Face client, Core ML is native, and
  the cleanup model already runs locally.
- The app is already English only, so Bark's language limit is not a
  regression.

## Artifacts And Interfaces

### Small Core ML package

The small model has two alternative Core ML packages, `coreml/ane`
and `coreml/gpu`. The ANE package is the better fit for dictation
because it uses less power and does not contend with MLX cleanup.

Files needed from `coreml/ane`:

| File | Size | Purpose |
| --- | --- | --- |
| `BarkEncoder.mlpackage` | ~191 MB | Quantized FastConformer encoder |
| `decoder.npz` | 11.2 MB | LSTM, joint head, mel filters |
| `vocab.json` | 116 KB | Token pieces, special IDs, durations |

Total download is about 202 MB. The 163 MB headline refers to
`model.bark`, the compressed weight container, not the Core ML
package or the unpacked MLX weights.

Encoder interface, from the model card and the reference runner:

- Input `features`: FP16 `[1, T, 128]`.
- Input `mask`: Int32 `[1, T]`.
- Output `encoded`: FP16 `[1, T', 640]`.
- `T = window_seconds * 100 + 1`.
- ANE package has multifunction functions `w8` and `w15`.
- GPU package has a fixed 15-second encoder.
- The package requires macOS 15 or later.

`decoder.npz` contents, verified by inspecting the downloaded file:

| Array | Shape | Dtype |
| --- | --- | --- |
| `decoder.embedding.weight.q` | 8193 x 640 | int8 |
| `decoder.embedding.weight.s` | 8193 | float16 |
| `decoder.lstm.weight_ih_l0.q` | 2560 x 640 | int8 |
| `decoder.lstm.weight_ih_l0.s` | 2560 | float16 |
| `decoder.lstm.weight_hh_l0.q` | 2560 x 640 | int8 |
| `decoder.lstm.weight_hh_l0.s` | 2560 | float16 |
| `decoder.lstm.weight_ih_l1.q` | 2560 x 640 | int8 |
| `decoder.lstm.weight_hh_l1.q` | 2560 x 640 | int8 |
| `decoder.lstm.bias_ih_l0` | 2560 | float16 |
| `decoder.lstm.bias_hh_l0` | 2560 | float16 |
| `decoder.decoder_projector.weight.q` | 640 x 640 | int8 |
| `decoder.decoder_projector.weight.s` | 640 | float16 |
| `decoder.decoder_projector.bias` | 640 | float16 |
| `joint.head.weight.q` | 8198 x 640 | int8 |
| `joint.head.weight.s` | 8198 | float16 |
| `joint.head.bias` | 8198 | float16 |
| `mel_filters` | 128 x 257 | float32 |

`vocab.json` values:

- `pieces`: 8192 token pieces.
- `special_ids`: 3 entries, `[0, 2, 8192]`.
- `blank_id`: 8192.
- `vocab_size`: 8193.
- `durations`: 5.
- `max_symbols_per_step`: 10.

### Pro Core ML package

`coreml/` contains four Core ML packages plus the vocabulary:

- `Preprocessor.mlpackage`, about 1.2 MB.
- `Encoder.mlpackage`, about 1.20 GB.
- `Decoder.mlpackage`, about 23.6 MB.
- `JointDecisionv3.mlpackage`, about 12.6 MB.
- `parakeet_v3_vocab.json`, about 143 KB.

Total is about 1.23 GB. This package is already wired to FluidAudio.

### model.bark container

`model.bark` uses a custom format, `bark-levels-v2` or
`bark-levels-v3`. Encoder linear weights use per-row FP16 levels plus
ANS entropy-coded codes. Other matrices use per-row symmetric
integers with FP16 row scales. Some small blobs are LZMA compressed.
The Python loader needs the `constriction` package for ANS decoding.
A Swift port of this container is significantly harder than using
the Core ML package, which is why it is not recommended.

## Reference Algorithms

The Python reference is `coreml/ane/bark_coreml.py` in the model
repository. It is roughly 200 lines and is the specification for a
Swift port.

### Frontend

- Input is mono 16 kHz float audio.
- Pre-emphasis: `x[0]`, then `x[i] - 0.97 * x[i-1]`.
- Center the signal by padding 256 samples on each side.
- STFT: FFT size 512, window 400, hop 160.
- Window is symmetric Hann, zero-padded into 512 samples.
- Power spectrum, 257 bins.
- Slaney mel filter bank, 128 bins, stored in `mel_filters`.
- Natural log with a `2^-24` floor.
- Per-utterance normalization using only the valid frames,
  `valid = length / hop`, with an epsilon of `1e-5`.
- Frames after `valid` are zeroed.

### Encoder

- Add 0.25 seconds of leading silence.
- Pick `w8` when the padded clip fits in 8 seconds, otherwise `w15`.
- Pad features to `T = window_seconds * 100 + 1`.
- Mask valid frames.
- Run the encoder on the ANE or GPU.
- Slice the output to `enc_len(valid)`, where `enc_len` applies
  three stride-2 convolutions: `n = (n - 1) / 2 + 1` three times.

### Decoder

- Two LSTM layers, 640 hidden units each.
- Initial token is blank, ID 8192.
- For each encoder frame:
  - Compute joint logits from `max(encoded[t] + decoder_out, 0)`.
  - Argmax the vocabulary logits and the duration logits.
  - Blank advances time by `max(duration, 1)`.
  - Non-blank emits the token and updates the LSTM state.
  - A zero duration with too many symbols forces a time step.
- Dequantize int8 weights with per-row FP16 scales:
  `q * scale[:, None]`.
- Detokenize by joining pieces, skipping special IDs, and replacing
  the sentencepiece marker with a space.

### Segmentation

Audio longer than 15 seconds is cut at pauses. Within each 5 to
14.75 second stretch, find the quietest 200 ms span using smoothed
10 ms energy and cut in the middle. This avoids splitting a word.

## Integration Options

### A. Small Core ML port

Download the ANE package, port the frontend and decoder to Swift,
run the encoder on the ANE.

- Download: about 200 MB.
- Accuracy: 4.94% average WER.
- Work: roughly 600 lines of Swift plus tests.
- Effort: 2 to 4 focused days.
- Risk: medium. The DSP and decoder must match the Python reference
  exactly. Golden tests and a local benchmark are required.
- Dependencies: none beyond Apple frameworks. `decoder.npz` needs a
  minimal NPY reader. The NPZ is a ZIP with DEFLATE entries, so a
  small ZIP parser plus Foundation `Compression` is enough. The
  arrays are C-order little-endian `int8`, `float16`, and `float32`.
- macOS 15 or later.

### B. Pro Core ML plus FluidAudio

Add FluidAudio at the revision Underdog validated, download the Pro
Core ML package, and use the reference runner code.

- Download: about 1.23 GB.
- Accuracy: 4.29% average WER.
- Work: about one day.
- Risk: low. Underdog publishes a working Swift runner.
- Dependency: FluidAudio, Apache-2.0, pinned at
  `a00964e1aa8eff99c4bce80bc9c8ff2d4dd1568d`.
- macOS 15 or later, Swift 6.2.

Reference flow:

```swift
let models = try AsrModels(
    encoder: load("Encoder", units, function: function),
    preprocessor: load("Preprocessor", .cpuOnly),
    decoder: load("Decoder", .cpuOnly),
    joint: load("JointDecisionv3", .cpuOnly),
    configuration: config,
    vocabulary: vocabulary,
    version: .ultra
)
let manager = AsrManager(models: models)
var state = try TdtDecoderState()
let result = try await manager.transcribe(samples, decoderState: &state)
```

Use `.cpuAndNeuralEngine` for the encoder when running on the ANE,
and `.cpuOnly` for the other models. The first load compiles the
`.mlpackage` files and can take minutes. An app should compile once,
cache the `.mlmodelc` files, and reuse them.

The downside is size. Pro is 2.6 times larger than the current
Whisper small.en download, which contradicts the "smaller" reason
for looking at Bark.

### C. Wait for a native small runtime

Do nothing now. Revisit when one of these happens:

- Underdog publishes its native Swift runtime or a complete Core ML
  package for the 163 MB model.
- FluidAudio adds support for the small Bark encoder and decoder.
- The app raises its macOS floor and the 1.23 GB Pro package becomes
  acceptable.
- Whisper small.en accuracy becomes a real product problem.

### D. FluidAudio Parakeet Ultra, not Bark

FluidAudio already ships `parakeet-ultra-coreml`, about 631 MB,
multilingual across 25 European languages, with a one-call
`AsrModels.downloadAndLoad(version: .ultra)` API. It is not Bark,
but it is the lowest-risk turnkey accuracy upgrade if the goal
changes from "use Bark" to "use a better on-device ASR model."

## Current Speakeasy Integration Points

- `core/src/audio.rs` loads 16 kHz mono WAV files and runs
  whisper-rs with Metal. `transcribe_local` calls `state.full`.
- `core/Cargo.toml` depends on `whisper-rs` with the `metal` feature
  and `hound`.
- `macos-menubar/Sources/Speakeasy/TranscriptionService.swift` calls
  `RustFFI.transcribeAudio`.
- `macos-menubar/Sources/Speakeasy/Speakeasy.swift` loads the Whisper
  context once in `loadWhisperModel` and keeps it for the app lifetime.
- `macos-menubar/Sources/Speakeasy/SettingsManager.swift` owns the
  single model path, name, size, and download URL. The default is
  `ggml-small.en.bin` from the whisper.cpp Hugging Face repository.
- `macos-menubar/Sources/Speakeasy/ModelDownloadService.swift`
  downloads one file with `URLSession`.
- `macos-menubar/Sources/Speakeasy/ModelManagementViewController.swift`
  presents a single-file download, progress, and delete UI.
- `macos-menubar/Sources/Speakeasy/RustAppStateMachine.swift` checks
  `SettingsManager.hasModel()` at launch and exposes `needsModel`.
- `macos-menubar/Package.swift` declares macOS 14.
- `macos-menubar/assets/Info.plist` declares `LSMinimumSystemVersion`
  13.0.
- The cleanup model is Qwen2.5 1.5B Instruct 4-bit via MLX. Its
  contract allows only punctuation and capitalization changes, and
  every input word must survive exactly.

## Implementation Sketch If Revived

Stage 0: Prove the port

- Add a debug-only `BarkProbe`, following the existing
  `CleanupProbe` pattern. Run it with a `just bark-probe` recipe.
- Download `coreml/ane/BarkEncoder.mlpackage`, `decoder.npz`, and
  `vocab.json` into a local test folder.
- Port the frontend, encoder wrapper, decoder, segmenter, and
  detokenizer to Swift.
- Parse `decoder.npz` with a minimal ZIP reader and NPY parser.
- Run 10 to 20 real dictation clips through Bark and the current
  Whisper model. Compare transcripts, word error rate, latency, and
  peak memory.
- Gate: proceed only if output matches the Python reference and
  beats Whisper on real clips.

Stage 1: Integrate

- Add a `BarkModelStore` that downloads with
  `HubClient.downloadSnapshot`, using globs for `coreml/ane/**` and
  `coreml/NOTICE`.
- Verify file sizes and hashes, compile the encoder once, cache the
  `.mlmodelc`, and delete the source `.mlpackage` after a successful
  compile.
- Add `BarkTranscriber` and a `SpeechTranscriber` protocol. Keep the
  existing Rust and Whisper path as the fallback implementation.
- Switch `TranscriptionService` and `AppDelegate` to the protocol.
- Update model management, menu text, deletion, and the state
  machine's `hasModel` check.
- Add NOTICE and attribution, and update the README and AGENTS.
- Add unit tests for frontend shapes, decoder golden values, and
  detokenization, plus an integration test on a known WAV.

Stage 2: Retire Whisper, optional

- Raise `Package.swift` and `LSMinimumSystemVersion` to macOS 15.
- Remove `whisper-rs`, `hound`, `core/src/audio.rs`, the whisper FFI
  declarations in `speakeasy_core.h`, and the Swift wrappers in
  `RustFFI`.
- Remove the Whisper model download and management path.
- Run `just build`, `just test`, `just probe`, and a release DMG
  smoke test.

## Risks And Constraints

- The small decoder is int8 and must be dequantized exactly like the
  Python reference. Golden tests are mandatory.
- First-run Core ML compilation can take minutes. Show a
  "Preparing model" state and cache the compiled model.
- Keeping both the `.mlpackage` and `.mlmodelc` roughly doubles disk
  use until the source package is deleted.
- The Core ML packages require macOS 15. The app currently supports
  macOS 13 and 14.
- `Bark 3.0 Clean` removes fillers and false starts, which conflicts
  with the app's verbatim cleanup contract. Raw Bark 3.0 is the only
  variant that fits without changing the contract.
- Bark is English only. The current app is English only, so this is
  not a regression.
- Bark has no word timings, speaker labels, or custom vocabulary.
  The app does not use any of them.
- The model is CC-BY-4.0. Attribution is required. The repository's
  `NOTICE` credits NVIDIA and Moondream. FluidAudio is Apache-2.0.
- Underdog's benchmark numbers are self-reported and not yet on the
  Open ASR Leaderboard. A local benchmark is required before making
  a product decision.

## Decision Log

2026-10-21:

- Chose to wait for a native small-model Swift runtime.
- Chose to keep Whisper indefinitely as the supported backend.
- No code or model changes made.
- Research parked in this document.

## Sources

- https://underdog.ai/bark
- https://huggingface.co/ConwayResearch/Underdog-Bark-3.0
- https://huggingface.co/ConwayResearch/Underdog-Bark-3.0-Pro
- https://huggingface.co/ConwayResearch/Underdog-Bark-3.0/tree/main/coreml/ane
- https://github.com/FluidInference/FluidAudio
- https://huggingface.co/FluidInference/parakeet-ultra-coreml
- https://huggingface.co/nvidia/parakeet-tdt-0.6b-v3
