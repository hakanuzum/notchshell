import Foundation
import os.log

private let cliLog = OSLog(subsystem: AppIdentity.logSubsystem, category: "CLI")

/// Puts the `notchshell` command on the user's PATH.
///
/// The command itself lives in the bundle; this only creates a symlink to it, so the
/// link keeps working across app updates and is removed by deleting the app.
enum CommandLineInstaller {

    enum Location: String, CaseIterable {
        /// Usually on PATH already, but on a stock machine it does not exist and is
        /// not writable without sudo.
        case usrLocalBin = "/usr/local/bin"
        /// Writable without privileges. Increasingly on PATH by default, but not
        /// always — the caller is told when it isn't.
        case userLocalBin = "~/.local/bin"

        var path: String { NSString(string: rawValue).expandingTildeInPath }
        var linkPath: String { path + "/" + AppIdentity.slug }
    }

    enum Result: Equatable {
        case installed(at: String, onPath: Bool)
        case alreadyInstalled(at: String)
        case failed(reason: String)
    }

    /// The command inside the app bundle, or nil if the bundle was built without it.
    static var bundledCommand: String? {
        guard let url = Bundle.main.url(forAuxiliaryExecutable: "\(AppIdentity.slug)-cli")
                ?? Bundle.main.executableURL?.deletingLastPathComponent()
                    .appendingPathComponent("\(AppIdentity.slug)-cli") else { return nil }
        return FileManager.default.isExecutableFile(atPath: url.path) ? url.path : nil
    }

    /// Where the command is currently linked from, if anywhere we manage.
    static func existingInstallation() -> String? {
        Location.allCases.first { location in
            resolvedLink(at: location.linkPath) == bundledCommand
        }?.linkPath
    }

    /// Link the command the first time the app runs, and only the first time.
    ///
    /// The command exists to save you a trip to the mouse. Making you find a button in
    /// Help before `notchshell .` works defeats the whole point of having it — nobody
    /// goes looking for a setting to enable a shortcut they have not been told about.
    ///
    /// Once, though, and not again: removing the link is itself an answer, and putting
    /// it back on the next launch would be arguing with the person who removed it.
    static func installOnFirstLaunch() {
        guard !AppIdentity.isTestEnvironment else { return }
        let key = "cliInstallAttempted"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        install()
    }

    /// Link the bundled command into the first writable location.
    @discardableResult
    static func install() -> Result {
        guard let command = bundledCommand else {
            return .failed(reason: "This build does not include the command line tool.")
        }
        if let existing = existingInstallation() {
            return .alreadyInstalled(at: existing)
        }

        var lastFailure = "No writable directory found."
        for location in Location.allCases {
            let fm = FileManager.default
            if !fm.fileExists(atPath: location.path) {
                // Only create the one under the user's own home; /usr/local/bin
                // needs privileges we deliberately do not ask for.
                guard location == .userLocalBin,
                      (try? fm.createDirectory(atPath: location.path, withIntermediateDirectories: true)) != nil
                else {
                    lastFailure = "\(location.rawValue) does not exist."
                    continue
                }
            }
            guard fm.isWritableFile(atPath: location.path) else {
                lastFailure = "\(location.rawValue) is not writable."
                continue
            }
            // Replace a stale link left by an app that has moved or been reinstalled.
            if resolvedLink(at: location.linkPath) != nil || fm.fileExists(atPath: location.linkPath) {
                try? fm.removeItem(atPath: location.linkPath)
            }
            do {
                try fm.createSymbolicLink(atPath: location.linkPath, withDestinationPath: command)
                os_log(.info, log: cliLog, "Linked %{public}s", location.linkPath)
                return .installed(at: location.linkPath, onPath: isOnPath(location.path))
            } catch {
                lastFailure = error.localizedDescription
            }
        }
        return .failed(reason: lastFailure)
    }

    // MARK: - Helpers

    private static func resolvedLink(at path: String) -> String? {
        try? FileManager.default.destinationOfSymbolicLink(atPath: path)
    }

    /// Whether a directory is on the PATH this process inherited. An app launched from
    /// Finder sees launchd's PATH, not a login shell's, so a false here means "we
    /// cannot tell", and the UI says so rather than claiming it is missing.
    static func isOnPath(_ directory: String) -> Bool {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let standardized = URL(fileURLWithPath: directory).standardizedFileURL.path
        return path.split(separator: ":").contains { entry in
            URL(fileURLWithPath: String(entry)).standardizedFileURL.path == standardized
        }
    }
}
