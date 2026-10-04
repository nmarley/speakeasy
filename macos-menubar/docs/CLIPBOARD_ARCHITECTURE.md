# Text Insertion

After transcription (and optional cleanup), Speakeasy inserts the text
into the focused field. Accessibility is the primary path. Clipboard
paste is the fallback when the focused element cannot take selected
text.

## Recording to insert

Push-to-talk release stops recording, then `transcribeAudio` runs
Whisper. On success, optional MLX cleanup runs. Both the raw and
cleaned finish paths call `insertTranscription` on the main queue
after the state machine update and before the menu refresh.

`insertTranscription` tries `TextInserter` first. On AX success it
returns without touching the pasteboard. On AX failure it calls
`ClipboardManager.paste`.

## Accessibility insert

`TextInserter` reads the system-wide focused element and, if
`kAXSelectedTextAttribute` is settable, writes the transcription
there. That inserts at the caret (or replaces the current selection)
without using the clipboard, so there is no restore race.

This fails for Chrome, Electron, Terminal, secure fields, and any
element that does not expose settable selected text. Those cases fall
back to clipboard paste. Accessibility permission is already required
for the push-to-talk event tap.

## Clipboard fallback

`ClipboardManager.paste` runs only on the main thread. It snapshots
the current string pasteboard, writes the transcription, fences the
write by reading `changeCount`, then posts a full Command-down,
V-down, V-up, Command-up sequence from a private `CGEventSource` on
the next runloop turn.

`ClipboardManager.isPasting` is true only while those synthetic keys
are in flight (about 100ms). `PushToTalkManager` passes events through
while it is true so the fake Command-V does not confuse modifier
tracking. Restoration does not hold this flag; a 5s restore must not
keep push-to-talk deaf.

A monotonic `pasteGeneration` invalidates any in-flight key-post or
restore from an earlier dictation.

## Clipboard restoration

Pasteboard reads never bump `changeCount`, so there is no signal that
the target consumed the paste. The previous clipboard is restored
after a 5s safety timeout, on the main thread, only if `changeCount`
is still the value from our write. If another app wrote in the
meantime, restore is skipped.

A 500ms restore was too short on macOS 26: slow consumers read the
already-restored previous clipboard instead of the transcription.

## Testing

1. Native AppKit fields (Notes, TextEdit): AX insert, clipboard
   unchanged.
2. Chrome, Electron, Terminal: AX fails, clipboard paste, correct
   text in the target.
3. Fifty consecutive dictations with a pre-populated clipboard.
4. Universal Clipboard active (iPhone nearby).
5. No "CLIPBOARD RESTORATION FAILED" errors in logs.
6. History in the Speakeasy menu matches what landed in the target.
