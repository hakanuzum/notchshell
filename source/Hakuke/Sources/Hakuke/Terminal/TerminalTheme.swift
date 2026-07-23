import AppKit

private func makeColor(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> NSColor {
    NSColor(red: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: 1.0)
}

struct TerminalTheme {
    var foreground: NSColor
    var background: NSColor
    var cursor: NSColor
    var selectionBackground: NSColor
    var ansiColors: [NSColor]
    var fontName: String
    var fontSize: CGFloat
    var backgroundOpacity: CGFloat

    var font: NSFont {
        NSFont(name: fontName, size: fontSize)
            ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
    }

    static let `default`: TerminalTheme = {
        let colors: [NSColor] = [
            makeColor(0x1d, 0x1f, 0x28),
            makeColor(0xff, 0x5c, 0x57),
            makeColor(0x5a, 0xf7, 0x8e),
            makeColor(0xf3, 0xf9, 0x9d),
            makeColor(0x57, 0xba, 0xf7),
            makeColor(0xff, 0x6a, 0xc1),
            makeColor(0x9a, 0xed, 0xfe),
            makeColor(0xf1, 0xf1, 0xf0),
            makeColor(0x68, 0x6d, 0x7a),
            makeColor(0xff, 0x5c, 0x57),
            makeColor(0x5a, 0xf7, 0x8e),
            makeColor(0xf3, 0xf9, 0x9d),
            makeColor(0x57, 0xba, 0xf7),
            makeColor(0xff, 0x6a, 0xc1),
            makeColor(0x9a, 0xed, 0xfe),
            makeColor(0xf1, 0xf1, 0xf0),
        ]
        return TerminalTheme(
            foreground: NSColor(white: 0.92, alpha: 1),
            background: NSColor(red: 0.08, green: 0.08, blue: 0.10, alpha: 1),
            cursor: NSColor(red: 0.55, green: 0.78, blue: 1.0, alpha: 1),
            selectionBackground: NSColor(white: 0.3, alpha: 0.6),
            ansiColors: colors,
            fontName: "SF Mono",
            fontSize: 13,
            backgroundOpacity: 0.95
        )
    }()
}
