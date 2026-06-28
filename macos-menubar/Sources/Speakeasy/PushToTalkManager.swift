import Cocoa

// This manager handles the global key monitoring for Push-to-Talk
protocol PushToTalkManagerDelegate: AnyObject {
    func pushToTalkDidEngage(_ manager: PushToTalkManager)
    func pushToTalkDidDisengage(_ manager: PushToTalkManager)
    func pushToTalkDidCancel(_ manager: PushToTalkManager)
}

class PushToTalkManager {
    weak var delegate: PushToTalkManagerDelegate?

    // We're still using the spacebar (key code 49) for push-to-talk,
    // but now it must be combined with Command and Shift.
    private let pushToTalkKey: UInt16 = 49

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isEngaged = false
    private var isSpaceDown = false
    private var currentModifiers: NSEvent.ModifierFlags = []

    private var toggleRecordKey: Int = 17  // 17 is the keycode for 'T'
    private var isToggleRecordingActive = false

    private var cancelKey: Int = 8  // 8 is the keycode for 'C'

    // macOS can silently disable an active event tap (slow callback, or while
    // Secure Input is held by another process). A periodic watchdog re-enables
    // a disabled tap and recreates one that never came up, so the hotkey heals
    // itself instead of staying dead until the app is restarted.
    private var watchdogTimer: Timer?
    private let watchdogInterval: TimeInterval = 2.0

    // The permission alert is shown at most once so the watchdog's repeated
    // recreation attempts cannot spam the user with dialogs.
    private var hasShownPermissionAlert = false

    init() {
        // Start a CGEvent tap that intercepts key events so we can suppress unwanted space events.
        startEventTap()
        startWatchdog()
    }

    deinit {
        watchdogTimer?.invalidate()
        teardownEventTap()
    }

    // Creates the event tap and wires it into the current run loop. Safe to
    // call repeatedly: an existing tap is torn down first so the watchdog can
    // recreate a tap that failed to come up (for example, after Accessibility
    // permission is granted without restarting the app).
    @discardableResult
    private func startEventTap() -> Bool {
        teardownEventTap()

        let mask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                // Convert refcon back to our PushToTalkManager instance
                let manager = Unmanaged<PushToTalkManager>.fromOpaque(refcon!).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        guard let eventTap = eventTap else {
            Log.general.error(
                "Failed to create event tap - Accessibility permission may not be granted")
            showPermissionAlertOnce()
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        runLoopSource = source
        Log.general.info("Event tap created and enabled")
        return true
    }

    // Removes the current tap from the run loop and invalidates it, leaving the
    // manager ready to create a fresh tap.
    private func teardownEventTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        if let eventTap = eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    private func showPermissionAlertOnce() {
        guard !hasShownPermissionAlert else { return }
        hasShownPermissionAlert = true

        // Show alert to user on main thread
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Keyboard Monitoring Unavailable"
            alert.informativeText =
                "Failed to create keyboard event monitor. Please ensure Speakeasy has Accessibility permission in System Settings > Privacy & Security > Accessibility."
            alert.alertStyle = .critical
            alert.addButton(withTitle: "Open System Settings")
            alert.addButton(withTitle: "OK")

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                if let url = URL(
                    string:
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                ) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    // MARK: - Watchdog

    private func startWatchdog() {
        let timer = Timer.scheduledTimer(
            withTimeInterval: watchdogInterval, repeats: true
        ) { [weak self] _ in
            self?.checkTapHealth()
        }
        // Keep the watchdog firing during menu tracking and other run loop modes.
        RunLoop.current.add(timer, forMode: .common)
        watchdogTimer = timer
    }

    // Re-enables a tap that macOS disabled, or recreates one that never came
    // up. Note this cannot recover from Secure Input being held by another
    // process: the tap stays enabled but receives no events until the holder
    // releases it. That case is surfaced separately by SecureInputMonitor.
    private func checkTapHealth() {
        guard let eventTap = eventTap else {
            Log.general.error("Event tap missing; attempting to recreate")
            startEventTap()
            return
        }

        if !CGEvent.tapIsEnabled(tap: eventTap) {
            Log.general.error("Event tap was disabled by the system; re-enabling")
            CGEvent.tapEnable(tap: eventTap, enable: true)

            // If re-enabling did not take, rebuild the tap from scratch.
            if !CGEvent.tapIsEnabled(tap: eventTap) {
                Log.general.error("Re-enable failed; recreating event tap")
                startEventTap()
            }
        }
    }

    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent)
        -> Unmanaged<CGEvent>?
    {
        // Ignore synthetic events generated by ClipboardManager's Cmd+V
        // simulation to prevent modifier tracking confusion.
        if ClipboardManager.isPasting {
            return Unmanaged.passRetained(event)
        }

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS disabled the tap (a slow callback, or user-input timeout).
            // Re-enable immediately so the hotkey does not silently die; the
            // watchdog is a slower backstop for this same condition.
            Log.general.error(
                "Event tap disabled by system (type: \(type.rawValue, privacy: .public)); re-enabling"
            )
            if let eventTap = eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passRetained(event)
        case .keyDown:
            if event.getIntegerValueField(.keyboardEventKeycode) == Int64(pushToTalkKey) {
                isSpaceDown = true
                updatePushToTalkState()
                // Suppress the space event if our combo is active
                if isEngaged { return nil }
            } else if event.getIntegerValueField(.keyboardEventKeycode) == Int64(toggleRecordKey) {
                // Check if Command+Shift+T was pressed
                if currentModifiers.contains(.command) && currentModifiers.contains(.shift) {
                    // Toggle recording state
                    isToggleRecordingActive = !isToggleRecordingActive
                    updateToggleRecordingState()
                    return nil  // Consume the event
                }
            } else if event.getIntegerValueField(.keyboardEventKeycode) == Int64(cancelKey) {
                // Check if Command+Shift+C was pressed
                Log.general.debug(
                    "Cancel key (C) detected - keycode: \(event.getIntegerValueField(.keyboardEventKeycode), privacy: .public), modifiers: \(self.currentModifiers.rawValue, privacy: .public)"
                )
                if currentModifiers.contains(.command) && currentModifiers.contains(.shift) {
                    // Cancel current operation
                    Log.general.debug("Cancel hotkey activated (Cmd+Shift+C)")
                    DispatchQueue.main.async {
                        self.delegate?.pushToTalkDidCancel(self)
                    }
                    return nil  // Consume the event
                } else {
                    Log.general.debug("Cancel key pressed but wrong modifiers - need Cmd+Shift")
                }
            }
        case .keyUp:
            if event.getIntegerValueField(.keyboardEventKeycode) == Int64(pushToTalkKey) {
                isSpaceDown = false
                updatePushToTalkState()
                if isEngaged && !isToggleRecordingActive { return nil }
            }
        case .flagsChanged:
            // Convert CGEventFlags to NSEvent.ModifierFlags, converting UInt64 to UInt
            currentModifiers = NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue))
            updatePushToTalkState()
        default:
            break
        }
        return Unmanaged.passRetained(event)
    }

    private func updatePushToTalkState() {
        let startTime = Date()

        // Check if the full combination is active:
        // Space is held down AND Command AND Shift appear in the currentModifiers.
        let combinationActive =
            isSpaceDown && currentModifiers.contains(.command) && currentModifiers.contains(.shift)

        if (combinationActive || isToggleRecordingActive) && !isEngaged {
            isEngaged = true
            Log.general.info(
                "Push-to-Talk Engaged after \(Date().timeIntervalSince(startTime), privacy: .public) seconds"
            )
            DispatchQueue.main.async {
                self.delegate?.pushToTalkDidEngage(self)
            }
        } else if !combinationActive && !isToggleRecordingActive && isEngaged {
            isEngaged = false
            Log.general.info(
                "Push-to-Talk Disengaged after \(Date().timeIntervalSince(startTime), privacy: .public) seconds"
            )
            DispatchQueue.main.async {
                self.delegate?.pushToTalkDidDisengage(self)
            }
        }
    }

    private func updateToggleRecordingState() {
        let startTime = Date()

        if isToggleRecordingActive && !isEngaged {
            isEngaged = true
            Log.general.info(
                "Toggle Recording Engaged after \(Date().timeIntervalSince(startTime), privacy: .public) seconds"
            )
            DispatchQueue.main.async {
                self.delegate?.pushToTalkDidEngage(self)
            }
        } else if !isToggleRecordingActive && isEngaged && !isSpaceDown {
            isEngaged = false
            Log.general.info(
                "Toggle Recording Disengaged after \(Date().timeIntervalSince(startTime), privacy: .public) seconds"
            )
            DispatchQueue.main.async {
                self.delegate?.pushToTalkDidDisengage(self)
            }
        }
    }

    // Method to reset toggle state when cancellation occurs
    func resetToggleState() {
        isToggleRecordingActive = false
        isEngaged = false
        Log.general.debug("Reset toggle recording state after cancellation")
    }
}
