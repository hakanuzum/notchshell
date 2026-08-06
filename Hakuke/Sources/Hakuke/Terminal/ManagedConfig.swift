import Foundation
import GhosttyKit
import os.log

private let configLog = OSLog(subsystem: AppIdentity.logSubsystem, category: "ManagedConfig")

/// The configuration layer this app owns.
///
///     ~/.config/notchshell/config        root; created once, yours to edit
///         config-file = ?~/.config/ghostty/config     inherited, never written
///         config-file = ~/.config/notchshell/theme.conf
///
///     ~/.config/notchshell/theme.conf    owned outright, rewritten on every apply
///
/// The point of the split is that the user's own Ghostty config is *read* and never
/// *edited*. Previously the theme picker rewrote the `theme =` line inside
/// `~/.config/ghostty/config`, which destroyed whatever the user had there and
/// fought with any other tool writing the same file.
///
/// Layering semantics were measured against libghostty rather than taken from the
/// docs (see `GhosttyConfigProbeTests`):
///
///   - A later `config-file` include overrides keys from an earlier one, so listing
///     our theme layer last is what makes it win.
///   - A `?` prefix makes a missing file non-fatal — no diagnostic, no failure.
///   - **`config-file` is only expanded by `ghostty_config_load_recursive_files`.**
///     `load_file` and `load_default_files` read a file's own keys but silently
///     ignore its includes, resolving to Ghostty's defaults instead. Every load path
///     here must run the recursive pass.
enum ManagedConfig {

    static var directory: String { AppIdentity.configDirectory }
    static var rootPath: String { directory + "/config" }
    static var themeOverridePath: String { directory + "/theme.conf" }

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

    // MARK: - Creating

    /// Create the managed files if they are missing. Never overwrites an existing
    /// root config — once it exists it belongs to the user.
    static func ensureExists() {
        let fm = FileManager.default
        try? fm.createDirectory(atPath: directory, withIntermediateDirectories: true)

        if !fm.fileExists(atPath: themeOverridePath) {
            // Carry over whatever theme the user already had so the first launch
            // after this change looks identical to the last launch before it.
            let inherited = themeLine(inFileAt: userGhosttyConfigPath)
            write(themeOverride: inherited)
            if inherited != nil {
                os_log(.info, log: configLog, "Seeded theme override from the user's Ghostty config")
            }
        }

        guard !fm.fileExists(atPath: rootPath) else { return }
        let contents = """
        # \(AppIdentity.displayName) configuration.
        #
        # Your own Ghostty config is included below and is never modified by this
        # app — edit it where it lives. Settings written from the app land in
        # theme.conf, which is included last so it wins.
        #
        # Anything you add directly to this file is overridden by those includes;
        # put personal overrides in your Ghostty config or after the include lines.

        config-file = ?\(userGhosttyConfigPath)
        config-file = \(themeOverridePath)

        """
        do {
            try contents.write(toFile: rootPath, atomically: true, encoding: .utf8)
            os_log(.info, log: configLog, "Created %{public}s", rootPath)
        } catch {
            os_log(.error, log: configLog, "Could not create %{public}s: %{public}s",
                   rootPath, error.localizedDescription)
        }
    }

    // MARK: - Theme

    /// The theme currently selected, verbatim. May be a plain name or Ghostty's
    /// `light:A,dark:B` pair — this does not interpret it.
    static func currentTheme() -> String? {
        themeLine(inFileAt: themeOverridePath)
    }

    @discardableResult
    static func setTheme(_ value: String) -> Bool {
        ensureExists()
        return write(themeOverride: value)
    }

    @discardableResult
    private static func write(themeOverride value: String?) -> Bool {
        var contents = """
        # Written by \(AppIdentity.displayName). Edits here are replaced when you
        # change settings in the app.

        """
        if let value, !value.isEmpty {
            contents += "theme = \(value)\n"
        }
        do {
            try contents.write(toFile: themeOverridePath, atomically: true, encoding: .utf8)
            return true
        } catch {
            os_log(.error, log: configLog, "Could not write %{public}s: %{public}s",
                   themeOverridePath, error.localizedDescription)
            return false
        }
    }

    /// Value of the first uncommented `theme =` line, or nil.
    private static func themeLine(inFileAt path: String) -> String? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            guard line[..<eq].trimmingCharacters(in: .whitespaces).lowercased() == "theme" else { continue }
            var value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            return value.isEmpty ? nil : String(value)
        }
        return nil
    }
}
