# Secure Input Resilience

## Problem

Speakeasy's push-to-talk hotkey silently dies and restarting the app does
not fix it. Investigation on the affected machine found
`kCGSSessionSecureInputPID` set in the IORegistry `IOConsoleUsers` property,
held by Ghostty (PID 3076). When any process enables macOS Secure Input
(Secure Keyboard Entry / `EnableSecureEventInput`), the OS stops delivering
key events to every `CGEventTap` system-wide as an anti-keylogger measure.
Speakeasy's entire hotkey mechanism is built on a `CGEventTap`
(`PushToTalkManager.swift`), so it goes completely dead while normal typing
into apps still works.

Symptoms explained by this root cause:

- Hotkeys do nothing (tap is starved of events).
- The menu and its toggles still work (only the tap is affected).
- A plain-key probe through the tap logs nothing (callback never fires).
- Restarting Speakeasy does not help (the block is held by another process).
- Resetting/regranting Accessibility does not help (permissions were never
  the issue).
- It "randomly comes back, then stops" (the holder toggles Secure Input on
  and off as password prompts, SSH sessions, or TUIs gain focus).

Ghostty specifically enables this via `macos-auto-secure-input`, which
defaults to `true` and uses unreliable heuristics to guess when a password
prompt is shown.

## Goals

1. Make the event tap self-healing so a transient disable cannot leave the
   hotkey permanently dead.
2. Detect Secure Input the way Espanso does and surface it in the menu bar,
   so a blocked hotkey becomes a clear, actionable message instead of a
   silent failure that looks like an app bug.
3. Remove the startup ordering fragility so granting Accessibility does not
   require a manual restart.
4. Mitigating the trigger in the local Ghostty environment is handled
   outside this repo via Ghostty configuration and is not part of the app
   work.

## Reference: how Espanso detects Secure Input

Espanso does not use the Carbon `IsSecureEventInputEnabled()` boolean.
Instead it reads the IORegistry root's `IOConsoleUsers` CF property,
iterates the console-user dictionaries, and looks for the
`kCGSSessionSecureInputPID` key. A present, non-zero value means Secure
Input is active and that integer is the holding PID. This yields both the
state and the culprit PID in a single call. Espanso then resolves the PID to
an executable path with `proc_pidpath` (buffer must be 4096 bytes) and
extracts the app name. It polls on a background thread with an adaptive
interval (3s idle, 1s while active) and edge-detects on the PID so it only
reacts on transitions. The result drives a distinct "system disabled" tray
icon plus extra context-menu items.

## The stale holder case

Secure Input is reference-counted per login session. If a process enables it
and then dies abnormally without the matching disable call, the session
counter never decrements and the holder PID is left pointing at a process
that no longer exists. This is the common real-world failure (observed here
with both a force-killed Ghostty and, ultimately, 1Password). When the holder
PID refers to a dead process, both `NSRunningApplication(processIdentifier:)`
and `proc_pidpath` fail to resolve a name. Detection must treat this as a
first-class case and report the holder as stale, advising the user that
logging out clears it, rather than presenting a misleading or empty app name.

## Stages

Stage 1: Secure Input detection module
  1a: Add `SecureInputMonitor.swift` that reads `IOConsoleUsers` from
      `IORegistryGetRootEntry(kIOMainPortDefault)` via
      `IORegistryEntryCreateCFProperty`, casts to `[[String: Any]]`, and
      returns the `kCGSSessionSecureInputPID` value (or nil if absent/zero).
  1b: Resolve the holding PID to an app display name using
      `NSRunningApplication(processIdentifier:)?.localizedName`, falling back
      to `proc_pidpath` (4096-byte buffer) and a bundle-name parse.
  1c: Poll with a `DispatchSourceTimer` on a background queue using adaptive
      cadence (3s idle, 1s while active) and edge-detection on the PID;
      expose a delegate/closure that fires `secureInputDidEngage(app:)` and
      `secureInputDidDisengage()` on the main queue.

Stage 2: Event tap self-healing
  2a: Handle `.tapDisabledByTimeout` and `.tapDisabledByUserInput` in
      `PushToTalkManager.handleEvent` by calling
      `CGEvent.tapEnable(tap:enable:true)` and logging at `.error`.
  2b: Add a watchdog timer that periodically checks
      `CGEvent.tapIsEnabled(tap:)` and re-enables the tap if it was disabled;
      if `eventTap` is nil, attempt to recreate it.
  2c: Reorder startup so Accessibility trust is verified before tap creation,
      and recreate the tap after permission is granted instead of requiring a
      restart; keep the existing alert as a fallback.

Stage 3: Menu bar UI surfacing
  3a: Add a distinct warning status image in `Icons.swift` (system-disabled
      style) for the blocked state.
  3b: On `secureInputDidEngage`, swap the `NSStatusItem` button image to the
      warning icon and set a tooltip naming the holding app; restore the
      normal icon on `secureInputDidDisengage`.
  3c: When Secure Input is active, insert menu items at the top of the menu:
      a disabled status line ("Hotkey blocked by Secure Input (<App>)", or a
      stale-holder variant when the PID is gone) and a "Why isn't this
      working?" item that opens a short explanation.

## Out of scope

- No attempt to programmatically clear another process's Secure Input state
  (not possible without that process cooperating). Speakeasy only detects and
  reports it; the user resolves the holder.
- No change to the underlying push-to-talk combo or transcription pipeline.
