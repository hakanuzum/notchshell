import SwiftUI
import AppKit

/// Which way round the panel's chrome is painted.
///
/// This used to select between two different chromes — a soft light one with folder
/// tabs along the bottom, and an inherited dark one with a plain bar along the top.
/// The setting was labelled "Light / Dark / Auto", so it read as a theme while it
/// actually swapped the layout, the tab bar's edge, the corner radius and the shadow
/// all at once. Choosing Dark did not darken the panel; it replaced it.
///
/// Now there is one chrome and this picks its palette. The raw values are unchanged so
/// an existing `panelChromeStyle` preference still resolves.
enum PanelChromeStyle: String, CaseIterable, Identifiable, Codable {
    case unclutter
    case terminalDark
    case auto

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .unclutter: return "Light"
        case .terminalDark: return "Dark"
        case .auto: return "Auto"
        }
    }

    var resolved: PanelChromeStyle {
        switch self {
        case .unclutter, .terminalDark: return self
        case .auto:
            let appearance = NSApp.effectiveAppearance
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return isDark ? .terminalDark : .unclutter
        }
    }
}

enum PanelChrome {
    static func isDark(_ style: PanelChromeStyle) -> Bool {
        style.resolved == .terminalDark
    }

    static func colorScheme(style: PanelChromeStyle) -> ColorScheme {
        isDark(style) ? .dark : .light
    }

    static func contentBackground(style: PanelChromeStyle) -> Color {
        isDark(style)
            ? Color(nsColor: NSColor(calibratedWhite: 0.13, alpha: 1))
            : Color(nsColor: NSColor(calibratedWhite: 0.97, alpha: 1))
    }

    /// The hairline around the shelf. It has to read against the desktop behind it, so
    /// it darkens in dark rather than lightening — a white edge on a near-black panel
    /// draws a bright rectangle across whatever is on screen.
    static func border(style: PanelChromeStyle) -> Color {
        isDark(style) ? Color.black.opacity(0.55) : Color.black.opacity(0.10)
    }

    static func shadow(style: PanelChromeStyle) -> Color {
        isDark(style) ? Color.black.opacity(0.38) : Color.black.opacity(0.22)
    }

    /// Top-docked shelf: square all round.
    ///
    /// The bottom corners used to be rounded, which clipped the ends of the tab bar
    /// into arcs. A full-width shelf whose tab bar is the height of the menu bar reads
    /// as a second menu bar, and menu bars do not have rounded ends.
    static func clipShape(radius: CGFloat = 0) -> UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0, bottomLeadingRadius: radius,
            bottomTrailingRadius: radius, topTrailingRadius: 0
        )
    }
}
