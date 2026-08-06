import Foundation

/// Single source of truth for who this app is.
///
/// These strings reach the bundle identifier, the config directory, the control
/// socket, log subsystems and every user-facing label. They used to be written out
/// by hand at each site and had already drifted — `Info.plist` shipped
/// `com.hakuke.app` while `project.yml` and the Help text both claimed
/// `com.hakuke.terminal`, so the documented "reset your settings" command pointed at
/// a domain that never existed.
///
/// Anything here that is also declared in `Info.plist` must be kept in step with it;
/// `AppIdentityTests` pins them together.
enum AppIdentity {
    /// Lowercase, no spaces. The CLI command, the config directory and the socket name.
    static let slug = "notchshell"

    /// Shown to people: menu titles, alerts, window titles.
    static let displayName = "notchshell"

    /// Must equal `CFBundleIdentifier` in Info.plist.
    static let bundleID = "com.notchshell.app"

    /// `os_log` subsystem prefix.
    static let logSubsystem = "com.notchshell"

    /// Unix socket for the local JSON control API.
    static let controlSocketPath = "/tmp/\(slug).sock"

    /// Directory this app owns for its own configuration layer. Distinct from
    /// `~/.config/ghostty`, which belongs to the user and is never written to.
    static var configDirectory: String {
        NSString(string: "~/.config/\(slug)").expandingTildeInPath
    }

    /// Environment variable that opts tests into real Ghostty initialization.
    static let testGhosttyEnvVar = "NOTCHSHELL_TEST_GHOSTTY"

    /// Scratch paths used by the `--debug-window` harness.
    static func debugScratchPath(_ suffix: String) -> String { "/tmp/\(slug)-\(suffix)" }

    enum Links {
        static let repository = "https://github.com/hakanuzum/\(AppIdentity.slug)"
        static let issues = "\(repository)/issues"
        /// Same host the Sparkle appcast is served from, so there is one place to
        /// point people at until a dedicated site exists.
        static let website = repository
        static let setupGuide = "\(repository)#setup"
    }
}
