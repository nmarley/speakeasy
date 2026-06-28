import AppKit
import Darwin
import IOKit

// Detects macOS "Secure Input" (Secure Keyboard Entry / EnableSecureEventInput).
//
// While Secure Input is active, macOS stops delivering key events to every
// CGEventTap system-wide as an anti-keylogger measure. Speakeasy's push-to-talk
// is built entirely on a CGEventTap, so the hotkey silently dies until the
// holder releases Secure Input. This monitor surfaces that condition so the app
// can warn the user instead of appearing broken.
//
// Detection mirrors Espanso's approach: rather than the Carbon
// IsSecureEventInputEnabled() boolean, it reads the IORegistry root's
// IOConsoleUsers property and looks for kCGSSessionSecureInputPID. A present,
// non-zero value means Secure Input is active and that integer is the holding
// PID, giving both the state and the culprit in a single call.

// Identifies the process holding Secure Input.
//
// Secure Input is reference-counted per login session. If a process enables it
// and dies abnormally without the matching disable call, the holder PID is left
// pointing at a process that no longer exists. In that case neither
// NSRunningApplication nor proc_pidpath can resolve a name, and `appName` is nil
// (a "stale" holder that only a logout/restart can clear).
struct SecureInputHolder: Equatable {
    let pid: pid_t
    let appName: String?

    // True when the holder PID no longer maps to a live, resolvable process.
    var isStale: Bool { appName == nil }

    // Human-readable description for tooltips and menu items.
    var displayName: String {
        if let appName = appName {
            return appName
        }
        return "an app that has since quit (PID \(pid))"
    }
}

protocol SecureInputMonitorDelegate: AnyObject {
    // Called on the main queue when Secure Input becomes active, or when the
    // holder changes to a different process while already active.
    func secureInputDidEngage(holder: SecureInputHolder)

    // Called on the main queue when Secure Input is released.
    func secureInputDidDisengage()
}

final class SecureInputMonitor {
    weak var delegate: SecureInputMonitorDelegate?

    // Poll faster while Secure Input is active so release is detected promptly,
    // and slower while idle to stay cheap.
    private let idleInterval: TimeInterval = 3.0
    private let activeInterval: TimeInterval = 1.0

    private let queue = DispatchQueue(label: "com.glowberrylabs.speakeasy.secure-input")
    private var timer: DispatchSourceTimer?

    // Last observed holder PID, used to fire delegate callbacks only on edges
    // (off->on, on->off, or a change of holder) rather than every poll.
    private var lastPID: pid_t?

    func start() {
        queue.async { [weak self] in
            guard let self = self, self.timer == nil else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.setEventHandler { [weak self] in
                self?.poll()
            }
            self.timer = timer
            timer.schedule(deadline: .now())
            timer.resume()
            Log.general.info("Secure Input monitor started")
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.timer?.cancel()
            self?.timer = nil
        }
    }

    // Runs on `queue`. Reads current state, fires edge-triggered callbacks on
    // the main queue, then re-arms the timer at the adaptive interval.
    private func poll() {
        let pid = Self.secureInputPID()

        if let pid = pid {
            let changed = lastPID != pid
            if changed {
                let holder = Self.resolveHolder(pid: pid)
                if holder.isStale {
                    Log.general.error(
                        "Secure Input active, blocking the hotkey, held by a process that has since quit (PID \(pid, privacy: .public)); a logout or restart is needed to clear it"
                    )
                } else {
                    Log.general.error(
                        "Secure Input active, blocking the hotkey, held by '\(holder.displayName, privacy: .public)' (PID \(pid, privacy: .public))"
                    )
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.secureInputDidEngage(holder: holder)
                }
            }
            lastPID = pid
        } else {
            if lastPID != nil {
                Log.general.info("Secure Input released; hotkey should work again")
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.secureInputDidDisengage()
                }
            }
            lastPID = nil
        }

        let interval = (pid != nil) ? activeInterval : idleInterval
        timer?.schedule(deadline: .now() + interval)
    }

    // Reads the IORegistry root's IOConsoleUsers property and returns the
    // Secure Input holder PID if one is set and non-zero, otherwise nil.
    private static func secureInputPID() -> pid_t? {
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        guard root != 0 else { return nil }
        defer { IOObjectRelease(root) }

        guard
            let property = IORegistryEntryCreateCFProperty(
                root, "IOConsoleUsers" as CFString, kCFAllocatorDefault, 0
            )?.takeRetainedValue(),
            let consoleUsers = property as? [[String: Any]]
        else {
            return nil
        }

        for session in consoleUsers {
            if let pid = session["kCGSSessionSecureInputPID"] as? pid_t, pid != 0 {
                return pid
            }
        }
        return nil
    }

    // Resolves a holder PID to a display name. Tries the running-application
    // registry first, then the executable path. If neither resolves (the
    // process has quit), returns a holder with a nil name flagged as stale.
    private static func resolveHolder(pid: pid_t) -> SecureInputHolder {
        if let app = NSRunningApplication(processIdentifier: pid),
            let name = app.localizedName
        {
            return SecureInputHolder(pid: pid, appName: name)
        }

        if let name = appName(fromPath: executablePath(pid: pid)) {
            return SecureInputHolder(pid: pid, appName: name)
        }

        return SecureInputHolder(pid: pid, appName: nil)
    }

    // Returns the executable path for a PID via proc_pidpath, or nil if the
    // process is gone. The buffer must be PROC_PIDPATHINFO_MAXSIZE (4096);
    // proc_pidpath fails silently with a smaller buffer.
    private static func executablePath(pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    // Extracts a bundle display name from an executable path such as
    // "/Applications/1Password.app/Contents/MacOS/1Password" -> "1Password".
    // Falls back to the final path component for non-bundle executables.
    private static func appName(fromPath path: String?) -> String? {
        guard let path = path, !path.isEmpty else { return nil }

        let components = path.components(separatedBy: "/")
        if let bundleComponent = components.first(where: {
            $0.hasSuffix(".app") || $0.hasSuffix(".bundle")
        }) {
            return (bundleComponent as NSString).deletingPathExtension
        }

        let lastComponent = components.last ?? ""
        return lastComponent.isEmpty ? nil : lastComponent
    }
}
