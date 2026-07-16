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
- systemd user unit for start at login

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

## Install

Installs the release binary, a systemd user unit, and this README under
a prefix. Default prefix is `~/.local` (no root required).

```sh
cd linux
just install
```

Layout (default prefix):

| Artifact | Path |
|----------|------|
| Binary | `~/.local/bin/speakeasy` |
| User unit | `~/.local/share/systemd/user/speakeasy.service` |
| Docs | `~/.local/share/doc/speakeasy/README.md` |

Override the prefix if needed:

```sh
PREFIX=/usr/local just install   # typically needs write access
```

Ensure `~/.local/bin` is on your `PATH` when using the default prefix.

Remove an install with the same prefix:

```sh
just uninstall
# PREFIX=/usr/local just uninstall
```

## First run

1. Install (see above), or use `./target/release/speakeasy` from a build
   tree for one-off testing.

2. Download the default Whisper model (same `ggml-small.en.bin` as macOS,
   about 466 MB, once):

   ```sh
   speakeasy download-model
   ```

   Speakeasy pulls the file from Hugging Face Hub via the official
   `hf-hub` client (Xet transfers). A free read token is optional but
   helps if anonymous Hub access is rate-limited:

   ```sh
   export HF_TOKEN=hf_...   # or HUGGING_FACE_HUB_TOKEN
   speakeasy download-model
   ```

   Manual fallback if you already have the file (or prefer `hf download`):

   ```sh
   mkdir -p ~/.local/share/speakeasy/models
   # place ggml-small.en.bin at:
   # ~/.local/share/speakeasy/models/ggml-small.en.bin
   ```

3. Check paths:

   ```sh
   speakeasy paths
   ```

4. Enable the user service so the daemon starts at login:

   ```sh
   systemctl --user daemon-reload
   systemctl --user enable --now speakeasy.service
   systemctl --user status speakeasy.service
   ```

   Logs:

   ```sh
   journalctl --user -u speakeasy.service -f
   ```

5. Control recording (another terminal, or a compositor keybind):

   ```sh
   speakeasy toggle   # start recording
   speakeasy toggle   # stop, transcribe, copy to clipboard
   speakeasy status
   speakeasy quit     # or: systemctl --user stop speakeasy
   ```

### Session environment

The daemon needs a graphical session: PipeWire (or ALSA) for the mic,
the session D-Bus for the tray, and usually `WAYLAND_DISPLAY` (or
`DISPLAY`) for the clipboard. User units normally get
`XDG_RUNTIME_DIR` and the session bus. If clipboard or tray misbehave
after a systemd start, import the compositor environment once per
login (many sessions already do this):

```sh
systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP DISPLAY
dbus-update-activation-environment --systemd \
  WAYLAND_DISPLAY XDG_CURRENT_DESKTOP DISPLAY
```

## Paths

| Purpose | Location |
|---------|----------|
| Data | `~/.local/share/speakeasy/` |
| Config | `~/.config/speakeasy/` |
| Cache / temp WAVs | `~/.cache/speakeasy/` |
| Whisper model | `~/.local/share/speakeasy/models/ggml-small.en.bin` |
| Daemon socket | `$XDG_RUNTIME_DIR/speakeasy.sock` |
| Installed docs | `$PREFIX/share/doc/speakeasy/README.md` |

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
Prefer the systemd user unit for starting the daemon; compositor
`exec-once` / `exec` / `spawn-at-startup` is a fine alternate if you
do not want systemd.

### Hyprland

```conf
# ~/.config/hypr/hyprland.conf
bind = SUPER SHIFT, SPACE, exec, speakeasy toggle
bind = SUPER SHIFT, C, exec, speakeasy cancel
bind = SUPER SHIFT, Q, exec, speakeasy quit

# Alternate to systemd --user (only if the unit is not enabled):
# exec-once = speakeasy daemon
```

### Sway

```conf
# ~/.config/sway/config
bindsym $mod+Shift+space exec speakeasy toggle
bindsym $mod+Shift+c exec speakeasy cancel
bindsym $mod+Shift+q exec speakeasy quit

# Alternate to systemd --user (only if the unit is not enabled):
# exec speakeasy daemon
```

### niri

```kdl
// ~/.config/niri/config.kdl
binds {
    Mod+Shift+Space { spawn "speakeasy" "toggle"; }
    Mod+Shift+C { spawn "speakeasy" "cancel"; }
    Mod+Shift+Q { spawn "speakeasy" "quit"; }
}

// Alternate to systemd --user (only if the unit is not enabled):
// spawn-at-startup "speakeasy" "daemon"
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
  Re-run with `download-model -f` to replace it. If download fails, set
  `HF_TOKEN` or drop the file into the models path listed under Paths.

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
- Distro packages (AUR, Flatpak, and similar)
