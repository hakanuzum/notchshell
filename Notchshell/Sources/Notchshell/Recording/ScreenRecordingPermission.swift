import CoreGraphics
import AppKit

/// Screen Recording, asked for at the last possible moment.
///
/// `PERMISSIONS.md` used to say this was never requested, and the reasoning behind
/// that still holds: a terminal that asks to record your screen on launch has no
/// good answer for why. Asking when the user presses record does — the request is
/// the thing they just asked for, and everything else in the app works without it.
///
/// There is no `NSUsageDescription` for this one. macOS writes the prompt itself, so
/// unlike the keys in `Info.plist` there is nothing to get wrong — but also nothing
/// to explain ourselves with, which is another reason the timing has to carry the
/// explanation.
enum ScreenRecordingPermission {

    /// Whether capture would work right now. Does **not** prompt — safe to call while
    /// drawing a button.
    static var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt if the user has never answered.
    ///
    /// Returns whether access is already usable. A first-time grant does not apply to
    /// the running process: macOS hands the app the permission at launch, so a user
    /// who grants it now is still denied until relaunch. Callers have to say so rather
    /// than leave a record button that silently does nothing.
    @discardableResult
    static func request() -> Bool { CGRequestScreenCaptureAccess() }

    /// Open the exact pane, because "System Settings → Privacy & Security → Screen
    /// Recording" is four levels deep and easy to give up on.
    static func openSystemSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!
        NSWorkspace.shared.open(url)
    }
}
