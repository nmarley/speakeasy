# Speakeasy Linux (Wayland / Arch)

Local speech-to-text client for Linux. Records from the microphone,
transcribes with Whisper via the shared Rust `core/`, and copies the
result to the clipboard. Global hotkeys are bound in your compositor
(not inside the app). There is no auto-paste on Wayland; paste with
your normal shortcut after transcription.

## Features

- System tray (StatusNotifierItem) for toggle / cancel / quit
- Unix socket IPC for compositor keybinds
- One-shot CLI (`once`) for scripts and testing
- XDG paths for config, data, cache, and the Whisper model
- Fully local transcription (CPU whisper.cpp by default)

## Prerequisites (Arch)

```sh
sudo pacman -S --needed base-devel rust cmake clang pkgconf \
  alsa-lib pipewire pipewire-alsa dbus
```

Optional but recommended:

- A tray host (Waybar, KDE Plasma tray, etc.) for the StatusNotifierItem
- `wl-clipboard` if you want CLI clipboard tools alongside Speakeasy

Build tools: `just` is convenient (`pacman -S just`) but not required.

## Build

```sh
cd linux
just build
# binary: target/release/speakeasy
```

Or:

```sh
cd linux && cargo build --release
```

## First run

1. Download the default Whisper model (same `ggml-small.en.bin` as macOS):

   ```sh
   ./target/release/speakeasy download-model
   ```

2. Check paths:

   ```sh
   ./target/release/speakeasy paths
   ```

3. Start the daemon (loads model, starts tray + socket):

   ```sh
   ./target/release/speakeasy daemon
   ```

4. In another terminal (or via a keybind):

   ```sh
   speakeasy toggle   # start recording
   speakeasy toggle   # stop, transcribe, copy to clipboard
   speakeasy status
   speakeasy quit
   ```

Install the binary somewhere on your `PATH` if you want short commands
(for example copy `target/release/speakeasy` to `~/.local/bin/`).

## Paths

| Purpose | Location |
|---------|----------|
| Data | `~/.local/share/speakeasy/` |
| Config | `~/.config/speakeasy/` |
| Cache / temp WAVs | `~/.cache/speakeasy/` |
| Whisper model | `~/.local/share/speakeasy/models/ggml-small.en.bin` |
| Daemon socket | `$XDG_RUNTIME_DIR/speakeasy.sock` |

## CLI

```
speakeasy paths              Show XDG and model paths
speakeasy download-model     Download default Whisper model
speakeasy download-model -f  Re-download even if present
speakeasy record [seconds]   Record to a 16 kHz mono WAV only
speakeasy once [seconds]     Record, transcribe, copy (no daemon)
speakeasy daemon             Long-lived process (tray + socket)
speakeasy start|stop|toggle  Control recording via the daemon
speakeasy status|cancel|quit Daemon status / cancel / shutdown
speakeasy version
speakeasy help
```

## Compositor binds

Hotkeys are not grabbed inside Speakeasy. Bind keys in your compositor
to the CLI commands. Examples assume `speakeasy` is on your `PATH`.

### Hyprland

```conf
# ~/.config/hypr/hyprland.conf
bind = SUPER SHIFT, SPACE, exec, speakeasy toggle
bind = SUPER SHIFT, C, exec, speakeasy cancel
bind = SUPER SHIFT, Q, exec, speakeasy quit
```

Start the daemon from autostart:

```conf
exec-once = speakeasy daemon
```

### Sway

```conf
# ~/.config/sway/config
bindsym $mod+Shift+space exec speakeasy toggle
bindsym $mod+Shift+c exec speakeasy cancel
bindsym $mod+Shift+q exec speakeasy quit

exec speakeasy daemon
```

### niri

```kdl
// ~/.config/niri/config.kdl
binds {
    Mod+Shift+Space { spawn "speakeasy" "toggle"; }
    Mod+Shift+C { spawn "speakeasy" "cancel"; }
    Mod+Shift+Q { spawn "speakeasy" "quit"; }
}

spawn-at-startup "speakeasy" "daemon"
```

Adjust modifiers and keys to taste. `toggle` is the usual push-to-talk
stand-in: first press starts recording, second press stops and copies
the transcript.

## Workflow notes

- After `toggle` (stop), text is on the clipboard. Paste with your
  compositor or app paste binding (for example Ctrl+V).
- If the tray does not appear, the daemon still works over the socket;
  check that a StatusNotifier host is running.
- `once` does not need the daemon; useful for testing mic and model.
- Model download is large (~466 MB). It only needs to complete once.

## Architecture

```
Compositor bind  →  speakeasy toggle  →  Unix socket
                                              |
                    linux daemon
                    ├── tray (StatusNotifierItem)
                    ├── audio (cpal / PipeWire)
                    ├── clipboard (arboard)
                    └── core (state machine + Whisper)
```

Platform I/O stays in `linux/`. Shared transcription and state logic
live in `core/`.

## Out of scope (for now)

- Auto-paste into the focused window
- In-app global hotkey grabs
- Transcript cleanup LLM (macOS MLX path only today)
- AUR / Flatpak packaging
