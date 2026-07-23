import Testing
import AppKit
@testable import Hakuke

@Suite(.serialized)
struct TerminalThemeTests {

    // MARK: - Default theme values

    @Test func defaultTheme_fontSize() {
        let theme = TerminalTheme.default
        #expect(theme.fontSize == 13)
    }

    @Test func defaultTheme_fontName() {
        let theme = TerminalTheme.default
        #expect(theme.fontName == "SF Mono")
    }

    @Test func defaultTheme_backgroundOpacity() {
        let theme = TerminalTheme.default
        #expect(theme.backgroundOpacity == 0.95)
    }

    @Test func defaultTheme_has16AnsiColors() {
        let theme = TerminalTheme.default
        #expect(theme.ansiColors.count == 16)
    }

    @Test func defaultTheme_foregroundColor_isLight() {
        let theme = TerminalTheme.default
        // Foreground is NSColor(white: 0.92, alpha: 1) — should be a light gray
        let fg = theme.foreground
        var white: CGFloat = 0
        var alpha: CGFloat = 0
        fg.usingColorSpace(.genericGray)?.getWhite(&white, alpha: &alpha)
        // The white component should be close to 0.92
        #expect(white > 0.8)
        #expect(alpha == 1.0)
    }

    @Test func defaultTheme_backgroundColor_isDark() {
        let theme = TerminalTheme.default
        let bg = theme.background
        // Background is NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1) — very dark
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        bg.usingColorSpace(.genericRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(r < 0.2)
        #expect(g < 0.2)
        #expect(b < 0.2)
        #expect(a == 1.0)
    }

    @Test func defaultTheme_cursorColor_isBluish() {
        let theme = TerminalTheme.default
        let cursor = theme.cursor
        // Cursor is NSColor(red: 0.55, green: 0.78, blue: 1.0, alpha: 1) — bluish
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        cursor.usingColorSpace(.genericRGB)?.getRed(&r, green: &g, blue: &b, alpha: &a)
        #expect(b > r) // blue > red
        #expect(b > g) // blue > green
    }

    @Test func defaultTheme_selectionBackground_isSemitransparent() {
        let theme = TerminalTheme.default
        // selectionBackground is NSColor(white: 0.3, alpha: 0.6)
        let sel = theme.selectionBackground
        var white: CGFloat = 0, alpha: CGFloat = 0
        sel.usingColorSpace(.genericGray)?.getWhite(&white, alpha: &alpha)
        #expect(alpha < 1.0) // semi-transparent
    }

    // MARK: - Font resolution

    @Test func defaultTheme_font_returnsMonospacedFont() {
        let theme = TerminalTheme.default
        let font = theme.font
        // Should have the right size
        #expect(font.pointSize == 13)
        // It's either "SF Mono" or the fallback monospacedSystemFont — both are valid
        #expect(font.isFixedPitch)
    }

    @Test func theme_fontFallback_whenInvalidFontName() {
        var theme = TerminalTheme.default
        theme.fontName = "NonExistentFont12345"
        theme.fontSize = 15
        let font = theme.font
        // Should fall back to monospacedSystemFont with the requested size
        #expect(font.pointSize == 15)
        #expect(font.isFixedPitch)
    }

    @Test func theme_fontWithCustomSize() {
        var theme = TerminalTheme.default
        theme.fontSize = 20
        let font = theme.font
        #expect(font.pointSize == 20)
    }
}
