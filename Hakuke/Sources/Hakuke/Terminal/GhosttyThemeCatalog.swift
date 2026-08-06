import AppKit
import Foundation
import os.log

private let themeLog = OSLog(subsystem: "com.hakuke", category: "ThemeCatalog")

/// Ghostty theme discovery + apply.
/// Only touches Ghostty config (`theme = "…"`). Does NOT rewrite starship/zsh/lsd.
enum GhosttyThemeCatalog {
    static var resourceRoots: [String] {
        var roots: [String] = []
        if let env = ProcessInfo.processInfo.environment["GHOSTTY_RESOURCES_DIR"] {
            roots.append(env)
        }
        roots += [
            "/Applications/Muxy.app/Contents/Resources/Muxy_Muxy.bundle/ghostty",
            "/Applications/Ghostty.app/Contents/Resources/ghostty",
            "/opt/homebrew/share/ghostty",
            "/usr/local/share/ghostty",
            NSString(string: "~/.config/ghostty").expandingTildeInPath,
        ]
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
        let path = GhosttyApp.shared.configPath
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") { continue }
            guard trimmed.lowercased().hasPrefix("theme") else { continue }
            guard let eq = trimmed.firstIndex(of: "=") else { continue }
            var value = trimmed[trimmed.index(after: eq)...]
                .trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            return String(value)
        }
        return nil
    }

    /// Write `theme = "Name"` to Ghostty config and ensure theme file is available.
    @discardableResult
    static func applyTheme(named name: String) -> Bool {
        guard let source = url(forTheme: name) else {
            os_log(.error, log: themeLog, "Theme not found: %{public}s", name)
            return false
        }

        let fm = FileManager.default
        let userThemes = URL(fileURLWithPath: NSString(string: "~/.config/ghostty/themes").expandingTildeInPath)
        let configPath = GhosttyApp.shared.configPath
        let userConfig = URL(fileURLWithPath: configPath)

        try? fm.createDirectory(at: userThemes, withIntermediateDirectories: true)
        try? fm.createDirectory(at: userConfig.deletingLastPathComponent(), withIntermediateDirectories: true)

        let dest = userThemes.appendingPathComponent(name)
        if source.standardizedFileURL != dest.standardizedFileURL {
            try? fm.removeItem(at: dest)
            try? fm.copyItem(at: source, to: dest)
        }

        let escaped = name
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let themeLine = "theme = \"\(escaped)\""

        var text = (try? String(contentsOf: userConfig, encoding: .utf8)) ?? "# Ghostty config\n"
        var lines = text.components(separatedBy: .newlines)
        var replaced = false
        for i in lines.indices {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") { continue }
            if trimmed.lowercased().hasPrefix("theme=") || trimmed.lowercased().hasPrefix("theme =") {
                lines[i] = themeLine
                replaced = true
                break
            }
        }
        if !replaced {
            if !text.isEmpty && !text.hasSuffix("\n") { lines.append("") }
            lines.append(themeLine)
            lines.append("")
        }
        do {
            try lines.joined(separator: "\n").write(to: userConfig, atomically: true, encoding: .utf8)
        } catch {
            os_log(.error, log: themeLog, "Failed writing config: %{public}s", error.localizedDescription)
            return false
        }

        UserDefaults.standard.set(name, forKey: "selectedGhosttyTheme")
        os_log(.info, log: themeLog, "Set theme=%{public}s", name)
        return true
    }

    static func parseTerminalTheme(named name: String) -> TerminalTheme? {
        guard let url = url(forTheme: name),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return parseThemeText(text)
    }

    static func parseThemeText(_ text: String) -> TerminalTheme {
        var palette: [Int: NSColor] = [:]
        var background = NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1)
        var foreground = NSColor(white: 0.92, alpha: 1)
        var cursor = NSColor(red: 0.55, green: 0.78, blue: 1.0, alpha: 1)
        var selection = NSColor(white: 0.3, alpha: 0.6)

        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if line.lowercased().hasPrefix("palette") {
                if let eq = line.firstIndex(of: "=") {
                    let rhs = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
                    let comps = rhs.split(separator: "=", maxSplits: 1)
                    if comps.count == 2, let idx = Int(comps[0]) {
                        let hex = comps[1].trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                        if let c = nsColor(hex: String(hex.prefix(6))) {
                            palette[idx] = c
                        }
                    }
                }
                continue
            }

            func metaColor(_ key: String) -> NSColor? {
                guard line.lowercased().hasPrefix(key) else { return nil }
                guard let eq = line.firstIndex(of: "=") else { return nil }
                let hex = line[line.index(after: eq)...]
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
                return nsColor(hex: String(hex.prefix(6)))
            }

            if let c = metaColor("background") { background = c }
            if let c = metaColor("foreground") { foreground = c }
            if let c = metaColor("cursor-color") { cursor = c }
            if let c = metaColor("selection-background") { selection = c.withAlphaComponent(0.6) }
        }

        var ansi: [NSColor] = []
        for i in 0..<16 {
            ansi.append(palette[i] ?? TerminalTheme.default.ansiColors[i])
        }

        return TerminalTheme(
            foreground: foreground,
            background: background,
            cursor: cursor,
            selectionBackground: selection,
            ansiColors: ansi,
            fontName: TerminalTheme.default.fontName,
            fontSize: TerminalTheme.default.fontSize,
            backgroundOpacity: 0.97
        )
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
