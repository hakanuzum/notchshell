import AppKit
import SwiftUI
import KeyboardShortcuts

enum PanelState: Equatable {
    case hidden
    case visible
}

@MainActor
final class WindowController: ObservableObject {
    let panel: TerminalPanel
    let tabManager: TabManager
    /// Owned here because it records this controller's window and has to outlive any
    /// view that starts it.
    let recorder = PanelRecorder()

    @Published var state: PanelState = .hidden
    @Published var isPinned: Bool = false
    /// Whether the Settings sidebar is open along the trailing edge of the terminal.
    /// Settings used to open as a full tab; it is a side panel now, so the terminal
    /// stays visible beside it.
    @Published var showSettingsSidebar: Bool = false
    /// Whether the command palette is up. Owned here rather than by the tab bar so
    /// ⌘P can reach it from the key monitor.
    @Published var showCommandPalette: Bool = false
    @Published var displayID: Int = 0
    /// Full menu-bar width by default (Unclutter shelf).
    @Published var widthPercent: Int = 100
    /// Share of the screen height the panel takes when nothing has been chosen. Was
    /// spelled out separately in the live value and the stored one; the resize handle
    /// needs a third copy to reset to, so it became a constant.
    static let defaultHeightPercent = 45

    @Published var heightPercent: Int = WindowController.defaultHeightPercent
    @Published var panelWidth: CGFloat = 0
    @Published var chromeStyle: PanelChromeStyle = .auto

    private var previousApp: NSRunningApplication?
    private var resignObserver: Any?
    private var themeObserver: NSObjectProtocol?
    private var appSwitchObserver: Any?
    private var screenObserver: Any?
    private var spaceObserver: Any?
    private var terminalClickObserver: Any?
    private var notificationClickObserver: Any?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var middleClickMonitor: Any?
    private var scrollMonitor: Any?

    // Debounce: ignore resign/appSwitch hide triggers briefly after show()
    private var showTimestamp: Date = .distantPast
    /// Theme popover lives in another window — suppress auto-hide while open / applying.
    private var suppressAutoHideUntil: Date = .distantPast

    // Scroll wheel state for tab switching
    private var scrollAccumulator: CGFloat = 0
    private var lastScrollTime: Date = .distantPast

    // Persisted
    @AppStorage("terminalWidthPercent") private var savedWidthPercent: Int = 100
    @AppStorage("terminalHeightPercent") private var savedHeightPercent: Int = WindowController.defaultHeightPercent
    @AppStorage("selectedDisplayID") private var savedDisplayID: Int = 0
    @AppStorage("panelChromeStyle") private var savedChromeStyle: String = PanelChromeStyle.auto.rawValue

    // MARK: - Sizes

    /// Cached width — set before animation so only height animates (slide down).
    var cachedWidth: CGFloat = 0

    /// Height of the menu bar on the screen the panel is on.
    ///
    /// Both figures matter: a notched display reports the notch through
    /// `safeAreaInsets` and the menu bar through the frame difference, and they are not
    /// the same number.
    var menuBarHeight: CGFloat {
        let screen = resolvedScreen
        return max(screen.frame.maxY - screen.visibleFrame.maxY, screen.safeAreaInsets.top)
    }

    /// The tab bar is drawn the same height as the menu bar, so the shelf is bracketed
    /// by two strips of the same weight.
    var tabBarHeight: CGFloat { menuBarHeight }

    /// The terminal area of the active tab, in window coordinates with a top-left
    /// origin and measured in points — the shape ScreenCaptureKit's `sourceRect` wants.
    ///
    /// Measured rather than assumed: a capture cropped to a rect starting at the menu
    /// bar height returned the band directly below it, so `sourceRect` on a window
    /// filter is relative to the window's top-left, not AppKit's bottom-left.
    ///
    /// Excludes the tab bar, which always sits below the terminal.
    var terminalContentRect: CGRect {
        let size = terminalSize
        let bar = tabBarHeight
        let windowWidth = panel.frame.width > 0 ? panel.frame.width : size.width
        return CGRect(
            x: ((windowWidth - size.width) / 2).rounded(),
            y: menuBarHeight.rounded(),
            width: size.width.rounded(),
            height: max(size.height - bar, 1).rounded()
        )
    }

    var terminalSize: CGSize {
        let screen = resolvedScreen.frame
        let width = screen.width * CGFloat(widthPercent) / 100.0
        let height = screen.height * CGFloat(heightPercent) / 100.0
        return CGSize(width: max(width, 300), height: max(height, 150))
    }

    // MARK: - Init

    init() {
        let panel = TerminalPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
            styleMask: [],
            backing: .buffered,
            defer: true
        )
        self.panel = panel
        self.tabManager = TabManager()

        self.displayID = savedDisplayID
        self.widthPercent = savedWidthPercent
        self.heightPercent = savedHeightPercent
        self.chromeStyle = PanelChromeStyle(rawValue: savedChromeStyle) ?? .auto
        // Prefer full-width Unclutter shelf
        if widthPercent < 90 {
            widthPercent = 100
            savedWidthPercent = 100
        }

        setupContentView()
        setupObservers()
        setupKeyMonitor()
        setupClickMonitor()
        setupMiddleClickMonitor()
        setupScrollMonitor()

        // SwiftUI content animates inside a fixed full-screen frame, but the panel is
        // only ordered in while it is actually on screen — see hide().
        //
        // Order in once at launch so the hosting view gets a layout pass and the first
        // drop-down slides rather than pops, then drop it again.
        repositionPanel()
        panel.ignoresMouseEvents = true
        panel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self, self.state == .hidden else { return }
            self.tabManager.setSurfacesVisible(false)
            self.panel.orderOut(nil)
        }
    }

    deinit {
        if let obs = resignObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = themeObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = appSwitchObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        if let obs = screenObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(obs)
        }
        if let obs = terminalClickObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let obs = notificationClickObserver {
            NotificationCenter.default.removeObserver(obs)
        }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = middleClickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = scrollMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func setupContentView() {
        let rootView = PanelContentView(
            tabManager: tabManager,
            windowController: self
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView
    }

    // MARK: - Panel positioning (fixed frame, no animation)

    func repositionPanel() {
        let screen = resolvedScreen.frame
        panel.setFrame(NSRect(
            x: screen.origin.x,
            y: screen.origin.y,
            width: screen.width,
            height: screen.height
        ), display: true)
        panelWidth = screen.width
    }

    // MARK: - Observers

    private func setupObservers() {
        // Repaint chrome when the theme in effect changes — including when a
        // light/dark pair switches side because the system appearance did.
        themeObserver = NotificationCenter.default.addObserver(
            forName: .terminalThemeDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshChromeTheme() }
        }

        resignObserver = NotificationCenter.default.addObserver(
            forName: .panelDidResignKey,
            object: panel,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                // Decide after a beat, not now: a Space swipe posts resign-key and
                // activeSpaceDidChange in an order macOS does not guarantee. Waiting lets
                // the Space handler set the suppression window first, so a swipe-away does
                // not hide the panel out from under itself. 0.15s is below notice for a
                // genuine click-away.
                try? await Task.sleep(nanoseconds: 150_000_000)
                guard self.shouldAutoHide() else { return }
                self.hide()
            }
        }

        appSwitchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in
                guard self.shouldAutoHide() else { return }
                if app.bundleIdentifier != Bundle.main.bundleIdentifier {
                    if self.isPinned {
                        self.panel.resignKey()
                    } else {
                        // Same reason as the resign handler: an app on the arriving Space
                        // activates during a swipe, and we must not race the Space handler
                        // that keeps the panel alive.
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        guard self.shouldAutoHide() else { return }
                        self.hide()
                    }
                }
            }
        }

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.repositionPanel()
            }
        }

        // Switching Spaces (a Mission Control swipe) makes the panel resign key and, a
        // moment later, some other app on the arriving Space activate. Both of those
        // fire the auto-hide above, so an unpinned panel vanished the instant you swiped
        // away and had to be re-summoned on the new Space. The panel already joins every
        // Space (see TerminalPanel.collectionBehavior), so it is present on the one you
        // land on — it just must not hide on the way. Suppressing auto-hide briefly
        // across the switch lets it ride along, which reads as the terminal following
        // you to the new Space rather than closing.
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard self.state == .visible else { return }
                self.suppressAutoHideUntil = Date().addingTimeInterval(1.0)
            }
        }

        terminalClickObserver = NotificationCenter.default.addObserver(
            forName: .terminalClicked,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.closeSettingsSidebar() }
        }

        // Clicking a notification is a request to go and look at the tab that sent it,
        // which means dropping the panel first if it is up.
        notificationClickObserver = NotificationCenter.default.addObserver(
            forName: TerminalNotifier.didActivateNotification,
            object: nil,
            queue: .main
        ) { [weak self] notif in
            let tabID = notif.userInfo?[TerminalNotifier.tabIDKey] as? String
            Task { @MainActor in
                guard let self, let tabID else { return }
                if self.state == .hidden { self.show() }
                self.tabManager.revealTab(id: tabID)
            }
        }
    }

    // MARK: - Key Monitor (layout-independent, Chrome-style)

    /// Key codes and shortcuts live in `KeyCode` / `ActionShortcut` now — they were
    /// private constants here only because the switch that used them was here too.

    /// Every action this app has, built once. See `ActionRegistry` for why there is one
    /// list and not one per consumer.
    lazy var actions: [AppAction] = ActionRegistry.actions(for: self)

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }

            // ⌘P → the command palette. Handled before the registry because it is the
            // one action that is about the registry rather than in it.
            if event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.shift),
               event.keyCode == KeyCode.p {
                self.showCommandPalette.toggle()
                return nil
            }

            // Whatever the user set in Settings wins over the built-in bindings, so it
            // is checked first — the point of a configurable shortcut is that it beats
            // the default.
            if self.eventMatchesShortcut(event, for: .nextTab) {
                self.tabManager.selectNextTab()
                return nil
            }
            if self.eventMatchesShortcut(event, for: .previousTab) {
                self.tabManager.selectPreviousTab()
                return nil
            }

            if let action = ActionRegistry.action(matching: event, in: self.actions) {
                action.perform()
                return nil
            }

            return event
        }
    }

    private func eventMatchesShortcut(_ event: NSEvent, for name: KeyboardShortcuts.Name) -> Bool {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else { return false }
        let keyMatch = event.keyCode == UInt16(shortcut.carbonKeyCode)
        let modMatch = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            .subtracting(.numericPad)
            .subtracting(.function)
            == shortcut.modifiers.intersection(.deviceIndependentFlagsMask)
        return keyMatch && modMatch
    }

    // MARK: - Mouse Monitors

    private func setupClickMonitor() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            let mouse = NSEvent.mouseLocation
            Task { @MainActor in
                guard self.shouldAutoHide() else { return }
                // Theme popover is a separate window — don't hide when clicking it.
                if NSApp.windows.contains(where: { $0.isVisible && $0.frame.contains(mouse) }) {
                    return
                }
                self.hide()
            }
        }
    }

    @MainActor
    func shouldAutoHide() -> Bool {
        guard state == .visible, !isPinned else { return false }
        guard Date().timeIntervalSince(showTimestamp) > 0.3 else { return false }
        guard Date() >= suppressAutoHideUntil else { return false }
        return true
    }

    @MainActor
    func beginTransientInteraction(seconds: TimeInterval = 2.0) {
        suppressAutoHideUntil = Date().addingTimeInterval(seconds)
        showTimestamp = Date()
    }

    /// Apply Ghostty theme only (does not rewrite starship/zsh).
    @discardableResult
    func applyGhosttyTheme(named name: String) -> Bool {
        applyGhosttyTheme(.single(name))
    }

    /// Apply a theme selection and repaint the tab bar and panel to match.
    @discardableResult
    func applyGhosttyTheme(_ selection: ThemeSelection) -> Bool {
        beginTransientInteraction(seconds: 3.0)
        let ok = GhosttyApp.shared.apply(themeSelection: selection)
        refreshChromeTheme(for: selection)
        if state == .visible {
            panel.ignoresMouseEvents = false
            panel.makeKeyAndOrderFront(nil)
            tabManager.focusTerminalInActiveTab()
        }
        beginTransientInteraction(seconds: 1.0)
        return ok
    }

    /// Repaint chrome from whichever half of the selection the current appearance
    /// selects. A finalized config collapses a pair to one side, so the side has to be
    /// chosen here rather than read back from Ghostty.
    func refreshChromeTheme(for selection: ThemeSelection? = nil) {
        guard let selection = selection ?? GhosttyThemeCatalog.currentSelection() else { return }
        let name = selection.theme(forDarkAppearance: GhosttyApp.shared.systemPrefersDark)
        guard let theme = GhosttyThemeCatalog.parseTerminalTheme(named: name) else { return }
        tabManager.theme = theme
        tabManager.objectWillChange.send()
    }

    func setChromeStyle(_ style: PanelChromeStyle) {
        chromeStyle = style
        savedChromeStyle = style.rawValue
        if style.resolved == .unclutter, widthPercent < 90 {
            setWidthPercent(100)
        }
    }

    /// Middle click on tab → close that tab (Chrome behavior)
    private func setupMiddleClickMonitor() {
        middleClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow, event.buttonNumber == 2 else { return event }

            if let hoveredIndex = self.tabManager.hoveredTabIndex,
               hoveredIndex < self.tabManager.tabs.count {
                let tab = self.tabManager.tabs[hoveredIndex]
                self.tabManager.closeTab(id: tab.id)
            }
            return nil
        }
    }

    /// Scroll wheel on tab bar area → switch tabs (Chrome behavior)
    private func setupScrollMonitor() {
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.panel.isKeyWindow, self.state == .visible else { return event }

            // Only handle scroll when mouse is in the tab bar area (top ~36pt below menu bar)
            let mouse = NSEvent.mouseLocation
            let screen = self.resolvedScreen
            let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
            let termWidth = self.terminalSize.width
            let termX = screen.frame.midX - termWidth / 2
            let tabBarTop = screen.frame.maxY - menuBarHeight
            let tabBarBottom = tabBarTop - 36

            guard mouse.y >= tabBarBottom && mouse.y <= tabBarTop
                    && mouse.x >= termX && mouse.x <= termX + termWidth else {
                return event
            }

            // Debounce: reset accumulator after 500ms gap
            let now = Date()
            if now.timeIntervalSince(self.lastScrollTime) > 0.5 {
                self.scrollAccumulator = 0
            }
            self.lastScrollTime = now

            // Use deltaY (vertical scroll) for tab switching
            self.scrollAccumulator += event.scrollingDeltaY

            let threshold: CGFloat = 15
            if self.scrollAccumulator > threshold {
                self.tabManager.selectPreviousTab()
                self.scrollAccumulator = 0
            } else if self.scrollAccumulator < -threshold {
                self.tabManager.selectNextTab()
                self.scrollAccumulator = 0
            }

            return nil // consume scroll event in tab bar
        }
    }

    // MARK: - Toggle (SwiftUI animation driven by state change)

    func toggle() {
        if state == .hidden { show() }
        else if state == .visible { hide() }
    }

    func show() {
        guard state == .hidden else { return }
        showTimestamp = Date()
        previousApp = NSWorkspace.shared.frontmostApplication

        repositionPanel()

        // Fix width before animation so only height slides
        cachedWidth = terminalSize.width

        panel.ignoresMouseEvents = false
        panel.makeKeyAndOrderFront(nil)
        tabManager.setSurfacesVisible(true)
        NSApp.activate(ignoringOtherApps: true)

        // Defer animation by one run loop tick so the SwiftUI hosting view
        // picks up the new panel frame. Without this, switching monitors
        // shows content sized/centered for the previous screen.
        DispatchQueue.main.async { [self] in
            if UserDefaults.standard.bool(forKey: "disableAnimation") {
                state = .visible
            } else {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)) {
                    state = .visible
                }
            }

            tabManager.focusTerminalInActiveTab()
        }

        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    func hide() {
        guard state == .visible else { return }

        if UserDefaults.standard.bool(forKey: "disableAnimation") {
            state = .hidden
        } else {
            withAnimation(.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)) {
                state = .hidden
            }
        }
        panel.ignoresMouseEvents = true

        // After the animation settles (or immediately) — report occlusion, order the
        // panel out, and activate the previous app.
        //
        // The occlusion call is the one that matters. Collapsing the SwiftUI content
        // to zero height leaves Ghostty rendering, and so does `orderOut`: sampled
        // with the window off screen, its CVDisplayLink still ticked and
        // `Renderer.updateFrame` still ran. Telling the surfaces directly took a
        // full-width panel from 227 MB and ~1.2% CPU while down to 106 MB and ~0.0%.
        // `orderOut` bought nothing measurable; it is kept so that `panel.isVisible`
        // answers honestly, which the click monitor's `NSApp.windows` scan relies on.
        let delay = UserDefaults.standard.bool(forKey: "disableAnimation") ? 0.05 : 0.5
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.state == .hidden else { return }
            self.tabManager.setSurfacesVisible(false)
            self.panel.orderOut(nil)
            if let prev = self.previousApp, !prev.isTerminated {
                prev.activate()
            }
        }
    }

    // MARK: - Resize (percent-based, no animation to avoid jitter)

    func updateHeightByDelta(_ pixelHeight: CGFloat) {
        let screen = resolvedScreen.frame
        let pct = Int((pixelHeight / screen.height) * 100)
        let clamped = min(max(pct, 20), 100)
        heightPercent = clamped
        savedHeightPercent = clamped
    }

    func updateWidthByDelta(_ pixelWidth: CGFloat) {
        let screen = resolvedScreen.frame
        let pct = Int((pixelWidth / screen.width) * 100)
        let clamped = min(max(pct, 30), 100)
        widthPercent = clamped
        savedWidthPercent = clamped
        cachedWidth = terminalSize.width
    }

    func setWidthPercent(_ percent: Int) {
        widthPercent = min(max(percent, 30), 100)
        savedWidthPercent = widthPercent
        cachedWidth = terminalSize.width
    }

    func setHeightPercent(_ percent: Int) {
        heightPercent = min(max(percent, 20), 100)
        savedHeightPercent = heightPercent
    }

    func setDisplayID(_ id: Int) {
        displayID = id
        savedDisplayID = id
    }

    var resolvedScreen: NSScreen {
        if displayID == 0 {
            let mouse = NSEvent.mouseLocation
            for screen in NSScreen.screens {
                if screen.frame.contains(mouse) {
                    return screen
                }
            }
            return NSScreen.main ?? NSScreen.screens[0]
        }
        let targetID = CGDirectDisplayID(displayID)
        for screen in NSScreen.screens {
            if let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               screenID == targetID {
                return screen
            }
        }
        return NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: - Settings / Help (as tabs)

    /// Toggle the Settings sidebar. Also the target of ⌘, and the menu-bar item, so all
    /// three routes land on the same panel rather than the old Settings tab. No
    /// animation: sliding it in flickered the desktop through the translucent terminal,
    /// and an instant toggle is both cleaner and glitch-free.
    func openSettings() {
        if state == .hidden { show() }
        showSettingsSidebar.toggle()
    }

    /// Close the Settings sidebar if it is open. Called when the terminal is clicked —
    /// clicking into the terminal dismisses the sidebar, while clicking within the
    /// sidebar leaves it open; only the toggle (or this) closes it.
    func closeSettingsSidebar() {
        if showSettingsSidebar { showSettingsSidebar = false }
    }

    func openHelp() {
        tabManager.openHelp()
        if state == .hidden { show() }
    }
}
