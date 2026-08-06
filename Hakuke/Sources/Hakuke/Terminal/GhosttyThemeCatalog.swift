import AppKit
import Foundation
import GhosttyKit
import os.log

private let themeLog = OSLog(subsystem: AppIdentity.logSubsystem, category: "ThemeCatalog")

/// Ghostty theme discovery + apply.
/// Only touches Ghostty config (`theme = "…"`). Does NOT rewrite starship/zsh/lsd.
enum GhosttyThemeCatalog {
    /// Ghostty resources directory shipped inside the app bundle.
    ///
    /// Hakuke vendors its own catalog (see `vendor/themes`) so a clean install has
    /// themes without Ghostty.app, Homebrew or any other terminal being present.
    static var bundledResourcesRoot: String? {
        guard let root = Bundle.main.resourceURL?
            .appendingPathComponent("ghostty", isDirectory: true) else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue else { return nil }
        return root.path
    }

    /// Search order, most specific first — `url(forTheme:)` takes the first match, so
    /// a theme the user dropped in `~/.config/ghostty/themes` shadows the bundled one
    /// of the same name.
    static var resourceRoots: [String] {
        var roots: [String] = []
        if let env = ProcessInfo.processInfo.environment["GHOSTTY_RESOURCES_DIR"] {
            roots.append(env)
        }
        roots.append("\(AppIdentity.configHome)/ghostty")
        if let bundled = bundledResourcesRoot {
            roots.append(bundled)
        }
        return roots
    }

    static var themeDirectories: [URL] {
        resourceRoots.compactMap { root in
            let themes = URL(fileURLWithPath: root).appendingPathComponent("themes")
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: themes.path, isDirectory: &isDir),
                  isDir.boolValue else { return nil }
            return themes
        }
    }

    static func availableThemes() -> [String] {
        var names = Set<String>()
        let fm = FileManager.default
        for dir in themeDirectories {
            guard let items = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in items where !name.hasPrefix(".") {
                names.insert(name)
            }
        }
        return names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func url(forTheme name: String) -> URL? {
        for dir in themeDirectories {
            let candidate = dir.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    static func currentThemeName() -> String? {
        ManagedConfig.currentTheme()
    }

    /// Select a theme by writing it to the config layer this app owns.
    ///
    /// This used to rewrite the `theme =` line inside `~/.config/ghostty/config` and
    /// copy the theme file into `~/.config/ghostty/themes`, i.e. it edited two things
    /// belonging to the user. Now it writes one file we own, and the theme is read
    /// from wherever `url(forTheme:)` found it — no copying.
    @discardableResult
    static func applyTheme(named name: String) -> Bool {
        guard url(forTheme: name) != nil else {
            os_log(.error, log: themeLog, "Theme not found: %{public}s", name)
            return false
        }
        guard ManagedConfig.setTheme(name) else { return false }
        UserDefaults.standard.set(name, forKey: "selectedGhosttyTheme")
        os_log(.info, log: themeLog, "Set theme=%{public}s", name)
        return true
    }

    // MARK: - Reading theme colors

    /// Colors for a named theme, resolved by libghostty rather than re-parsed here.
    ///
    /// Returns nil when the theme is missing or malformed. Callers must surface that
    /// instead of substituting a stand-in palette — a stand-in paints confidently
    /// wrong colors, which is harder to notice than no colors at all.
    static func parseTerminalTheme(named name: String) -> TerminalTheme? {
        guard let url = url(forTheme: name) else {
            os_log(.error, log: themeLog, "Theme not found: %{public}s", name)
            return nil
        }
        return terminalTheme(atPath: url.path)
    }

    /// Load a theme file into a throwaway Ghostty config and read the resolved colors.
    ///
    /// `ghostty_config_get` only answers Ghostty's non-optional color fields. Measured
    /// against libghostty: `palette` resolves to all 256 entries (Ghostty generates
    /// 16–255 itself), and `background`/`foreground` resolve too, falling back to
    /// Ghostty's own defaults when a theme omits them. `cursor-color`, `cursor-text`
    /// and `selection-*` are `?Color` in Ghostty's config and are always declined, so
    /// those come from `optionalColors(inThemeAt:)` below.
    ///
    /// Requires `ghostty_init` to have run (`GhosttyApp.initialize()` does it).
    static func terminalTheme(atPath path: String) -> TerminalTheme? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        guard let config = ghostty_config_new() else {
            os_log(.error, log: themeLog, "ghostty_config_new failed reading %{public}s", path)
            return nil
        }
        defer { ghostty_config_free(config) }

        path.withCString { ghostty_config_load_file(config, $0) }
        ghostty_config_finalize(config)

        let diagnostics = ghostty_config_diagnostics_count(config)
        if diagnostics > 0 {
            for i in 0..<diagnostics {
                if let message = ghostty_config_get_diagnostic(config, i).message {
                    os_log(.error, log: themeLog, "theme %{public}s: %{public}s",
                           path, String(cString: message))
                }
            }
            return nil
        }

        guard let rawPalette = configValue(config, "palette", as: ghostty_config_palette_s.self),
              let rawBackground = configValue(config, "background", as: ghostty_config_color_s.self),
              let rawForeground = configValue(config, "foreground", as: ghostty_config_color_s.self)
        else { return nil }

        let ansi = withUnsafeBytes(of: rawPalette.colors) { raw in
            raw.bindMemory(to: ghostty_config_color_s.self).prefix(16).map(nsColor(_:))
        }
        let foreground = nsColor(rawForeground)
        let optional = optionalColors(inThemeAt: path)

        return TerminalTheme(
            foreground: foreground,
            background: nsColor(rawBackground),
            cursor: optional.cursor ?? foreground,
            selectionBackground: (optional.selection ?? foreground).withAlphaComponent(0.6),
            ansiColors: Array(ansi),
            fontName: TerminalTheme.default.fontName,
            fontSize: TerminalTheme.default.fontSize,
            backgroundOpacity: 0.97
        )
    }

    /// Read the two optional colors libghostty won't hand back. Absent keys stay nil so
    /// the caller can derive them from the foreground rather than invent a color.
    private static func optionalColors(inThemeAt path: String) -> (cursor: NSColor?, selection: NSColor?) {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return (nil, nil) }
        var cursor: NSColor?
        var selection: NSColor?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("#"), let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
            let hex = line[line.index(after: eq)...]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            switch key {
            case "cursor-color":         cursor = nsColor(hex: String(hex.prefix(6)))
            case "selection-background": selection = nsColor(hex: String(hex.prefix(6)))
            default:                     break
            }
        }
        return (cursor, selection)
    }

    /// Read a config key into `T`. Nil when Ghostty declines the key.
    private static func configValue<T>(_ config: ghostty_config_t, _ key: String, as: T.Type) -> T? {
        let out = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { out.deallocate() }
        let answered = key.withCString { keyPtr in
            ghostty_config_get(config, out, keyPtr, UInt(strlen(keyPtr)))
        }
        return answered ? out.pointee : nil
    }

    private static func nsColor(_ c: ghostty_config_color_s) -> NSColor {
        NSColor(red: CGFloat(c.r) / 255, green: CGFloat(c.g) / 255, blue: CGFloat(c.b) / 255, alpha: 1)
    }

    /// Preview swatches: [bg, fg, ansi accents…]
    static func swatchColors(for name: String) -> [Color] {
        guard let theme = parseTerminalTheme(named: name) else {
            return Array(repeating: Color.gray, count: 10)
        }
        var colors: [Color] = [
            Color(nsColor: theme.background),
            Color(nsColor: theme.foreground),
        ]
        for i in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14] {
            if i < theme.ansiColors.count {
                colors.append(Color(nsColor: theme.ansiColors[i]))
            }
        }
        return colors
    }

    private static func nsColor(hex: String) -> NSColor? {
        guard hex.count == 6, let v = UInt32(hex, radix: 16) else { return nil }
        let r = CGFloat((v >> 16) & 0xff) / 255
        let g = CGFloat((v >> 8) & 0xff) / 255
        let b = CGFloat(v & 0xff) / 255
        return NSColor(red: r, green: g, blue: b, alpha: 1)
    }
}

import SwiftUI
