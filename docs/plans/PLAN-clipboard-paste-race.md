# Clipboard Paste Race

## Intent

Speakeasy's menu transcript history is correct, but the target app
receives the previous clipboard contents about 30-40% of the time.
That is a clipboard restore race, not a Whisper or cleanup failure.

`ClipboardManager` writes the new transcript, posts a synthetic Cmd+V,
then restores the previous clipboard after a blind 500ms timer.
Pasteboard reads never bump `changeCount`, so a slow consumer (common
on macOS 26.7) reads the restored previous contents instead of the
new transcript. Widening the timer from 100ms to 500ms already failed
to close this class of bug. The architecture doc describes
restore-on-read that was never built. The README claims Accessibility
insert that was also never built.

## Stage 1: Make clipboard paste race-safe

1a: Drive restore from a main-thread Timer. NSPasteboard is
main-thread only. Drop the background `Thread.sleep` poll.
1b: Restore previous clipboard only after a 5s safety timeout, and
skip if `changeCount` moved.
1c: Clear `isPasting` about 100ms after posting keys, independent of
restore, so push-to-talk does not stay deaf for the restore window.
1d: Post Command-down, V-down, V-up, Command-up from a private
`CGEventSource` on the next runloop turn after the pasteboard write
fence.
1e: Do not touch `isPasting` from the restore path. A superseded
restore must not leave the guard stuck, and must not clear a newer
paste's guard.

## Stage 2: Insert via Accessibility first

2a: New inserter: focused element plus `kAXSelectedTextAttribute`.
Accessibility permission is already granted for the event tap.
2b: On AX success, do not touch the clipboard.
2c: On AX failure (Chrome, Electron, Terminal, secure fields), fall
back to Stage 1 clipboard paste.

## Stage 3: Sync the clipboard architecture doc

3a: Rewrite `macos-menubar/docs/CLIPBOARD_ARCHITECTURE.md` to match
the AX-first, clipboard-fallback path. Separate commit, no code.
