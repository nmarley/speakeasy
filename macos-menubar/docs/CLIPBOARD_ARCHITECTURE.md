# Clipboard/Paste Operations

All previously documented race conditions have been resolved. This
document describes the current architecture for reference.

## Code Flow: Recording to Paste

```
1. User releases push-to-talk keys
   └─> PushToTalkManager.updatePushToTalkState()
       └─> DispatchQueue.main.async { delegate?.pushToTalkDidDisengage() }

2. AppDelegate.pushToTalkDidDisengage()
   └─> audioRecorder?.stopRecording { result in ... }
       └─> (completion runs on unknown thread)
           └─> transcribeAudio(url:)

3. transcribeAudio() [Speakeasy.swift]
   └─> TranscriptionService.shared.transcribe(audioURL:) { result in ... }

4. TranscriptionService.transcribe() [TranscriptionService.swift]
   └─> Task.detached { ... Rust FFI call ... }
   └─> Task { completion(.success(result)) }  // runs on cooperative thread pool

5. Completion handler [Speakeasy.swift]
   └─> DispatchQueue.main.async {
            stateMachine.process(...)               // state update first
            ClipboardManager.shared.paste(...)      // then paste, sequentially
            setupMenu()                             // then menu refresh
        }

6. ClipboardManager.paste() [ClipboardManager.swift]
   └─> save previousContent
   └─> write NSPasteboardItem with lazy data provider
       (private UTI first = eagerly fetched, .string second = lazy)
   └─> set isPasting = true
   └─> 10ms sync settle
   └─> post Cmd+V CGEvents (PushToTalkManager ignores events while isPasting)
   └─> start changeCount polling on background queue
   └─> return immediately (non-blocking)

7. Restoration (async, event-driven)
   └─> Signal A: PasteDataProvider callback for .string fires
       └─> consumer read the data, restore clipboard, isPasting = false
   └─> Signal B: changeCount changes (polled every 10ms)
       └─> another app took the clipboard, skip restore, isPasting = false
   └─> Signal C: pasteboardFinishedWithDataProvider fires
       └─> ownership lost before consumption, skip restore
   └─> Fallback: 5s safety timeout
       └─> something went wrong, restore anyway, isPasting = false
```

## Design Decisions

### Lazy data provider (two-type trick)

macOS eagerly fetches the first pasteboard type at `writeObjects` time.
To get a signal when the consuming app actually reads the paste, we
register two types: a private UTI (`com.speakeasy.transcription`) as
the first type (absorbs the eager fetch) and `.string` as the second
(lazily provided only when a consumer reads it).

### Event tap guard

`ClipboardManager.isPasting` is set to `true` while a paste is in
flight. `PushToTalkManager.handleEvent` checks this flag and passes
events through unmodified during paste, preventing synthetic Cmd+V
modifier events from confusing push-to-talk state tracking.

### Clipboard restoration

The previous clipboard content is always restored after the consuming
app reads the transcription. If another app takes clipboard ownership
before consumption, restoration is skipped (we would clobber the new
content). A 5-second safety timeout ensures restoration happens even
if the paste signal is never received.

## Testing Recommendations

1. Run 50+ consecutive transcriptions with clipboard pre-populated
2. Test with various target apps (native, Electron, Java-based)
3. Test while Universal Clipboard is active (iPhone nearby)
4. Verify no "CLIPBOARD RESTORATION FAILED" errors in logs
5. Confirm correct content is pasted every time
6. Monitor for "safety timeout reached" warnings (indicates fallback fired)
