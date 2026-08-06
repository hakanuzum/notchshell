import Testing
@testable import Notchshell

/// Parsing the `theme` config value. The awkward cases are real: the bundled catalog
/// contains `Dark+`, `Darkermatrix`, `Darkmatrix` and `Darkside`, and theme names
/// routinely contain spaces.
@Suite(.serialized)
struct ThemeSelectionTests {

    // MARK: - Single themes

    @Test func plainName_isSingle() {
        #expect(ThemeSelection(configValue: "Catppuccin Mocha") == .single("Catppuccin Mocha"))
    }

    @Test func surroundingWhitespace_isTrimmed() {
        #expect(ThemeSelection(configValue: "  Tokyo Night  ") == .single("Tokyo Night"))
    }

    @Test func emptyValue_isNil() {
        #expect(ThemeSelection(configValue: "") == nil)
        #expect(ThemeSelection(configValue: "   ") == nil)
    }

    /// A name that merely begins with "dark" is not a pair.
    @Test func themeNamesBeginningWithDark_areNotPairs() {
        for name in ["Dark+", "Darkermatrix", "Darkmatrix", "Darkside"] {
            #expect(ThemeSelection(configValue: name) == .single(name), "mangled \(name)")
        }
    }

    // MARK: - Pairs

    @Test func pair_parses() {
        #expect(ThemeSelection(configValue: "light:Catppuccin Latte,dark:Catppuccin Mocha")
                == .pair(light: "Catppuccin Latte", dark: "Catppuccin Mocha"))
    }

    @Test func pair_orderDoesNotMatter() {
        #expect(ThemeSelection(configValue: "dark:Tokyo Night,light:Tokyo Night Day")
                == .pair(light: "Tokyo Night Day", dark: "Tokyo Night"))
    }

    @Test func pair_toleratesWhitespaceAndCase() {
        #expect(ThemeSelection(configValue: " LIGHT : Latte , Dark : Mocha ")
                == .pair(light: "Latte", dark: "Mocha"))
    }

    @Test func pair_withDarkPrefixedNames() {
        #expect(ThemeSelection(configValue: "light:Dark+,dark:Darkside")
                == .pair(light: "Dark+", dark: "Darkside"))
    }

    // MARK: - Incomplete or unexpected values pass through untouched

    /// Half a pair is not a pair. Passing the raw value through means an unfamiliar
    /// value reaches Ghostty as the user wrote it instead of being silently rewritten.
    @Test func halfAPair_staysSingle() {
        #expect(ThemeSelection(configValue: "light:Latte") == .single("light:Latte"))
        #expect(ThemeSelection(configValue: "dark:Mocha") == .single("dark:Mocha"))
    }

    @Test func unknownLabel_staysSingle() {
        let value = "light:Latte,dark:Mocha,dim:Something"
        #expect(ThemeSelection(configValue: value) == .single(value))
    }

    // MARK: - Round trip

    @Test func configValue_roundTrips() {
        for value in ["Catppuccin Mocha", "light:Latte,dark:Mocha", "Dark+"] {
            let parsed = ThemeSelection(configValue: value)
            #expect(ThemeSelection(configValue: parsed!.configValue) == parsed)
        }
    }

    @Test func pair_serialisesInGhosttySyntax() {
        #expect(ThemeSelection.pair(light: "Latte", dark: "Mocha").configValue
                == "light:Latte,dark:Mocha")
    }

    // MARK: - Resolution

    @Test func pair_resolvesByAppearance() {
        let selection = ThemeSelection.pair(light: "Latte", dark: "Mocha")
        #expect(selection.theme(forDarkAppearance: true) == "Mocha")
        #expect(selection.theme(forDarkAppearance: false) == "Latte")
        #expect(selection.followsSystemAppearance)
    }

    @Test func single_resolvesToItselfEitherWay() {
        let selection = ThemeSelection.single("Mocha")
        #expect(selection.theme(forDarkAppearance: true) == "Mocha")
        #expect(selection.theme(forDarkAppearance: false) == "Mocha")
        #expect(!selection.followsSystemAppearance)
        // Seeding the settings pickers from a single theme shows it on both sides.
        #expect(selection.lightTheme == "Mocha")
        #expect(selection.darkTheme == "Mocha")
    }
}
