import AppKit

// MARK: - Protocol

protocol TerminalBackend: AnyObject {
    /// The NSView to embed in the UI.
    var view: NSView { get }

    /// The view that should receive keyboard focus. Defaults to `view`.
    /// Override when the embeddable view is a container (e.g. Ghostty's opaque wrapper).
    var focusableView: NSView { get }

    // Process lifecycle
    /// `environment` is added to the spawned process's environment and inherited by
    /// everything it runs — which is how a tab is identified in the process tree.
    func startProcess(
        executable: String, execName: String, currentDirectory: String?,
        environment: [String: String]
    )
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
    /// `directory` overrides the cwd a split would otherwise inherit from its source.
    /// Only session restore passes one — a split you make by hand should land where
    /// the pane you split was, which is what inheriting already does.
    func createSplitBackend(directory: String?) -> TerminalBackend?

    /// Whether this surface is on screen. A backend that renders on its own thread
    /// has no way to know the panel dropped away, and keeps drawing until told.
    func setVisible(_ visible: Bool)

    // Delegate
    var delegate: TerminalBackendDelegate? { get set }
}

extension TerminalBackend {
    func createSplitBackend(directory: String?) -> TerminalBackend? { nil }
    func createSplitBackend() -> TerminalBackend? { createSplitBackend(directory: nil) }
    func setVisible(_ visible: Bool) {}

    /// A protocol requirement cannot carry a default argument, so the three-argument
    /// form callers already use lives here instead.
    func startProcess(executable: String, execName: String, currentDirectory: String?) {
        startProcess(
            executable: executable, execName: execName,
            currentDirectory: currentDirectory, environment: [:]
        )
    }
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
    /// OSC 9 / OSC 777 — a program asking for attention, with something to say.
    func terminalRequestedNotification(title: String, body: String)
    /// BEL — the same ask, from a program with no richer channel to say it on.
    func terminalRangBell()
}

extension TerminalBackendDelegate {
    // Default no-op implementations for split actions
    func terminalRequestedSplit(direction: UInt32) {}
    func terminalRequestedGotoSplit(direction: UInt32) {}
    func terminalRequestedResizeSplit(direction: UInt32, amount: UInt16) {}
    func terminalRequestedEqualizeSplits() {}
    func terminalRequestedToggleSplitZoom() {}
    func terminalRequestedNotification(title: String, body: String) {}
    func terminalRangBell() {}
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
