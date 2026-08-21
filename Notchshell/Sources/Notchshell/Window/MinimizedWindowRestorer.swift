import AppKit
import ApplicationServices

/// Brings a window back from the Dock when the user switches to an app that has
/// nothing else to show.
///
/// ⌘Tab activates an app; it does not unminimize one. Switch to an app whose only
/// windows are minimized and macOS brings its menu bar forward and nothing else —
/// measured with this app quit entirely, so it is the OS's behaviour, not a side
/// effect of the panel. The OS's own answer is holding ⌥ while releasing ⌘Tab,
/// which nobody knows. When the switch happens *away from the panel*, this app is
/// the one hiding, so it is in a position to finish the switch instead.
///
/// Restores only when every standard window the app has is minimized. One visible
/// window means the activation already landed somewhere, and pulling more windows
/// out of the Dock would be doing something the user did not ask for.
///
/// Reading and flipping another app's `AXMinimized` needs the Accessibility grant.
/// Without it this is a silent no-op — except for a one-time system prompt, raised
/// the first time a restore would actually have happened, because that is the
/// moment the feature is visibly failing rather than an abstract request at launch.
enum MinimizedWindowRestorer {

    /// Holds the version that last prompted, not a boolean. TCC keys its grants on
    /// the code signature, so under an ad-hoc signature every update genuinely loses
    /// the grant — a once-ever flag would leave the feature silently dead from the
    /// second version on. Per version matches when the grant can actually be lost;
    /// under a stable Developer ID the grant survives updates, `AXIsProcessTrusted`
    /// stays true, and this is never consulted again.
    private static let promptShownKey = "minimizedRestorePromptVersion"

    /// Restore the frontmost minimized window of `app` if the app has no visible
    /// windows at all. Returns whether a window was actually restored.
    @discardableResult
    static func restoreIfAllWindowsMinimized(in app: NSRunningApplication) -> Bool {
        guard AXIsProcessTrusted() else {
            promptOnceIfRestoreWouldApply(to: app)
            return false
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &raw) == .success,
              let windows = raw as? [AXUIElement], !windows.isEmpty else { return false }

        var buried: [AXUIElement] = []
        for window in windows {
            var flag: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &flag) == .success,
                  let minimized = flag as? Bool else { continue }
            if !minimized { return false }
            buried.append(window)
        }

        // AX lists windows front to back, so the first buried one is the one the
        // user saw last.
        guard let front = buried.first else { return false }
        return AXUIElementSetAttributeValue(front, kAXMinimizedAttribute as CFString, kCFBooleanFalse) == .success
    }

    /// Raise the system Accessibility prompt, once, and only at a moment where the
    /// grant would have been used. The buried-ness check runs through CGWindowList,
    /// which needs no permission for geometry — window *names* would need Screen
    /// Recording, and are not read.
    private static func promptOnceIfRestoreWouldApply(to app: NSRunningApplication) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        guard UserDefaults.standard.string(forKey: promptShownKey) != version else { return }
        guard hasOnlyBuriedWindows(pid: app.processIdentifier) else { return }
        UserDefaults.standard.set(version, forKey: promptShownKey)
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private static func hasOnlyBuriedWindows(pid: pid_t) -> Bool {
        guard let info = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else { return false }
        let standardWindows = info.filter {
            ($0[kCGWindowOwnerPID as String] as? Int) == Int(pid)
                && ($0[kCGWindowLayer as String] as? Int) == 0
        }
        guard !standardWindows.isEmpty else { return false }
        return standardWindows.allSatisfy { ($0[kCGWindowIsOnscreen as String] as? Bool) != true }
    }
}
