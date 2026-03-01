# Speakeasy

Speakeasy is a lightweight macOS menu bar app that converts speech to text
in near real-time. Press a hotkey, speak, and your words are transcribed
and inserted directly into whatever text field you're working in.

It uses OpenAI's Whisper API for transcription. You bring your own API
key.

## Design Goals

- **Minimal and unobtrusive** -- lives in the menu bar, stays out of your
  way, follows macOS Human Interface Guidelines
- **Two recording modes** -- push-to-talk (hold to record) and toggle
  (press to start/stop), each with configurable global hotkeys
- **Instant text insertion** -- transcribed text is automatically pasted
  into the active text field via macOS accessibility APIs
- **No backend required** -- the app talks directly to OpenAI; there is
  no intermediary server

## Repository Structure

- **`core/`** -- Rust library that handles audio capture and
  transcription via the Whisper API
- **`macos-menubar/`** -- macOS menu bar application written in Swift,
  built with Swift Package Manager and AppKit

## License

This project is licensed under either of

 * MIT license ([LICENSE-MIT](LICENSE-MIT) or
   https://opensource.org/licenses/MIT)
 * Apache License, Version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or
   https://www.apache.org/licenses/LICENSE-2.0)
