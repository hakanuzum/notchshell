import AppKit
import SwiftUI
import os.log

/// NSViewRepresentable wrapping a TerminalBackend's NSView.
struct TerminalContentView: NSViewRepresentable {
    let backend: TerminalBackend
    var theme: TerminalTheme

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        applyTheme(context: context)
        return backend.view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        applyTheme(context: context)
    }

    private func applyTheme(context: Context) {
        let key = ThemeKey(
            fontName: theme.fontName, fontSize: theme.fontSize,
            foreground: theme.foreground, background: theme.background,
            backgroundOpacity: theme.backgroundOpacity,
            cursor: theme.cursor, selection: theme.selectionBackground,
            ansiColors: theme.ansiColors
        )
        guard key != context.coordinator.lastTheme else { return }
        context.coordinator.lastTheme = key

        backend.applyFont(theme.font)
        backend.applyColors(
            foreground: theme.foreground,
            background: theme.background.withAlphaComponent(theme.backgroundOpacity),
            cursor: theme.cursor,
            selection: theme.selectionBackground,
            ansiColors: theme.ansiColors
        )
    }

    final class Coordinator {
        var lastTheme: ThemeKey?
    }

    /// Compare by RGBA values instead of NSColor references for reliable caching.
    struct ThemeKey: Equatable {
        let fontName: String
        let fontSize: CGFloat
        let backgroundOpacity: CGFloat
        private let colorData: [UInt64]  // Packed RGBA for all colors

        init(fontName: String, fontSize: CGFloat,
             foreground: NSColor, background: NSColor,
             backgroundOpacity: CGFloat,
             cursor: NSColor, selection: NSColor,
             ansiColors: [NSColor]) {
            self.fontName = fontName
            self.fontSize = fontSize
            self.backgroundOpacity = backgroundOpacity
            var packed: [UInt64] = []
            packed.reserveCapacity(4 + ansiColors.count)
            for c in [foreground, background, cursor, selection] + ansiColors {
                packed.append(Self.pack(c))
            }
            self.colorData = packed
        }

        private static func pack(_ color: NSColor) -> UInt64 {
            let c = color.usingColorSpace(.sRGB) ?? color
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            c.getRed(&r, green: &g, blue: &b, alpha: &a)
            let ri = UInt64(r * 65535) & 0xFFFF
            let gi = UInt64(g * 65535) & 0xFFFF
            let bi = UInt64(b * 65535) & 0xFFFF
            let ai = UInt64(a * 65535) & 0xFFFF
            return (ri << 48) | (gi << 32) | (bi << 16) | ai
        }
    }
}

/// Creates and manages a terminal backend instance with a shell process.
final class TerminalInstance: NSObject, TerminalBackendDelegate {
    let backend: TerminalBackend
    var onTitleChange: ((String) -> Void)?
    var onDirectoryChange: ((String) -> Void)?
    var onProcessTerminated: (() -> Void)?
    var onResizeSplit: ((CGFloat) -> Void)?
    var onEqualizeSplits: (() -> Void)?
    private(set) var currentTitle: String = "zsh"
    private(set) var currentDirectory: String = ""
    private var isTerminated = false

    init(backendType: BackendType = .current) {
        backend = backendType.createBackend()
        super.init()
        backend.delegate = self
    }

    /// Wrap an already-created backend (for split surfaces with inherited config).
    init(existingBackend: TerminalBackend) {
        backend = existingBackend
        super.init()
        backend.delegate = self
    }

    /// Configured shell path. Empty or "auto" means use $SHELL env var.
    static var configuredShell: String {
        let saved = UserDefaults.standard.string(forKey: "shellPath") ?? ""
        if saved.isEmpty || saved == "auto" {
            return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        }
        return saved
    }

    func startShell(in directory: String? = nil, environment: [String: String] = [:]) {
        guard !isTerminated else { return }
        let shell = Self.configuredShell
        let shellName = "-" + (shell as NSString).lastPathComponent
        backend.startProcess(
            executable: shell, execName: shellName,
            currentDirectory: directory, environment: environment
        )
    }

    func terminate() {
        guard !isTerminated else { return }
        isTerminated = true
        backend.terminate()
    }

    // MARK: - TerminalBackendDelegate

    func terminalSizeChanged(cols: Int, rows: Int) {
        // Terminal handles SIGWINCH internally
    }

    func terminalTitleChanged(_ title: String) {
        currentTitle = title
        onTitleChange?(title)
    }

    func terminalDirectoryChanged(_ directory: String) {
        currentDirectory = directory
        onDirectoryChange?(directory)
    }

    func terminalProcessTerminated(exitCode: Int32?) {
        isTerminated = true
        onProcessTerminated?()
    }

    func terminalRequestedResizeSplit(direction: UInt32, amount: UInt16) {
        // Ghostty sends amount as percentage points (e.g. 10 = 10%).
        // Convert to ratio delta: positive = grow focused pane.
        let delta = CGFloat(amount) / 100.0
        onResizeSplit?(delta)
    }

    func terminalRequestedEqualizeSplits() {
        onEqualizeSplits?()
    }
}
