# Speakeasy

macOS menu bar app that converts speech to text using local Whisper
inference via whisper.cpp with Metal GPU acceleration. Press a hotkey,
speak, and transcribed text is pasted into the active text field.

## Architecture

The project has two components:

- **`core/`** -- Rust static library handling audio capture and
  transcription via whisper.cpp (whisper-rs bindings with Metal GPU
  acceleration). Builds as an arm64-only static lib linked by the
  Swift app through a C header (`speakeasy_core.h`).

- **`macos-menubar/`** -- Swift + AppKit menu bar application built
  with Swift Package Manager. Links against
  `core/target/release/libspeakeasy_core.a`. Transcript cleanup runs
  locally via MLX Swift (Gemma 3 1B QAT 4-bit) on the Metal GPU, no
  network calls required.

## Build Chain

The Rust library must be built before the Swift app. Both build
arm64-only (MLX requires Apple Silicon):

```sh
cd core && just build            # arm64 static lib
cd macos-menubar && just build   # Swift debug build (checks for lib)
```

## Key Commands

All commands use `just` (justfile runner).

### Root

- `just version` -- show version from git tags
- `just bump <version>` -- bump version across all source files

### Core (`core/`)

- `just build` -- arm64 static lib
- `just check` -- cargo check
- `just test` -- cargo test
- `just fmt` -- cargo fmt

### macOS App (`macos-menubar/`)

- `just build` -- debug build (runs swift-format first)
- `just run` -- debug run
- `just build-release` -- arm64 release binary
- `just bundle` -- create .app bundle
- `just codesign` -- codesign release bundle
- `just build-dmg` -- create DMG installer
- `just build-dmg-debug` -- create unsigned debug DMG for local testing
- `just release` -- full release pipeline (build, sign, notarize,
  staple DMG)
- `just clean` -- remove build artifacts

### Release Pipeline

Full release: `cd macos-menubar && just release`

Requires `.env` with `DEVELOPER_ID`, `APPLE_DEVELOPER_TEAM_ID`,
`APPLE_ID_EMAIL`, and `NOTARIZATION_PASSWORD`.

## Versioning

Version is derived from git tags. To release a new version:

1. `just bump <version>` (updates Swift, plist, and Cargo.toml)
2. Commit and tag: `git tag -s v<version>`

### Tag Message Format

```
Release v<version>

<Component>
- <change>
- <change>

<Component>
- <change>
```

- Subject line: `Release v<version>`
- Blank line after subject
- Changes grouped by component heading (plain text, no markdown)
- Component headings used: `Core`, `macOS App`, `Internal`, etc.
- One `- ` bullet per change, describing what changed

## Conventions

- Rust: edition 2024, formatted with `cargo fmt`
- Swift: formatted with `swift-format` (runs automatically on build)
- Dual-licensed: MIT / Apache-2.0
