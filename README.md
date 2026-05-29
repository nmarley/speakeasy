# Speakeasy

Speakeasy is a lightweight macOS menu bar app that converts speech to text
in near real-time. Press a hotkey, speak, and your words are transcribed
and inserted directly into whatever text field you're working in.

Transcription runs entirely on-device using whisper.cpp with Metal GPU
acceleration on Apple Silicon. No API key is required for transcription.
An optional transcript cleanup feature (punctuation and capitalization
via GPT-4.1-nano) is available for users who provide an OpenAI API key.

## Design Goals

- **Minimal and unobtrusive** -- lives in the menu bar, stays out of your
  way, follows macOS Human Interface Guidelines
- **Two recording modes** -- push-to-talk (hold to record) and toggle
  (press to start/stop), each with configurable global hotkeys
- **Instant text insertion** -- transcribed text is automatically pasted
  into the active text field via macOS accessibility APIs
- **Fully local transcription** -- runs Whisper inference on-device via
  Metal GPU acceleration; no data leaves your Mac unless you opt in to
  the transcript cleanup feature

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
