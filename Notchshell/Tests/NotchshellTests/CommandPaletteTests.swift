import Testing
@testable import Notchshell

/// The palette's list-building, tested directly rather than read off a screenshot.
@MainActor
@Suite(.serialized)
struct CommandPaletteTests {

    private func makeActions() -> [AppAction] {
        ActionRegistry.actions(for: WindowController())
    }

    private let themes = ["Nord", "Nord Light", "Ayu Mirage", "Solarized Dark", "Gruvbox"]

    // MARK: - Matching

    @Test func matches_isCaseInsensitiveSubstring() {
        #expect(CommandPalette.matches("Nord Light", "nord"))
        #expect(CommandPalette.matches("Split Right", "SPLIT"))
        #expect(CommandPalette.matches("Close Pane or Tab", "pane"))
        #expect(!CommandPalette.matches("New Tab", "nord"))
    }

    /// Substring, not fuzzy. "nt" must not drag in "New Tab" ahead of a real match.
    @Test func matches_isNotFuzzy() {
        #expect(!CommandPalette.matches("New Tab", "nt"))
        #expect(!CommandPalette.matches("Solarized Dark", "sld"))
    }

    // MARK: - List building

    /// Opening the palette shows what the app can do, not 602 theme names.
    @Test func items_withEmptyQuery_areActionsOnly() {
        let items = CommandPalette.items(query: "", actions: makeActions(), themeNames: themes)
        #expect(!items.isEmpty)
        #expect(items.allSatisfy { if case .action = $0 { return true } else { return false } })
    }

    /// The bug this suite was written for: typing a theme name left every action on
    /// screen. An action that does not match must not survive the filter.
    @Test func items_withThemeQuery_dropNonMatchingActions() {
        let items = CommandPalette.items(query: "nord", actions: makeActions(), themeNames: themes)
        let actionTitles = items.compactMap { item -> String? in
            if case .action(let a) = item { return a.title }
            return nil
        }
        #expect(!actionTitles.contains("New Tab"))
        #expect(!actionTitles.contains("Split Right"))

        let themeNames = items.compactMap { item -> String? in
            if case .theme(let name) = item { return name }
            return nil
        }
        #expect(themeNames == ["Nord", "Nord Light"])
    }

    /// A query can match both kinds at once, and actions come first because an action
    /// is what a palette is for.
    @Test func items_listActionsBeforeThemes() {
        let items = CommandPalette.items(query: "a", actions: makeActions(),
                                         themeNames: ["Ayu Mirage"])
        let firstThemeIndex = items.firstIndex { if case .theme = $0 { return true } else { return false } }
        let lastActionIndex = items.lastIndex { if case .action = $0 { return true } else { return false } }
        if let firstThemeIndex, let lastActionIndex {
            #expect(lastActionIndex < firstThemeIndex)
        }
    }

    @Test func items_withNoMatchesAreEmpty() {
        let items = CommandPalette.items(query: "zzzznotathing",
                                         actions: makeActions(), themeNames: themes)
        #expect(items.isEmpty)
    }

    /// Trailing whitespace is what you get from typing, not a search term.
    @Test func items_ignoreSurroundingWhitespace() {
        let padded = CommandPalette.items(query: "  nord  ", actions: makeActions(),
                                          themeNames: themes)
        let plain = CommandPalette.items(query: "nord", actions: makeActions(),
                                         themeNames: themes)
        #expect(padded.map(\.id) == plain.map(\.id))
    }

    /// A long list of theme matches is capped, so the palette cannot become a wall.
    @Test func items_capTheThemeList() {
        let many = (0..<200).map { "Theme \($0)" }
        let items = CommandPalette.items(query: "Theme", actions: makeActions(), themeNames: many)
        let themeCount = items.filter { if case .theme = $0 { return true } else { return false } }.count
        #expect(themeCount == 40)
    }
}
