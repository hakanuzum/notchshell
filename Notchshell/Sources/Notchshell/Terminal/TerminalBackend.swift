import AppKit

// MARK: - Protocol

protocol TerminalBackend: AnyObject {
    /// The NSView to embed in the UI.
    var view: NSView { get }

    /// The view that should receive keyboard focus. Defaults to `view`.
    /// Override when the embeddable view is a container (e.g. Ghostty's opaque wrapper).
    var focusableView: NSView { get }

    // Process lifecycle
    func startProcess(executable: String, execName: String, currentDirectory: String?)
    func terminate()

    // Styling
    func applyFont(_ font: NSFont)
    func applyColors(
        foreground: NSColor, background: NSColor,
        cursor: NSColor, selection: NSColor,
        ansiColors: [NSColor]
    )

    // Search
    func showFindBar()
    func findNext()
    func findPrevious()

    // I/O (used by ControlServer API)
    func send(text: String)
    func readBuffer(lineCount: Int) -> TerminalBufferSnapshot

    // Split
    func createSplitBackend() -> TerminalBackend?

    /// Whether this surface is on screen. A backend that renders on its own thread
    /// has no way to know the panel dropped away, and keeps drawing until told.
    func setVisible(_ visible: Bool)

    // Delegate
    var delegate: TerminalBackendDelegate? { get set }
}

extension TerminalBackend {
    func createSplitBackend() -> TerminalBackend? { nil }
    func setVisible(_ visible: Bool) {}
}

protocol TerminalBackendDelegate: AnyObject {
    func terminalSizeChanged(cols: Int, rows: Int)
    func terminalTitleChanged(_ title: String)
    func terminalDirectoryChanged(_ directory: String)
    func terminalProcessTerminated(exitCode: Int32?)
    // Split pane actions (Ghostty native)
    func terminalRequestedSplit(direction: UInt32)
    func terminalRequestedGotoSplit(direction: UInt32)
    func terminalRequestedResizeSplit(direction: UInt32, amount: UInt16)
    func terminalRequestedEqualizeSplits()
    func terminalRequestedToggleSplitZoom()
}

extension TerminalBackendDelegate {
    // Default no-op implementations for split actions
    func terminalRequestedSplit(direction: UInt32) {}
    func terminalRequestedGotoSplit(direction: UInt32) {}
    func terminalRequestedResizeSplit(direction: UInt32, amount: UInt16) {}
    func terminalRequestedEqualizeSplits() {}
    func terminalRequestedToggleSplitZoom() {}
}

extension TerminalBackend {
    var focusableView: NSView { view }
}

// MARK: - Buffer snapshot

struct TerminalBufferSnapshot {
    let lines: [String]
    let rows: Int
    let cols: Int
}

// MARK: - Backend type

enum BackendType: String, CaseIterable {
    case ghostty = "libghostty"

    static var current: BackendType { .ghostty }

    var isAvailable: Bool { true }

    func createBackend() -> TerminalBackend {
        return GhosttyBackend()
    }
}
