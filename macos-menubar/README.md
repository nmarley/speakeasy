# Speakeasy macOS Menu Bar App

Swift/AppKit menu bar application. Uses the Rust core library for local
audio transcription via whisper.cpp with Metal GPU acceleration.
Transcript cleanup (punctuation and capitalization) runs locally via
MLX Swift (Gemma 3 1B QAT 4-bit) on the Metal GPU, no network calls
required.

## Prerequisites

- Xcode command line tools
- Metal Toolchain (one-time download):
  `xcodebuild -downloadComponent MetalToolchain`
- Rust toolchain (for building `core/`)
- `swift-format` (for code formatting)
- `just` (task runner)

## Development

Build the Rust core library first:

```sh
cd ../core && just build
```

Then build and run:

```sh
just build
just run
```

## Release

Full release pipeline (build, codesign, notarize, staple, DMG):

```sh
just release
```

Codesigning credentials are loaded automatically from `.env` (see
`.env.example` for the required variables).

See `just --list` for all available commands, and `docs/` for
DMG build notes and other internal documentation.
