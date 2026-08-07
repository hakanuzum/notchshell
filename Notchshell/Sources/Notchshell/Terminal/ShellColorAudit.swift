import AppKit

/// Reports shell configuration that pins colours to fixed values.
///
/// A colour written as a hex literal or a truecolor escape is frozen: the terminal
/// stores the exact RGB and cannot repaint it when the theme changes. A colour
/// written as an ANSI slot is looked up in the palette every time it is drawn, so it
/// follows the theme — including a live light/dark switch, because the palette
/// changes underneath text that is already on screen.
///
/// The practical consequence is that colours chosen against a dark background stay
/// put on a light one and become unreadable. This finds them and says how bad it is.
///
/// **This only reads.** Rewriting someone's shell configuration is not this app's
/// business — no terminal does it, and a wrong guess would be destructive in a file
/// the user maintains by hand. The report is the deliverable; the edit is theirs.
enum ShellColorAudit {

    struct Finding: Equatable {
        let file: String
        let line: Int
        /// The setting the colour belongs to, when the line says.
        let label: String
        let hex: String
        /// Contrast against the theme's background, per WCAG.
        let contrast: Double
    }

    struct Report {
        let findings: [Finding]
        let themeName: String
        let backgroundHex: String

        /// Colours that fall below the WCAG floor for large text. Below this, a colour
        /// is guesswork rather than legible.
        var unreadable: [Finding] { findings.filter { $0.contrast < 3.0 } }
        var scannedFiles: [String] { Array(Set(findings.map(\.file))).sorted() }
        var isClean: Bool { unreadable.isEmpty }
    }

    /// Files worth looking at. Missing ones are skipped without comment — most people
    /// have one shell, not four.
    static var candidateFiles: [String] {
        let home = NSHomeDirectory()
        let config = AppIdentity.configHome
        return [
            "\(config)/fish/config.fish",
            "\(config)/starship.toml",
            "\(home)/.zshrc",
            "\(home)/.bashrc",
            "\(home)/.bash_profile",
            "\(home)/.profile",
        ]
    }

    /// Audit against the theme in effect for a given appearance.
    ///
    /// Light is the interesting case — these colours were almost always chosen against
    /// a dark background, and a dark theme hides the problem.
    static func audit(forDarkAppearance isDark: Bool,
                      files: [String]? = nil) -> Report? {
        guard let selection = GhosttyThemeCatalog.currentSelection() else { return nil }
        let themeName = selection.theme(forDarkAppearance: isDark)
        guard let theme = GhosttyThemeCatalog.parseTerminalTheme(named: themeName) else { return nil }
        let background = theme.background

        var findings: [Finding] = []
        for path in files ?? candidateFiles {
            findings += scan(path, against: background)
        }
        return Report(findings: findings.sorted { $0.contrast < $1.contrast },
                      themeName: themeName,
                      backgroundHex: hexString(background))
    }

    // MARK: - Scanning

    static func scan(_ path: String, against background: NSColor) -> [Finding] {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
        let name = (path as NSString).lastPathComponent
        var findings: [Finding] = []

        for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let label = self.label(in: line)

            for hex in hexLiterals(in: line) + truecolorSequences(in: line) {
                guard let colour = colour(fromHex: hex) else { continue }
                findings.append(Finding(file: name,
                                        line: index + 1,
                                        label: label,
                                        hex: hex,
                                        contrast: contrastRatio(colour, background)))
            }
        }
        return findings
    }

    /// Six hex digits, with or without a `#`, that are plausibly a colour rather than
    /// part of a longer token — a git SHA or a path fragment would otherwise match.
    private static func hexLiterals(in line: String) -> [String] {
        let pattern = "(?<![0-9A-Za-z])#?([0-9a-fA-F]{6})(?![0-9A-Za-z])"
        return matches(of: pattern, in: line, group: 1)
    }

    /// `38;2;R;G;B` — a truecolor foreground, as used in LS_COLORS and EZA_COLORS.
    private static func truecolorSequences(in line: String) -> [String] {
        let pattern = "38;2;([0-9]{1,3});([0-9]{1,3});([0-9]{1,3})"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            let parts = (1...3).compactMap { index -> Int? in
                guard let r = Range(match.range(at: index), in: line) else { return nil }
                return Int(line[r])
            }
            guard parts.count == 3, parts.allSatisfy({ $0 <= 255 }) else { return nil }
            return String(format: "%02x%02x%02x", parts[0], parts[1], parts[2])
        }
    }

    /// The setting name, when the line is recognisably a setting.
    private static func label(in line: String) -> String {
        for pattern in ["(fish_(?:pager_)?color_[a-z_]+)",
                        "(LS_COLORS|EZA_COLORS|FZF_DEFAULT_OPTS)",
                        "^\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*="] {
            if let first = matches(of: pattern, in: line, group: 1).first { return first }
        }
        return ""
    }

    private static func matches(of pattern: String, in line: String, group: Int) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            guard let r = Range(match.range(at: group), in: line) else { return nil }
            return String(line[r])
        }
    }

    // MARK: - Colour

    static func colour(fromHex hex: String) -> NSColor? {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        return NSColor(red: CGFloat((value >> 16) & 0xff) / 255,
                       green: CGFloat((value >> 8) & 0xff) / 255,
                       blue: CGFloat(value & 0xff) / 255,
                       alpha: 1)
    }

    static func hexString(_ colour: NSColor) -> String {
        let c = colour.usingColorSpace(.deviceRGB) ?? colour
        return String(format: "#%02x%02x%02x",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }

    /// WCAG contrast ratio, 1:1 (identical) to 21:1 (black on white).
    static func contrastRatio(_ a: NSColor, _ b: NSColor) -> Double {
        let high = max(relativeLuminance(a), relativeLuminance(b))
        let low = min(relativeLuminance(a), relativeLuminance(b))
        return (high + 0.05) / (low + 0.05)
    }

    private static func relativeLuminance(_ colour: NSColor) -> Double {
        let c = colour.usingColorSpace(.deviceRGB) ?? colour
        func channel(_ value: CGFloat) -> Double {
            let v = Double(value)
            return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.redComponent)
             + 0.7152 * channel(c.greenComponent)
             + 0.0722 * channel(c.blueComponent)
    }
}
