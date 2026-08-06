import Foundation

/// Single source of truth for who this app is.
///
/// These strings reach the bundle identifier, the config directory, the control
/// socket, log subsystems and every user-facing label. They used to be written out
/// by hand at each site and had already drifted — `Info.plist` shipped
/// one identifier while `project.yml` and the Help text both claimed
/// another, so the documented "reset your settings" command pointed at
/// a domain that never existed.
///
/// Anything here that is also declared in `Info.plist` must be kept in step with it;
/// `AppIdentityTests` pins them together.
enum AppIdentity {
    /// Lowercase, no spaces. Everything a machine reads: the CLI command, the config
    /// directory, the socket, the bundle identifier, the repository.
    static let slug = "notchshell"

    /// Everything a person reads: the app in Finder, menu titles, alerts, About.
    /// Capitalised because that is the macOS convention for an app's name — the two
    /// forms are deliberately different, so do not derive one from the other.
    static let displayName = "Notchshell"

    /// Must equal `CFBundleIdentifier` in Info.plist.
    static let bundleID = "com.notchshell.app"

    /// `os_log` subsystem prefix.
    static let logSubsystem = "com.notchshell"

    /// Unix socket for the local JSON control API.
    static let controlSocketPath = "/tmp/\(slug).sock"

    /// Base for per-user configuration, honouring `XDG_CONFIG_HOME` the way Ghostty
    /// itself does. Reading it from the environment rather than expanding `~` also
    /// makes the config paths redirectable, which is the only way tests can exercise
    /// them without writing into the developer's real dotfiles — `NSHomeDirectory()`
    /// resolves through `getpwuid` and ignores a reassigned `HOME`.
    static var configHome: String {
        if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            return xdg
        }
        return NSString(string: "~/.config").expandingTildeInPath
    }

    /// Directory this app owns for its own configuration layer. Distinct from
    /// `<configHome>/ghostty`, which belongs to the user and is never written to.
    static var configDirectory: String { "\(configHome)/\(slug)" }

    /// Environment variable that opts tests into real Ghostty initialization.
    static let testGhosttyEnvVar = "NOTCHSHELL_TEST_GHOSTTY"

    /// True when running under a test host rather than the real app.
    static var isTestEnvironment: Bool {
        let info = ProcessInfo.processInfo
        return info.environment["XCTestConfigurationFilePath"] != nil
            || info.processName.contains("xctest")
            || info.processName.contains("swiftpm-testing-helper")
    }

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
