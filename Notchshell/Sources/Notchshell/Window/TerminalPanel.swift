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

    /// Take the frame as given.
    ///
    /// AppKit otherwise slides a window down until its top clears the menu bar, and
    /// exempts only windows at least as tall as the screen. The panel used to be exactly
    /// that — full screen frame — and so escaped the rule by accident. Insetting it for
    /// the Dock made it shorter, the rule applied, and the panel came to rest a menu
    /// bar's height too low with a strip of desktop above it. Measured: asked for a top
    /// at 1474, got 1430.
    ///
    /// Being flush under the menu bar is the whole shape of this product, so the panel
    /// positions itself in screen coordinates and this constraint has no say.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }

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
    /// Posted when a selection is copied to the clipboard, with `userInfo["count"]` set
    /// to the character count, so the panel can show a brief confirmation.
    static let terminalDidCopy = Notification.Name("\(AppIdentity.slug).terminalDidCopy")
}
