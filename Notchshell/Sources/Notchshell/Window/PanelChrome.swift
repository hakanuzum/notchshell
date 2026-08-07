import SwiftUI
import AppKit

/// Soft Unclutter-like chrome vs classic dark tab bar.
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
    static func isSoftLight(_ style: PanelChromeStyle) -> Bool {
        style.resolved == .unclutter
    }

    static func colorScheme(style: PanelChromeStyle) -> ColorScheme {
        isSoftLight(style) ? .light : .dark
    }

    static func tabBarBackground(style: PanelChromeStyle) -> Color {
        if isSoftLight(style) {
            return Color(nsColor: NSColor(calibratedWhite: 0.94, alpha: 0.96))
        }
        return Color.black.opacity(0.85)
    }

    static func contentBackground(style: PanelChromeStyle) -> Color {
        if isSoftLight(style) {
            return Color(nsColor: NSColor(calibratedWhite: 0.97, alpha: 1))
        }
        return Color(nsColor: .windowBackgroundColor)
    }

    static func border(style: PanelChromeStyle) -> Color {
        isSoftLight(style) ? Color.black.opacity(0.10) : Color.white.opacity(0.15)
    }

    static func shadow(style: PanelChromeStyle) -> Color {
        isSoftLight(style) ? Color.black.opacity(0.22) : Color.black.opacity(0.35)
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
