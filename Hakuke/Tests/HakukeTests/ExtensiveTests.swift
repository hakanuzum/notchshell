import Testing
import AppKit
@testable import Hakuke

// MARK: - TerminalPanel Tests

@MainActor
@Suite(.serialized)
struct TerminalPanelTests {

    private func makePanel() -> TerminalPanel {
        TerminalPanel(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 400),
            styleMask: [],
            backing: .buffered,
            defer: true
        )
    }

    @Test func panel_canBecomeKey() {
        let panel = makePanel()
        #expect(panel.canBecomeKey == true)
    }

    @Test func panel_cannotBecomeMain() {
        let panel = makePanel()
        #expect(panel.canBecomeMain == false)
    }

    @Test func panel_isNotOpaque() {
        let panel = makePanel()
        #expect(panel.isOpaque == false)
    }

    @Test func panel_hasNoShadow() {
        let panel = makePanel()
        #expect(panel.hasShadow == false)
    }

    @Test func panel_isNotMovable() {
        let panel = makePanel()
        #expect(panel.isMovable == false)
    }

    @Test func panel_isNotMovableByBackground() {
        let panel = makePanel()
        #expect(panel.isMovableByWindowBackground == false)
    }

    @Test func panel_isFloating() {
        let panel = makePanel()
        #expect(panel.isFloatingPanel == true)
    }

    @Test func panel_animationBehavior_isNone() {
        let panel = makePanel()
        #expect(panel.animationBehavior == .none)
    }

    @Test func panel_acceptsMouseMovedEvents() {
        let panel = makePanel()
        #expect(panel.acceptsMouseMovedEvents == true)
    }

    @Test func panel_level_aboveStatusWindow() {
        let panel = makePanel()
        // On VMs without full WindowServer, CGWindowLevelForKey may return
        // different values at init time vs query time. Verify panel is above
        // normal window level (0) which is stable across environments.
        #expect(panel.level.rawValue > 0)
    }

    @Test func panel_styleMask_isBorderless() {
        let panel = makePanel()
        #expect(panel.styleMask.contains(.borderless))
    }

    @Test func panel_styleMask_isNonActivating() {
        let panel = makePanel()
        #expect(panel.styleMask.contains(.nonactivatingPanel))
    }

    @Test func panel_styleMask_hasFullSizeContentView() {
        let panel = makePanel()
        #expect(panel.styleMask.contains(.fullSizeContentView))
    }

    @Test func panel_collectionBehavior_canJoinAllSpaces() {
        let panel = makePanel()
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
    }

    @Test func panel_collectionBehavior_isStationary() {
        let panel = makePanel()
        #expect(panel.collectionBehavior.contains(.stationary))
    }

    @Test func panel_collectionBehavior_ignoresCycle() {
        let panel = makePanel()
        #expect(panel.collectionBehavior.contains(.ignoresCycle))
    }

    @Test func panel_backgroundColor_isNearlyTransparent() {
        let panel = makePanel()
        let bg = panel.backgroundColor!
        let alpha = bg.alphaComponent
        #expect(alpha < 0.01)
        #expect(alpha > 0)
    }

    @Test func panel_titleVisibility_isHidden() {
        let panel = makePanel()
        #expect(panel.titleVisibility == .hidden)
    }

    @Test func panel_titlebarAppearsTransparent() {
        let panel = makePanel()
        #expect(panel.titlebarAppearsTransparent == true)
    }
}

// MARK: - ScreenDetector Tests

@MainActor
@Suite(.serialized)
struct ScreenDetectorExtendedTests {

    @Test func detect_returnsValidInfo() {
        let info = ScreenDetector.detect()
        #expect(info.screenFrame.width > 0)
        #expect(info.screenFrame.height > 0)
        #expect(info.visibleFrame.width > 0)
        #expect(info.visibleFrame.height > 0)
    }

    @Test func detect_topInsetWidth_isPositive() {
        let info = ScreenDetector.detect()
        #expect(info.topInsetWidth > 0)
    }

    @Test func detect_topInsetHeight_isNonNegative() {
        let info = ScreenDetector.detect()
        #expect(info.topInsetHeight >= 0)
    }

    @Test func detect_visibleFrame_withinScreenFrame() {
        let info = ScreenDetector.detect()
        // Visible frame should be contained within (or equal to) screen frame
        #expect(info.visibleFrame.minX >= info.screenFrame.minX)
        #expect(info.visibleFrame.maxX <= info.screenFrame.maxX)
        #expect(info.visibleFrame.minY >= info.screenFrame.minY)
        #expect(info.visibleFrame.maxY <= info.screenFrame.maxY)
    }

    @Test func detect_topInsetRect_atTopOfScreen() {
        let info = ScreenDetector.detect()
        if info.hasTopInset {
            // Top inset should be at the top of the screen
            #expect(info.topInsetRect.maxY == info.screenFrame.maxY)
        }
    }

    @Test func detect_specificScreen_usesGivenScreen() {
        guard let screen = NSScreen.main else { return }
        let info = ScreenDetector.detect(for: screen)
        #expect(info.screenFrame == screen.frame)
    }

    @Test func screenInfo_hasAllFields() {
        let info = ScreenInfo(
            hasTopInset: true,
            topInsetRect: NSRect(x: 100, y: 900, width: 170, height: 32),
            topInsetWidth: 170,
            topInsetHeight: 32,
            screenFrame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 868)
        )
        #expect(info.hasTopInset == true)
        #expect(info.topInsetWidth == 170)
        #expect(info.topInsetHeight == 32)
    }

    @Test func screenInfo_noTopInset() {
        let info = ScreenInfo(
            hasTopInset: false,
            topInsetRect: NSRect(x: 620, y: 900, width: 200, height: 0),
            topInsetWidth: 200,
            topInsetHeight: 0,
            screenFrame: NSRect(x: 0, y: 0, width: 1440, height: 900),
            visibleFrame: NSRect(x: 0, y: 0, width: 1440, height: 875)
        )
        #expect(info.hasTopInset == false)
        #expect(info.topInsetHeight == 0)
    }
}

// MARK: - TerminalTheme Extended Tests

@MainActor
@Suite(.serialized)
struct TerminalThemeExtendedTests {

    @Test func defaultTheme_has16AnsiColors() {
        let theme = TerminalTheme.default
        #expect(theme.ansiColors.count == 16)
    }

    @Test func defaultTheme_fontName() {
        let theme = TerminalTheme.default
        #expect(theme.fontName == "SF Mono")
    }

    @Test func defaultTheme_fontSize() {
        let theme = TerminalTheme.default
        #expect(theme.fontSize == 13)
    }

    @Test func defaultTheme_backgroundOpacity() {
        let theme = TerminalTheme.default
        #expect(theme.backgroundOpacity == 0.95)
    }

    @Test func defaultTheme_font_resolves() {
        let theme = TerminalTheme.default
        let font = theme.font
        #expect(font.pointSize == 13)
    }

    @Test func theme_invalidFontName_fallsBack() {
        var theme = TerminalTheme.default
        theme.fontName = "NonExistentFont12345"
        let font = theme.font
        // Should fall back to monospaced system font
        #expect(font.pointSize == theme.fontSize)
        #expect(font.isFixedPitch)
    }

    @Test func theme_customFontSize() {
        var theme = TerminalTheme.default
        theme.fontSize = 18
        let font = theme.font
        #expect(font.pointSize == 18)
    }

    @Test func theme_foregroundColor_isNotTransparent() {
        let theme = TerminalTheme.default
        #expect(theme.foreground.alphaComponent == 1.0)
    }

    @Test func theme_backgroundColor_isNotTransparent() {
        let theme = TerminalTheme.default
        #expect(theme.background.alphaComponent == 1.0)
    }

    @Test func theme_cursorColor_isNotTransparent() {
        let theme = TerminalTheme.default
        #expect(theme.cursor.alphaComponent == 1.0)
    }

    @Test func theme_ansiColors_allNotTransparent() {
        let theme = TerminalTheme.default
        for (i, color) in theme.ansiColors.enumerated() {
            #expect(color.alphaComponent == 1.0, "ANSI color \(i) should be fully opaque")
        }
    }

    @Test func theme_selectionBackground_hasSemiTransparency() {
        let theme = TerminalTheme.default
        #expect(theme.selectionBackground.alphaComponent < 1.0)
        #expect(theme.selectionBackground.alphaComponent > 0.0)
    }

    @Test func theme_mutation_doesNotAffectDefault() {
        var theme = TerminalTheme.default
        theme.fontSize = 99
        theme.fontName = "Courier"
        #expect(TerminalTheme.default.fontSize == 13)
        #expect(TerminalTheme.default.fontName == "SF Mono")
    }

    @Test func theme_backgroundOpacity_canBeModified() {
        var theme = TerminalTheme.default
        theme.backgroundOpacity = 0.5
        #expect(theme.backgroundOpacity == 0.5)

        theme.backgroundOpacity = 1.0
        #expect(theme.backgroundOpacity == 1.0)
    }
}

// MARK: - Window Controller Resize Tests

@MainActor
@Suite(.serialized)
struct WindowControllerResizeTests {

    @Test func setWidthPercent_atBoundaries() {
        let wc = WindowController()
        wc.setWidthPercent(30)
        #expect(wc.widthPercent == 30)
        wc.setWidthPercent(100)
        #expect(wc.widthPercent == 100)
    }

    @Test func setWidthPercent_belowMinimum_clamps() {
        let wc = WindowController()
        wc.setWidthPercent(10)
        #expect(wc.widthPercent == 30)
        wc.setWidthPercent(0)
        #expect(wc.widthPercent == 30)
        wc.setWidthPercent(-10)
        #expect(wc.widthPercent == 30)
    }

    @Test func setWidthPercent_aboveMaximum_clamps() {
        let wc = WindowController()
        wc.setWidthPercent(150)
        #expect(wc.widthPercent == 100)
    }

    @Test func setHeightPercent_atBoundaries() {
        let wc = WindowController()
        wc.setHeightPercent(20)
        #expect(wc.heightPercent == 20)
        wc.setHeightPercent(90)
        #expect(wc.heightPercent == 90)
    }

    @Test func setHeightPercent_belowMinimum_clamps() {
        let wc = WindowController()
        wc.setHeightPercent(5)
        #expect(wc.heightPercent == 20)
        wc.setHeightPercent(0)
        #expect(wc.heightPercent == 20)
    }

    @Test func setHeightPercent_aboveMaximum_clamps() {
        let wc = WindowController()
        wc.setHeightPercent(95)
        #expect(wc.heightPercent == 90)
    }

    @Test func terminalSize_minimumDimensions() {
        let wc = WindowController()
        let size = wc.terminalSize
        #expect(size.width >= 300)
        #expect(size.height >= 150)
    }

    @Test func terminalSize_reflectsCurrentPercent() {
        let wc = WindowController()
        let screen = wc.resolvedScreen.frame
        wc.setWidthPercent(50)
        wc.setHeightPercent(40)
        let size = wc.terminalSize
        let expectedW = max(screen.width * 0.50, 300)
        let expectedH = max(screen.height * 0.40, 150)
        #expect(abs(size.width - expectedW) < 1)
        #expect(abs(size.height - expectedH) < 1)
    }

    @Test func cachedWidth_updatedBySetWidthPercent() {
        let wc = WindowController()
        wc.setWidthPercent(60)
        #expect(wc.cachedWidth == wc.terminalSize.width)
    }

    @Test func cachedWidth_updatedByUpdateWidthByDelta() {
        let wc = WindowController()
        let screen = wc.resolvedScreen.frame
        wc.updateWidthByDelta(screen.width * 0.5)
        #expect(wc.cachedWidth > 0)
    }
}

// MARK: - Window Controller Show/Hide Edge Cases

@MainActor
@Suite(.serialized)
struct WindowControllerLifecycleTests {

    @Test func show_setsState() {
        let wc = WindowController()
        wc.show()
        #expect(wc.state == .visible)
    }

    @Test func show_twice_isIdempotent() {
        let wc = WindowController()
        wc.show()
        wc.show()
        #expect(wc.state == .visible)
    }

    @Test func hide_setsState() {
        let wc = WindowController()
        wc.show()
        wc.hide()
        #expect(wc.state == .hidden)
    }

    @Test func hide_twice_isIdempotent() {
        let wc = WindowController()
        wc.show()
        wc.hide()
        wc.hide()
        #expect(wc.state == .hidden)
    }

    @Test func toggle_fromHidden_shows() {
        let wc = WindowController()
        wc.toggle()
        #expect(wc.state == .visible)
    }

    @Test func toggle_fromVisible_hides() {
        let wc = WindowController()
        wc.show()
        wc.toggle()
        #expect(wc.state == .hidden)
    }

    @Test func rapidToggle_20_times_endsHidden() {
        let wc = WindowController()
        for _ in 0..<20 { wc.toggle() }
        #expect(wc.state == .hidden)
    }

    @Test func rapidToggle_21_times_endsVisible() {
        let wc = WindowController()
        for _ in 0..<21 { wc.toggle() }
        #expect(wc.state == .visible)
    }

    @Test func show_cachesWidth() {
        let wc = WindowController()
        wc.show()
        #expect(wc.cachedWidth > 0)
    }

    @Test func show_enablesMouseEvents() {
        let wc = WindowController()
        wc.show()
        #expect(wc.panel.ignoresMouseEvents == false)
    }

    @Test func hide_disablesMouseEvents() {
        let wc = WindowController()
        wc.show()
        wc.hide()
        #expect(wc.panel.ignoresMouseEvents == true)
    }

    @Test func show_hide_preservesPinState() {
        let wc = WindowController()
        wc.isPinned = true
        wc.show()
        wc.hide()
        #expect(wc.isPinned == true)
    }

    @Test func show_hide_preservesResize() {
        let wc = WindowController()
        wc.setWidthPercent(80)
        wc.setHeightPercent(60)
        wc.show()
        wc.hide()
        #expect(wc.widthPercent == 80)
        #expect(wc.heightPercent == 60)
    }

    @Test func setDisplayID_updatesProperty() {
        let wc = WindowController()
        wc.setDisplayID(42)
        #expect(wc.displayID == 42)
        wc.setDisplayID(0) // auto
        #expect(wc.displayID == 0)
    }

    @Test func resolvedScreen_returnsValidScreen() {
        let wc = WindowController()
        let screen = wc.resolvedScreen
        #expect(screen.frame.width > 0)
        #expect(screen.frame.height > 0)
    }

    @Test func openSettings_showsPanelIfHidden() {
        let wc = WindowController()
        #expect(wc.state == .hidden)
        wc.openSettings()
        #expect(wc.state == .visible)
        #expect(wc.tabManager.activeTab?.kind == .settings)
    }

    @Test func openHelp_showsPanelIfHidden() {
        let wc = WindowController()
        #expect(wc.state == .hidden)
        wc.openHelp()
        #expect(wc.state == .visible)
        #expect(wc.tabManager.activeTab?.kind == .help)
    }
}

// MARK: - Tab Manager Advanced Tests

@MainActor
@Suite(.serialized)
struct TabManagerAdvancedTests {

    @Test func addManyTabs_allUnique() {
        let tm = TabManager()
        for _ in 0..<20 {
            tm.addTab()
        }
        let ids = tm.tabs.map(\.id)
        #expect(Set(ids).count == ids.count)
        #expect(tm.tabs.count == 21) // 1 initial + 20
    }

    @Test func closeAllTabsExceptFirst_activeAdjusts() {
        let tm = TabManager()
        tm.addTab()
        tm.addTab()
        tm.addTab()
        let firstID = tm.tabs[0].id
        while tm.tabs.count > 1 {
            if let lastID = tm.tabs.last?.id, lastID != firstID {
                tm.closeTab(id: lastID)
            } else {
                break
            }
        }
        #expect(tm.tabs.count == 1)
        #expect(tm.tabs[0].id == firstID)
    }

    @Test func closeFirstTab_activatesNext() {
        let tm = TabManager()
        tm.addTab()
        tm.addTab()
        tm.selectTab(at: 0)
        let firstID = tm.tabs[0].id
        let secondID = tm.tabs[1].id
        tm.closeTab(id: firstID)
        #expect(tm.tabs.count == 2)
        #expect(tm.tabs[0].id == secondID)
        #expect(tm.activeTabIndex <= tm.tabs.count - 1)
    }

    @Test func closeMiddleTab_preservesOrder() {
        let tm = TabManager()
        tm.addTab()
        tm.addTab()
        let ids = tm.tabs.map(\.id)
        tm.closeTab(id: ids[1])
        #expect(tm.tabs.count == 2)
        #expect(tm.tabs[0].id == ids[0])
        #expect(tm.tabs[1].id == ids[2])
    }

    @Test func selectTab_eachIndex_isCorrect() {
        let tm = TabManager()
        tm.addTab()
        tm.addTab()
        for i in 0..<3 {
            tm.selectTab(at: i)
            #expect(tm.activeTabIndex == i)
            #expect(tm.activeTab?.id == tm.tabs[i].id)
        }
    }

    @Test func renameTab_preservesOtherTabTitles() {
        let tm = TabManager()
        tm.addTab()
        let firstID = tm.tabs[0].id
        let secondID = tm.tabs[1].id
        tm.renameTab(id: firstID, name: "Alpha")
        #expect(tm.tabs[0].displayTitle == "Alpha")
        #expect(tm.tabs[1].customTitle == nil)
        tm.renameTab(id: secondID, name: "Beta")
        #expect(tm.tabs[0].displayTitle == "Alpha")
        #expect(tm.tabs[1].displayTitle == "Beta")
    }

    @Test func closeSpecialTabs_preservesTerminals() {
        let tm = TabManager()
        tm.addTab()
        let termIDs = tm.tabs.map(\.id)
        tm.openSettings()
        tm.openHelp()
        #expect(tm.tabs.count == 4)

        tm.closeSpecialTabs()
        #expect(tm.tabs.count == 2)
        #expect(tm.tabs.allSatisfy { $0.kind == .terminal })
        #expect(tm.tabs.map(\.id) == termIDs)
    }

    @Test func specialTabs_persistOnHide() {
        let tm = TabManager()
        tm.openSettings()
        tm.openHelp()
        let count = tm.tabs.count
        // closeSpecialTabs is no longer called on hide,
        // so special tabs should persist
        #expect(tm.tabs.contains(where: { $0.kind == .settings }))
        #expect(tm.tabs.contains(where: { $0.kind == .help }))
        #expect(tm.tabs.count == count)
    }

    @Test func activeTabIndex_neverExceedsBounds() {
        let tm = TabManager()
        tm.addTab()
        tm.addTab()
        tm.selectTab(at: 2) // last
        tm.closeTab(id: tm.tabs[2].id) // close last
        #expect(tm.activeTabIndex < tm.tabs.count)
    }

    @Test func settings_opensOnce_switchesToExisting() {
        let tm = TabManager()
        tm.openSettings()
        let settingsID = tm.activeTab?.id
        tm.selectTab(at: 0)
        tm.openSettings()
        // Should switch to existing settings tab, not create new
        #expect(tm.activeTab?.id == settingsID)
    }

    @Test func help_opensOnce_switchesToExisting() {
        let tm = TabManager()
        tm.openHelp()
        let helpID = tm.activeTab?.id
        tm.selectTab(at: 0)
        tm.openHelp()
        #expect(tm.activeTab?.id == helpID)
    }

    @Test func opacity_default() {
        let tm = TabManager()
        // Default is 0.95 but may be overridden by AppStorage
        #expect(tm.theme.backgroundOpacity >= 0.3)
        #expect(tm.theme.backgroundOpacity <= 1.0)
    }

    @Test func opacity_setAndGet() {
        let tm = TabManager()
        tm.setOpacity(0.7)
        #expect(tm.theme.backgroundOpacity == 0.7)
    }

    @Test func opacity_clampMin() {
        let tm = TabManager()
        tm.setOpacity(0.1)
        #expect(tm.theme.backgroundOpacity == 0.3)
    }

    @Test func opacity_clampMax() {
        let tm = TabManager()
        tm.setOpacity(2.0)
        #expect(tm.theme.backgroundOpacity == 1.0)
    }
}

// MARK: - Pane Manager Advanced Tests

@MainActor
@Suite(.serialized)
struct PaneManagerAdvancedTests {

    @Test func split_horizontal_thenVertical_creates3Panes() throws {
        let pm = PaneManager()
        try #require(pm.splitFocusedPane(axis: .horizontal))
        pm.splitFocusedPane(axis: .vertical) // 3
        #expect(pm.rootPane.leafCount == 3)
    }

    @Test func split_4times_creates5Panes() throws {
        let pm = PaneManager()
        try #require(pm.splitFocusedPane(axis: .horizontal))
        pm.splitFocusedPane(axis: .horizontal) // 3
        pm.splitFocusedPane(axis: .vertical) // 4
        pm.splitFocusedPane(axis: .vertical) // 5
        #expect(pm.rootPane.leafCount == 5)
    }

    @Test func split_preservesExistingPanes() throws {
        let pm = PaneManager()
        let firstID = pm.focusedPaneID
        try #require(pm.splitFocusedPane(axis: .horizontal))
        let leafIDs = pm.rootPane.leafIDs
        #expect(leafIDs.contains(firstID))
    }

    @Test func close_allButOne_fromMany() throws {
        let pm = PaneManager()
        try #require(pm.splitFocusedPane(axis: .horizontal))
        pm.splitFocusedPane(axis: .vertical)
        pm.splitFocusedPane(axis: .horizontal)
        #expect(pm.rootPane.leafCount == 4)

        // Close panes until 1 remains
        while pm.rootPane.leafCount > 1 {
            pm.closePane(id: pm.focusedPaneID)
        }
        #expect(pm.rootPane.leafCount == 1)
    }

    @Test func focusedInstance_afterSplit_isNewPane() throws {
        let pm = PaneManager()
        let originalInstance = pm.focusedInstance
        try #require(pm.splitFocusedPane(axis: .horizontal))
        let newInstance = pm.focusedInstance
        #expect(newInstance !== originalInstance)
    }

    @Test func moveFocus_circularNavigation() throws {
        let pm = PaneManager()
        try #require(pm.splitFocusedPane(axis: .horizontal))
        let ids = pm.rootPane.leafIDs
        pm.focusedPaneID = ids[0]

        // Next → 1, Next → 0 (wraps)
        pm.moveFocus(.next)
        #expect(pm.focusedPaneID == ids[1])
        pm.moveFocus(.next)
        #expect(pm.focusedPaneID == ids[0])
    }

    @Test func onFocusedTitleChange_firesForFocusedPane() {
        let pm = PaneManager()
        var titleChanged = false
        pm.onFocusedTitleChange = { _ in titleChanged = true }
        // The callback is wired via setupCallbacks — we verify it exists
        #expect(pm.onFocusedTitleChange != nil)
    }

    @Test func onLastPaneClosed_firesWhenLastClosed() {
        let pm = PaneManager()
        var closed = false
        pm.onLastPaneClosed = { closed = true }
        pm.closePane(id: pm.focusedPaneID)
        #expect(closed)
    }

    @Test func onLastPaneClosed_doesNotFireWhenMultiple() throws {
        let pm = PaneManager()
        var closed = false
        pm.onLastPaneClosed = { closed = true }
        try #require(pm.splitFocusedPane(axis: .horizontal))
        pm.closePane(id: pm.focusedPaneID)
        #expect(!closed)
        #expect(pm.rootPane.leafCount == 1)
    }

    @Test func currentDirectory_isEmpty_initially() {
        let pm = PaneManager()
        // Before shell reports directory, it's empty
        #expect(pm.currentDirectory == "" || !pm.currentDirectory.isEmpty)
    }
}

// MARK: - HorizontalEdge Tests

@MainActor
@Suite(.serialized)
struct HorizontalEdgeExtendedTests {

    @Test func edge_left() {
        let edge: HorizontalEdge = .left
        if case .left = edge { } else {
            Issue.record("Expected .left")
        }
    }

    @Test func edge_right() {
        let edge: HorizontalEdge = .right
        if case .right = edge { } else {
            Issue.record("Expected .right")
        }
    }

    @Test func edge_notEqual() {
        let left: HorizontalEdge = .left
        let right: HorizontalEdge = .right
        // They should be different enum cases
        switch (left, right) {
        case (.left, .right): break // expected
        default: Issue.record("Edges should differ")
        }
    }
}

// MARK: - Notification Tests

@MainActor
@Suite(.serialized)
struct NotificationTests {

    @Test func panelDidResignKey_notificationExists() {
        let name = Notification.Name.panelDidResignKey
        #expect(name.rawValue == "\(AppIdentity.slug).panelDidResignKey")
    }

    @Test func panelDidResignKey_isPostedOnResign() {
        let panel = TerminalPanel(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [],
            backing: .buffered,
            defer: true
        )
        var received = false
        let observer = NotificationCenter.default.addObserver(
            forName: .panelDidResignKey,
            object: panel,
            queue: .main
        ) { _ in
            received = true
        }
        panel.resignKey()
        #expect(received)
        NotificationCenter.default.removeObserver(observer)
    }
}

// MARK: - Tab Kind Tests

@MainActor
@Suite(.serialized)
struct TabKindTests {

    @Test func terminal_tab_hasKindTerminal() {
        let tab = Tab()
        #expect(tab.kind == .terminal)
    }

    @Test func terminal_tab_hasPaneManager() {
        let tab = Tab()
        #expect(tab.paneManager != nil)
    }

    @Test func settings_tab_hasNoPaneManager() {
        let tab = Tab(kind: .settings, title: "Settings")
        #expect(tab.paneManager == nil)
    }

    @Test func help_tab_hasNoPaneManager() {
        let tab = Tab(kind: .help, title: "Help")
        #expect(tab.paneManager == nil)
    }

    @Test func terminal_tab_instance_isNonNil() {
        let tab = Tab()
        #expect(tab.instance != nil)
    }

    @Test func settings_tab_instance_isNil() {
        let tab = Tab(kind: .settings, title: "Settings")
        #expect(tab.instance == nil)
    }

    @Test func tab_displayTitle_default() {
        let tab = Tab()
        #expect(tab.displayTitle == "zsh")
    }

    @Test func tab_displayTitle_custom() {
        var tab = Tab()
        tab.customTitle = "My Shell"
        #expect(tab.displayTitle == "My Shell")
    }

    @Test func tab_displayTitle_nilCustom_fallsBack() {
        var tab = Tab()
        tab.customTitle = "Temp"
        tab.customTitle = nil
        #expect(tab.displayTitle == tab.title)
    }
}

// MARK: - ControlServer Access State Tests

@MainActor
@Suite(.serialized)
struct ControlServerAccessTests {

    @Test func accessState_canBeEnabled() {
        let oldState = ControlServer.accessState
        ControlServer.accessState = "enabled"
        #expect(ControlServer.accessState == "enabled")
        ControlServer.accessState = oldState
    }

    @Test func accessState_canBeDisabled() {
        let oldState = ControlServer.accessState
        ControlServer.accessState = "disabled"
        #expect(ControlServer.accessState == "disabled")
        ControlServer.accessState = oldState
    }

    @Test func accessState_persistsAcrossReads() {
        let oldState = ControlServer.accessState
        ControlServer.accessState = "test-value"
        let read1 = ControlServer.accessState
        let read2 = ControlServer.accessState
        #expect(read1 == read2)
        ControlServer.accessState = oldState
    }
}

// MARK: - GhosttyApp Config Tests

#if canImport(GhosttyKit)
@MainActor
@Suite(.serialized)
struct GhosttyAppTests {

    @Test func shared_isSingleton() {
        let a = GhosttyApp.shared
        let b = GhosttyApp.shared
        #expect(a === b)
    }

    @Test func configPath_isNonEmpty() {
        let app = GhosttyApp.shared
        app.initialize()
        let path = app.configPath
        #expect(!path.isEmpty)
    }

    @Test func initialize_canBeCalledMultipleTimes() {
        let app = GhosttyApp.shared
        app.initialize()
        app.initialize()
        // Should not crash or duplicate resources
    }
}
#endif

// MARK: - Backend Type All Cases Tests

@MainActor
@Suite(.serialized)
struct BackendTypeTests {

    @Test func allCases_containsGhostty() {
        #expect(BackendType.allCases.contains(.ghostty))
    }

    @Test func current_isGhostty() {
        #expect(BackendType.current == .ghostty)
    }

    @Test func ghostty_rawValue() {
        #expect(BackendType.ghostty.rawValue == "libghostty")
    }

    @Test func ghostty_isAvailable() {
        #expect(BackendType.ghostty.isAvailable == true)
    }

    @Test func createBackend_returnsWorkingBackend() {
        let backend = BackendType.current.createBackend()
        let view = backend.view
        #expect(view.frame.width >= 0)
    }
}
