# Speakeasy

Speakeasy converts speech to text fully on-device. Speak, get a
transcript on the clipboard (or pasted on macOS), and keep working.

## Platforms

- **macOS** (`macos-menubar/`) -- menu bar app with global hotkeys,
  automatic paste into the active field, Metal-accelerated Whisper, and
  optional on-device transcript cleanup via MLX.
- **Linux** (`linux/`) -- Wayland-friendly daemon with system tray,
  compositor-bound hotkeys, clipboard-only output, and CPU Whisper by
  default. See [linux/README.md](linux/README.md).

Both front ends share the Rust **`core/`** library for the app state
machine and Whisper transcription via whisper.cpp.

## Design Goals

- **Minimal and unobtrusive** -- menu bar / tray, stays out of the way
- **Fully local** -- transcription on-device; no API keys required
- **Fast enough for flow** -- press a bind, speak, get text without
  context-switching to another app

macOS-specific goals (Accessibility paste, MLX cleanup, Metal) are
documented under `macos-menubar/`. Linux goals (compositor binds,
clipboard-only paste, StatusNotifierItem) are documented under `linux/`.

## Repository Structure

- **`core/`** -- Rust library: deterministic state machine and Whisper
  transcription on 16 kHz mono WAV (Metal on macOS, CPU on Linux)
- **`macos-menubar/`** -- Swift/AppKit menu bar application
- **`linux/`** -- Rust Wayland/Arch client (daemon, tray, socket IPC)

## License

This project is licensed under either of

 * MIT license ([LICENSE-MIT](LICENSE-MIT) or
   https://opensource.org/licenses/MIT)
 * Apache License, Version 2.0, ([LICENSE-APACHE](LICENSE-APACHE) or
   https://www.apache.org/licenses/LICENSE-2.0)
