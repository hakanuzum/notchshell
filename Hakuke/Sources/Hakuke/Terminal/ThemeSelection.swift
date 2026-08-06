import AppKit

/// What the `theme` config key holds: one theme, or a light/dark pair that Ghostty
/// switches between as the system appearance changes.
///
/// Ghostty's pair syntax is `light:Some Theme,dark:Other Theme` — whitespace around
/// the parts is trimmed and the order does not matter. Parsing is deliberately strict
/// about the prefixes: the catalog contains themes called `Dark+`, `Darkermatrix` and
/// `Darkside`, and a looser reading of "starts with dark" would mangle them.
enum ThemeSelection: Equatable {
    case single(String)
    case pair(light: String, dark: String)

    /// Parse a raw `theme =` value. Nil for an empty value.
    init?(configValue raw: String) {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }

        var light: String?
        var dark: String?
        var sawUnlabelled = false

        for part in value.split(separator: ",", omittingEmptySubsequences: true) {
            let segment = part.trimmingCharacters(in: .whitespaces)
            guard let colon = segment.firstIndex(of: ":") else {
                sawUnlabelled = true
                continue
            }
            let label = segment[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let name = segment[segment.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { continue }
            switch label {
            case "light": light = name
            case "dark":  dark = name
            default:      sawUnlabelled = true
            }
        }

        // Only a complete, unambiguous pair counts as a pair. Anything else — a lone
        // `light:`, a stray unlabelled segment — is treated as a plain name so an
        // unexpected value is passed through to Ghostty rather than silently rewritten.
        if let light, let dark, !sawUnlabelled {
            self = .pair(light: light, dark: dark)
        } else {
            self = .single(value)
        }
    }

    /// The value to write back to the config file.
    var configValue: String {
        switch self {
        case .single(let name):
            return name
        case .pair(let light, let dark):
            return "light:\(light),dark:\(dark)"
        }
    }

    /// The theme that applies under a given appearance.
    func theme(forDarkAppearance isDark: Bool) -> String {
        switch self {
        case .single(let name):              return name
        case .pair(let light, let dark):     return isDark ? dark : light
        }
    }

    var lightTheme: String {
        switch self {
        case .single(let name):          return name
        case .pair(let light, _):        return light
        }
    }

    var darkTheme: String {
        switch self {
        case .single(let name):          return name
        case .pair(_, let dark):         return dark
        }
    }

    var followsSystemAppearance: Bool {
        if case .pair = self { return true }
        return false
    }
}
