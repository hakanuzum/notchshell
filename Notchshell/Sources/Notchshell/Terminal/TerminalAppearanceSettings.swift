import AppKit

/// The Ghostty settings the app exposes in its own UI.
///
/// Each case is a real Ghostty config key. Writing a key Ghostty does not recognise
/// fails quietly — the config still loads, the setting just does nothing — so
/// `ManagedConfigTests` loads every key here through libghostty and checks it comes
/// back with no diagnostics.
enum TerminalSetting: String, CaseIterable {
    case fontFamily = "font-family"
    case fontSize = "font-size"
    case backgroundOpacity = "background-opacity"
    case backgroundBlurRadius = "background-blur-radius"
    case cursorStyle = "cursor-style"
    case scrollbackLimit = "scrollback-limit"

    /// A value that is valid for this key, used to prove Ghostty accepts it.
    var probeValue: String {
        switch self {
        case .fontFamily:           return "Menlo"
        case .fontSize:             return "13"
        case .backgroundOpacity:    return "0.95"
        case .backgroundBlurRadius: return "20"
        case .cursorStyle:          return "block"
        case .scrollbackLimit:      return "10000000"
        }
    }
}

/// Typed reads and writes for the settings above, over `ManagedConfig`.
///
/// Values are deliberately not cached: the file is the source of truth, so editing it
/// by hand and reopening Settings shows what is actually in effect.
enum TerminalAppearanceSettings {

    static let cursorStyles = ["block", "bar", "underline"]

    /// Monospaced font families, for the font picker. Anything else makes a terminal
    /// unusable, so proportional faces are not offered.
    static var monospacedFontFamilies: [String] {
        let manager = NSFontManager.shared
        let families = manager.availableFontFamilies.filter { family in
            guard let members = manager.availableMembers(ofFontFamily: family) else { return false }
            return members.contains { member in
                guard member.count > 3, let traits = member[3] as? NSNumber else { return false }
                return NSFontTraitMask(rawValue: traits.uintValue).contains(.fixedPitchFontMask)
            }
        }
        return families.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    static func string(_ setting: TerminalSetting) -> String? {
        ManagedConfig.override(setting.rawValue)
    }

    static func double(_ setting: TerminalSetting) -> Double? {
        ManagedConfig.override(setting.rawValue).flatMap(Double.init)
    }

    static func int(_ setting: TerminalSetting) -> Int? {
        ManagedConfig.override(setting.rawValue).flatMap(Int.init)
    }

    /// Write a value, or clear the key when nil so Ghostty's own default applies again.
    @discardableResult
    static func set(_ setting: TerminalSetting, to value: String?) -> Bool {
        ManagedConfig.setOverride(setting.rawValue, to: value)
    }

    @discardableResult
    static func set(_ setting: TerminalSetting, to value: Double) -> Bool {
        // Trim a trailing ".0" so the file reads like something a person wrote.
        let text = value == value.rounded() && abs(value) < 1e9
            ? String(Int(value.rounded()))
            : String(format: "%.2f", value)
        return set(setting, to: text)
    }
}
