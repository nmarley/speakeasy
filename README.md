# Speakeasy

Speakeasy is a lightweight macOS menu bar app that converts speech to text
in near real-time. Press a hotkey, speak, and your words are transcribed
and inserted directly into whatever text field you're working in.

Both transcription and transcript cleanup run entirely on-device.
Transcription uses whisper.cpp with Metal GPU acceleration on Apple
Silicon. Transcript cleanup (punctuation and capitalization) runs via
MLX Swift (Gemma 3 1B QAT 4-bit) on the Metal GPU. No API keys are
required, no data leaves your Mac.

## Design Goals

- **Minimal and unobtrusive** -- lives in the menu bar, stays out of your
  way, follows macOS Human Interface Guidelines
- **Two recording modes** -- push-to-talk (hold to record) and toggle
  (press to start/stop), each with configurable global hotkeys
- **Instant text insertion** -- transcribed text is automatically pasted
  into the active text field via macOS accessibility APIs
- **Fully local** -- both transcription and cleanup run on-device via
  Metal GPU acceleration; no data leaves your Mac

## Repository Structure

- **`core/`** -- Rust library that handles audio capture and local
  Whisper transcription via whisper.cpp with Metal acceleration
- **`macos-menubar/`** -- macOS menu bar application written in Swift,
  built with Swift Package Manager and AppKit

## License

This project is licensed under either of

 * MIT license ([LICENSE-MIT](LICENSE-MIT) or
   https://opensource.org/licenses/MIT)
 * Apache License, Version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or
   https://www.apache.org/licenses/LICENSE-2.0)
