import AppKit

final class TerminalPanel: NSPanel {
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: flag
        )
        configure()
    }

    private func configure() {
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 8)
        backgroundColor = NSColor.white.withAlphaComponent(0.001)
        isOpaque = false
        hasShadow = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = false
        isMovableByWindowBackground = false
        animationBehavior = .none
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [
            .fullScreenAuxiliary,
            .stationary,
            .canJoinAllSpaces,
            .ignoresCycle,
        ]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func noResponder(for eventSelector: Selector) {
        // Suppress NSBeep — the terminal handles all key events via Ghostty
    }

    override func sendEvent(_ event: NSEvent) {
        // Ensure first click inside panel is delivered immediately
        if event.type == .leftMouseDown {
            makeKey()
        }
        super.sendEvent(event)
    }

    // Resign key when clicking outside
    override func resignKey() {
        super.resignKey()
        // Notify the window controller that focus was lost
        NotificationCenter.default.post(name: .panelDidResignKey, object: self)
    }
}

extension Notification.Name {
    static let panelDidResignKey = Notification.Name("\(AppIdentity.slug).panelDidResignKey")
    static let splitRequest = Notification.Name("\(AppIdentity.slug).splitRequest")
    /// Posted when the theme in effect changes, including when a light/dark pair
    /// switches side because the system appearance changed.
    static let terminalThemeDidChange = Notification.Name("\(AppIdentity.slug).themeDidChange")
    /// Posted when the font size changes from somewhere other than the tab-bar slider —
    /// a ⌘-scroll or a pinch over the terminal — so the slider can catch up.
    static let terminalFontSizeDidChange = Notification.Name("\(AppIdentity.slug).fontSizeDidChange")
    /// Posted when a terminal surface is clicked, so the Settings sidebar can close —
    /// clicking into the terminal dismisses it, clicking within it does not.
    static let terminalClicked = Notification.Name("\(AppIdentity.slug).terminalClicked")
}
