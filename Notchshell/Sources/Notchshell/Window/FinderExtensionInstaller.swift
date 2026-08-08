import Foundation
import os.log

/// Turns the Finder extension on the first time the app runs.
///
/// macOS ships app extensions switched off. The extension travels inside the bundle, so
/// an update delivers it — and then nothing happens, because it is registered but not
/// enabled, and the switch lives in System Settings under a heading nobody goes looking
/// for. A Finder button that requires a trip to System Settings before it appears is not
/// a Finder button.
///
/// Once, and not again, for the same reason the command line tool is installed once:
/// turning it off is an answer, and switching it back on at every launch would be
/// arguing with it.
enum FinderExtensionInstaller {
    private static let log = OSLog(subsystem: AppIdentity.bundleID, category: "finder-extension")
    private static let attemptedKey = "finderExtensionEnableAttempted"

    static var extensionIdentifier: String { "\(AppIdentity.bundleID).finder" }

    static func enableOnFirstLaunch() {
        guard !AppIdentity.isTestEnvironment else { return }
        guard !UserDefaults.standard.bool(forKey: attemptedKey) else { return }
        UserDefaults.standard.set(true, forKey: attemptedKey)
        enable()
    }

    /// `pluginkit -e use -i <id>` — the same command the user would otherwise be told to
    /// run. It names our own extension and touches nothing else.
    @discardableResult
    static func enable() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        process.arguments = ["-e", "use", "-i", extensionIdentifier]
        do {
            try process.run()
            process.waitUntilExit()
            let ok = process.terminationStatus == 0
            os_log(.info, log: log, "Enable %{public}@: %{public}@",
                   extensionIdentifier, ok ? "ok" : "failed")
            return ok
        } catch {
            os_log(.error, log: log, "Could not run pluginkit: %{public}@",
                   error.localizedDescription)
            return false
        }
    }
}
