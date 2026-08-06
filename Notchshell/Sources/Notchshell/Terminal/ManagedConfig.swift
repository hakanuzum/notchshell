import Foundation
import GhosttyKit
import os.log

private let configLog = OSLog(subsystem: AppIdentity.logSubsystem, category: "ManagedConfig")

/// The configuration layer this app owns.
///
///     ~/.config/notchshell/config          root; created once, then yours
///         config-file = ?~/.config/ghostty/config     inherited, never written
///         config-file = ~/.config/notchshell/overrides.conf
///
///     ~/.config/notchshell/overrides.conf  every setting written from the app
///
/// The point of the split is that the user's own Ghostty config is *read* and never
/// *edited*. Before this existed, the theme picker rewrote the `theme =` line inside
/// `~/.config/ghostty/config`, destroying whatever the user had there and fighting
/// any other tool writing the same file.
///
/// Layering semantics were measured against libghostty rather than taken from the
/// docs (see `GhosttyConfigProbeTests`):
///
///   - A later `config-file` include overrides keys from an earlier one, so listing
///     our overrides last is what makes them win.
///   - A `?` prefix makes a missing file non-fatal — no diagnostic, no failure.
///   - **`config-file` is only expanded by `ghostty_config_load_recursive_files`.**
///     `load_file` and `load_default_files` read a file's own keys but silently
///     ignore its includes, resolving to Ghostty's defaults instead. Every load path
///     here must run the recursive pass.
enum ManagedConfig {

    static var directory: String { AppIdentity.configDirectory }
    static var rootPath: String { directory + "/config" }

    /// Everything the app writes. Named for its contents — it started out holding
    /// only the theme, under the name `theme.conf`, and `migrateThemeOverride()`
    /// moves that aside for anyone who has one.
    static var overridesPath: String { directory + "/overrides.conf" }

    private static var legacyThemeOverridePath: String { directory + "/theme.conf" }

    /// The user's own Ghostty config. Read through an include; never written to.
    static var userGhosttyConfigPath: String { "\(AppIdentity.configHome)/ghostty/config" }

    // MARK: - Loading

    /// Load the managed config into `config`, expanding includes.
    ///
    /// Callers must use this rather than `ghostty_config_load_file` directly — the
    /// recursive pass is what makes the layering work at all.
    static func load(into config: ghostty_config_t) {
        ensureExists()
        rootPath.withCString { ghostty_config_load_file(config, $0) }
        ghostty_config_load_recursive_files(config)
    }

    // MARK: - Write guard

    /// Whether writing to `directory` is permitted right now.
    ///
    /// A test that forgets to redirect `XDG_CONFIG_HOME` writes to the developer's
    /// real configuration and appears to pass. That happened: a full test run
    /// replaced a hand-set theme in `~/.config/notchshell` and nothing reported it,
    /// because from the code's point of view the write succeeded. Under a test host,
    /// writes are refused unless the config home has been redirected.
    private static var canWrite: Bool {
        guard AppIdentity.isTestEnvironment else { return true }
        if ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"] != nil { return true }
        os_log(.error, log: configLog,
               "Refusing to write %{public}s from a test — redirect XDG_CONFIG_HOME first",
               directory)
        return false
    }

    // MARK: - Creating

    /// Create the managed files if they are missing, and bring an older layout
    /// forward. Never discards a root config the user may have edited.
    static func ensureExists() {
        guard canWrite else { return }
        let fm = FileManager.default
        try? fm.createDirectory(atPath: directory, withIntermediateDirectories: true)

        migrateThemeOverride()

        if !fm.fileExists(atPath: overridesPath) {
            // Carry over whatever theme the user already had so the first launch
            // after this change looks identical to the last launch before it.
            var seeded: [String: String] = [:]
            if let inherited = value(forKey: "theme", inFileAt: userGhosttyConfigPath) {
                seeded["theme"] = inherited
                os_log(.info, log: configLog, "Seeded theme from the user's Ghostty config")
            }
            write(overrides: seeded)
        }

        guard !fm.fileExists(atPath: rootPath) else { return }
        let contents = """
        # \(AppIdentity.displayName) configuration.
        #
        # Your own Ghostty config is included below and is never modified by this
        # app — edit it where it lives. Settings written from the app land in
        # overrides.conf, which is included last so it wins.
        #
        # Anything you add directly to this file is overridden by those includes;
        # put personal overrides in your Ghostty config or after the include lines.

        config-file = ?\(userGhosttyConfigPath)
        config-file = \(overridesPath)

        """
        do {
            try contents.write(toFile: rootPath, atomically: true, encoding: .utf8)
            os_log(.info, log: configLog, "Created %{public}s", rootPath)
        } catch {
            os_log(.error, log: configLog, "Could not create %{public}s: %{public}s",
                   rootPath, error.localizedDescription)
        }
    }

    /// Move a `theme.conf` from the first version of this layer to `overrides.conf`,
    /// and repoint the root config's include at it.
    private static func migrateThemeOverride() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyThemeOverridePath) else { return }
        if !fm.fileExists(atPath: overridesPath) {
            try? fm.moveItem(atPath: legacyThemeOverridePath, toPath: overridesPath)
        } else {
            try? fm.removeItem(atPath: legacyThemeOverridePath)
        }
        if let root = try? String(contentsOfFile: rootPath, encoding: .utf8),
           root.contains(legacyThemeOverridePath) {
            let repointed = root.replacingOccurrences(of: legacyThemeOverridePath, with: overridesPath)
            try? repointed.write(toFile: rootPath, atomically: true, encoding: .utf8)
        }
        os_log(.info, log: configLog, "Migrated theme.conf to overrides.conf")
    }

    // MARK: - Overrides

    /// Value of `key` in the overrides file, or nil when unset.
    static func override(_ key: String) -> String? {
        value(forKey: key, inFileAt: overridesPath)
    }

    /// Set `key`, or remove it when `value` is nil. Other keys are preserved.
    @discardableResult
    static func setOverride(_ key: String, to newValue: String?) -> Bool {
        ensureExists()
        var overrides = readOverrides()
        if let newValue, !newValue.isEmpty {
            overrides[key] = newValue
        } else {
            overrides.removeValue(forKey: key)
        }
        return write(overrides: overrides)
    }

    static func currentTheme() -> String? { override("theme") }

    @discardableResult
    static func setTheme(_ value: String) -> Bool { setOverride("theme", to: value) }

    // MARK: - File access

    private static func readOverrides() -> [String: String] {
        guard let text = try? String(contentsOfFile: overridesPath, encoding: .utf8) else { return [:] }
        var result: [String: String] = [:]
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, !value.isEmpty else { continue }
            result[key] = unquoted(value)
        }
        return result
    }

    @discardableResult
    private static func write(overrides: [String: String]) -> Bool {
        guard canWrite else { return false }
        var contents = """
        # Written by \(AppIdentity.displayName). Edits here are replaced when you
        # change settings in the app.

        """
        for key in overrides.keys.sorted() {
            contents += "\(key) = \(overrides[key]!)\n"
        }
        do {
            try contents.write(toFile: overridesPath, atomically: true, encoding: .utf8)
            return true
        } catch {
            os_log(.error, log: configLog, "Could not write %{public}s: %{public}s",
                   overridesPath, error.localizedDescription)
            return false
        }
    }

    /// Value of the first uncommented `key =` line in a file, or nil.
    private static func value(forKey key: String, inFileAt path: String) -> String? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            guard line[..<eq].trimmingCharacters(in: .whitespaces).lowercased() == key else { continue }
            let value = unquoted(line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces))
            return value.isEmpty ? nil : value
        }
        return nil
    }

    private static func unquoted(_ value: String) -> String {
        guard value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 else { return value }
        return String(value.dropFirst().dropLast())
    }
}
