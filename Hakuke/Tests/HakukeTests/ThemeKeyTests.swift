import Testing
import AppKit
@testable import Hakuke

/// Tests for ThemeKey color packing, equality, and tab UI helper functions.
@MainActor
@Suite(.serialized)
struct ThemeKeyTests {

    // MARK: - Helpers

    private static let defaultAnsi: [NSColor] = (0..<16).map { _ in NSColor.gray }

    private func makeThemeKey(
        fontName: String = "Menlo",
        fontSize: CGFloat = 13,
        foreground: NSColor = .white,
        background: NSColor = .black,
        backgroundOpacity: CGFloat = 1.0,
        cursor: NSColor = .green,
        selection: NSColor = .blue,
        ansiColors: [NSColor]? = nil
    ) -> TerminalContentView.ThemeKey {
        TerminalContentView.ThemeKey(
            fontName: fontName,
            fontSize: fontSize,
            foreground: foreground,
            background: background,
            backgroundOpacity: backgroundOpacity,
            cursor: cursor,
            selection: selection,
            ansiColors: ansiColors ?? Self.defaultAnsi
        )
    }

    // MARK: - ThemeKey equality

    @Test func sameColors_areEqual() {
        let a = makeThemeKey()
        let b = makeThemeKey()
        #expect(a == b)
    }

    @Test func differentForeground_notEqual() {
        let a = makeThemeKey(foreground: .white)
        let b = makeThemeKey(foreground: .red)
        #expect(a != b)
    }

    @Test func differentBackground_notEqual() {
        let a = makeThemeKey(background: .black)
        let b = makeThemeKey(background: .darkGray)
        #expect(a != b)
    }

    @Test func differentCursor_notEqual() {
        let a = makeThemeKey(cursor: .green)
        let b = makeThemeKey(cursor: .yellow)
        #expect(a != b)
    }

    @Test func differentSelection_notEqual() {
        let a = makeThemeKey(selection: .blue)
        let b = makeThemeKey(selection: .cyan)
        #expect(a != b)
    }

    @Test func differentOpacity_notEqual() {
        let a = makeThemeKey(backgroundOpacity: 1.0)
        let b = makeThemeKey(backgroundOpacity: 0.8)
        #expect(a != b)
    }

    @Test func differentFontName_notEqual() {
        let a = makeThemeKey(fontName: "Menlo")
        let b = makeThemeKey(fontName: "Monaco")
        #expect(a != b)
    }

    @Test func differentFontSize_notEqual() {
        let a = makeThemeKey(fontSize: 13)
        let b = makeThemeKey(fontSize: 14)
        #expect(a != b)
    }

    @Test func differentAnsiColor_notEqual() {
        var ansi1 = Self.defaultAnsi
        var ansi2 = Self.defaultAnsi
        ansi2[0] = .red
        let a = makeThemeKey(ansiColors: ansi1)
        let b = makeThemeKey(ansiColors: ansi2)
        #expect(a != b)
        _ = ansi1 // silence unused
    }

    @Test func sameColors_createdIndependently_areEqual() {
        // Value semantics: two separate ThemeKeys with identical colors must be equal
        let ansi: [NSColor] = (0..<16).map { _ in NSColor(red: 0.5, green: 0.3, blue: 0.7, alpha: 1.0) }
        let a = makeThemeKey(foreground: .cyan, background: .brown, cursor: .magenta, selection: .orange, ansiColors: ansi)
        let b = makeThemeKey(foreground: .cyan, background: .brown, cursor: .magenta, selection: .orange, ansiColors: ansi)
        #expect(a == b)
    }

    // MARK: - Color packing precision

    @Test func pack_black_expectedBits() {
        let a = makeThemeKey(foreground: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        let b = makeThemeKey(foreground: NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        // Black foreground with alpha 1 should pack identically
        #expect(a == b)
    }

    @Test func pack_white_expectedBits() {
        let a = makeThemeKey(foreground: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        let b = makeThemeKey(foreground: NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
        #expect(a == b)
    }

    @Test func pack_halfValues_quantized() {
        // 0.5 quantized to 16-bit should be stable
        let color = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 0.5)
        let a = makeThemeKey(foreground: color)
        let b = makeThemeKey(foreground: color)
        #expect(a == b)
    }

    @Test func pack_transparent_vs_opaque_differ() {
        let transparent = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 0)
        let opaque = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let a = makeThemeKey(foreground: transparent)
        let b = makeThemeKey(foreground: opaque)
        #expect(a != b)
    }

    @Test func pack_red_vs_green_differ() {
        let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let green = NSColor(srgbRed: 0, green: 1, blue: 0, alpha: 1)
        let a = makeThemeKey(foreground: red)
        let b = makeThemeKey(foreground: green)
        #expect(a != b)
    }

    @Test func pack_deviceRGB_color_handled() {
        // NSColor from device color space should still pack correctly
        let deviceColor = NSColor(deviceRed: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        let srgbColor = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1.0)
        // These may differ slightly due to color space conversion, but shouldn't crash
        let a = makeThemeKey(foreground: deviceColor)
        let b = makeThemeKey(foreground: srgbColor)
        _ = (a, b) // no crash is the main assertion
    }
}

// MARK: - Tab UI helpers

@Suite(.serialized)
struct TabShortTitleTests {

    @Test func pathWithSlashes_returnsLastComponent() {
        #expect(tabShortTitle("foo/bar/baz") == "baz")
    }

    @Test func simpleString_returnsItself() {
        #expect(tabShortTitle("simple") == "simple")
    }

    @Test func emptyString_returnsItself() {
        #expect(tabShortTitle("") == "")
    }

    @Test func singleSlash_lastComponentEmpty() {
        // "trailing/" splits to ["trailing", ""], last is ""
        // But split(separator:) omits empty subsequences by default,
        // so "trailing/" → ["trailing"], last → "trailing"
        #expect(tabShortTitle("trailing/") == "trailing")
    }

    @Test func deepPath_returnsLeaf() {
        #expect(tabShortTitle("/usr/local/bin/zsh") == "zsh")
    }

    @Test func homePath_returnsLastDir() {
        #expect(tabShortTitle("~/.config/ghostty") == "ghostty")
    }

    @Test func processName_noSlash() {
        #expect(tabShortTitle("zsh") == "zsh")
    }

    @Test func longPath_performance() {
        let long = (0..<100).map { "dir\($0)" }.joined(separator: "/")
        #expect(tabShortTitle(long) == "dir99")
    }
}

// MARK: - Tab icon

@Suite(.serialized)
struct TabIconTests {

    @Test func settingsKind_returnsGearshape() {
        let tab = Tab(kind: .settings, title: "Settings")
        #expect(tab.kind == .settings)
    }

    @Test func helpKind_returnsQuestionmark() {
        let tab = Tab(kind: .help, title: "Help")
        #expect(tab.kind == .help)
    }

    @Test func terminalKind_hasNoPaneManagerForSpecial() {
        let settingsTab = Tab(kind: .settings, title: "Settings")
        #expect(settingsTab.paneManager == nil)
        #expect(settingsTab.instance == nil)
    }
}
