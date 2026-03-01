# Speakeasy Core

A Rust library containing the core state machine logic for the Speakeasy voice transcription application. This core provides deterministic state management that can be used across multiple platform-specific UIs (macOS, Linux, Windows).

## Purpose

Speakeasy is a productivity tool for developers that enables voice-to-text transcription via global hotkeys. Users can hold a key combination, speak, and have their transcription instantly streamed into their current application window - all without breaking their coding flow state.

This Rust core provides a pure state machine that manages application state transitions for:

- Application state validation and transitions
- Recording flow state management
- API key requirement enforcement
- State queries for UI decision making

## Architecture

The core is designed as a C-compatible library that exposes a pure functional state machine via FFI (Foreign Function Interface). This allows platform-specific UI layers to manage application state consistently while maintaining optimal performance and predictable behavior.

## Platform Integration

The core exposes a C-compatible API that platform-specific applications
can call. Currently only macOS is implemented:

- **macOS (Swift)** - Calls Rust core via Swift's C interop

If Linux or Windows UIs were added, they could call the same C API via
P/Invoke or equivalent FFI mechanisms.

Platform UIs handle:
- Global hotkey registration and monitoring
- Audio recording from microphone
- API communication and authentication
- System tray/menu bar integration
- Clipboard operations and text pasting
- OS-specific notifications and deep linking

## Data Flow

1. **User Input**: Platform UI detects hotkey press/release
2. **State Transition**: UI calls Rust core to validate and transition app state
3. **State Query**: Platform queries state machine for UI decisions
4. **Platform Actions**: UI performs actions based on current state
5. **Event Processing**: Platform sends events to update state machine
6. **State Update**: Core processes state transitions deterministically
7. **UI Update**: Platform UI updates based on new state

## Development Workflow

The core is built as a static library that platform applications link against:

```bash
# Build the core library
cargo build --release

# Link library from platform projects
```
