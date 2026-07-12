# Linux Wayland / Arch Port

MVP: local Whisper STT with system tray, compositor-bound hotkeys, and
clipboard-only output. No auto-paste, no in-app global grabs, no cleanup LLM.

## Architecture

```
core/           pure: state machine + Whisper-on-WAV (shared)
linux/          platform only: audio, clipboard, tray, CLI/IPC, XDG, download
macos-menubar/  unchanged (staticlib + C ABI)
```

Linux depends on `core` as a Rust path crate. Platform I/O never enters `core`.

```
Compositor bind  →  speakeasy toggle  →  Unix socket
                                              ↓
                    linux daemon (orchestration)
                    ├── audio (cpal / PipeWire)
                    ├── clipboard (arboard)
                    ├── tray (StatusNotifierItem)
                    └── core (state + whisper)
```

## Stack

| Concern    | Choice                                      |
|------------|---------------------------------------------|
| Language   | Rust binary crate                           |
| Audio      | `cpal` → 16 kHz mono WAV                    |
| Clipboard  | `arboard` (user pastes)                     |
| Actions    | CLI + `$XDG_RUNTIME_DIR/speakeasy.sock`     |
| Tray       | StatusNotifierItem (`ksni` or equivalent)   |
| Whisper    | CPU default; optional Vulkan later          |
| Paths      | XDG via `dirs`                              |
| Packaging  | Document deps first; AUR later              |

## Out of scope (later)

- Cleanup LLM (llama.cpp / GGUF)
- Auto-paste (ydotool / uinput)
- Portal Input Capture
- Vulkan/CUDA as default backend
- AUR / Flatpak
- systemd user unit

## Stages

1. Core Linux build
   1a: Target-split `whisper-rs` features (Metal on macOS, CPU elsewhere)
   1b: Linux-friendly `just build` in `core/`; keep macOS path working
2. Workspace + `linux/` skeleton
   2a: Root Cargo workspace with `core` and `linux`
   2b: Binary stub; ensure `.gitignore` covers Rust artifacts
3. XDG paths + Whisper model download
   3a: Data/config under XDG (`~/.local/share/speakeasy/`, etc.)
   3b: Download same `ggml-small.en.bin` used on macOS
4. Audio capture
   4a: Mic via `cpal` → 16 kHz mono WAV matching core contract
5. Daemon pipeline
   5a: Wire state machine → record → transcribe → clipboard
   5b: CLI-driven only (no tray yet)
6. CLI + socket IPC
   6a: Long-running daemon; `toggle` / `start` / `stop` / `status`
   6b: Socket at `$XDG_RUNTIME_DIR/speakeasy.sock`
7. Tray
   7a: StatusNotifierItem icon + menu (record, quit, status)
   7b: Same actions as CLI
8. Docs
   8a: Arch deps, Hyprland/Sway/niri bind examples, how to run
   8b: Root README note that Linux exists
