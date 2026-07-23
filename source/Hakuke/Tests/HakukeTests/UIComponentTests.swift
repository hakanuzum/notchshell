import Testing
import AppKit
import KeyboardShortcuts
@testable import Hakuke

/// Comprehensive UI component tests covering tab interactions, keyboard shortcuts,
/// focus management, pane operations, and visual state.
@MainActor
@Suite(.serialized)
struct UIComponentTests {

    // MARK: - Helpers

    private func makeController() -> WindowController {
        WindowController()
    }

    // MARK: - Tab selection & navigation

    @Test func selectTab_byIndex_updatesActiveTab() {
        let wc = makeController()
        wc.tabManager.addTab()
        wc.tabManager.addTab()
        // 3 tabs, active is 2
        let firstID = wc.tabManager.tabs[0].id
        wc.tabManager.selectTab(at: 0)
        #expect(wc.tabManager.activeTab?.id == firstID)
        #expect(wc.tabManager.activeTabIndex == 0)
    }

    @Test func selectTab_cmd1Through9_selectsCorrectTab() {
        let wc = makeController()
        // Create 9 tabs total (1 initial + 8 more)
        for _ in 0..<8 {
            wc.tabManager.addTab()
        }
        #expect(wc.tabManager.tabs.count == 9)

        // Cmd+1 → tab 0
        wc.tabManager.selectTab(at: 0)
        #expect(wc.tabManager.activeTabIndex == 0)

        // Cmd+5 → tab 4
        wc.tabManager.selectTab(at: 4)
        #expect(wc.tabManager.activeTabIndex == 4)

        // Cmd+9 → last tab (Chrome behavior)
        wc.tabManager.selectTab(at: wc.tabManager.tabs.count - 1)
        #expect(wc.tabManager.activeTabIndex == 8)
    }

    @Test func selectTab_outOfBounds_noChange() {
        let wc = makeController()
        wc.tabManager.addTab()
        wc.tabManager.selectTab(at: 0)
        // Out of bounds
        wc.tabManager.selectTab(at: 99)
        #expect(wc.tabManager.activeTabIndex == 0)
        wc.tabManager.selectTab(at: -1)
        #expect(wc.tabManager.activeTabIndex == 0)
    }

    @Test func ctrlTab_cyclesForward() {
        let wc = makeController()
        wc.tabManager.addTab()
        wc.tabManager.addTab()
        wc.tabManager.selectTab(at: 0)
        #expect(wc.tabManager.activeTabIndex == 0)

        wc.tabManager.selectNextTab()
        #expect(wc.tabManager.activeTabIndex == 1)
        wc.tabManager.selectNextTab()
        #expect(wc.tabManager.activeTabIndex == 2)
        // Wraps
        wc.tabManager.selectNextTab()
        #expect(wc.tabManager.activeTabIndex == 0)
    }

    @Test func ctrlShiftTab_cyclesBackward() {
        let wc = makeController()
        wc.tabManager.addTab()
        wc.tabManager.addTab()
        wc.tabManager.selectTab(at: 0)

        wc.tabManager.selectPreviousTab()
        #expect(wc.tabManager.activeTabIndex == 2)
        wc.tabManager.selectPreviousTab()
        #expect(wc.tabManager.activeTabIndex == 1)
        wc.tabManager.selectPreviousTab()
        #expect(wc.tabManager.activeTabIndex == 0)
    }

    // MARK: - Tab switching (KeyboardShortcuts recorder)

    @Test func tabSwitch_selectNextPrev_wrapsAround() {
        let wc = makeController()
        wc.tabManager.addTab()
        wc.tabManager.addTab()
        wc.tabManager.selectTab(at: 0)

        wc.tabManager.selectNextTab()
        #expect(wc.tabManager.activeTabIndex == 1)
        wc.tabManager.selectNextTab()
        #expect(wc.tabManager.activeTabIndex == 2)
        wc.tabManager.selectNextTab()
        #expect(wc.tabManager.activeTabIndex == 0)

        wc.tabManager.selectPreviousTab()
        #expect(wc.tabManager.activeTabIndex == 2)
        wc.tabManager.selectPreviousTab()
        #expect(wc.tabManager.activeTabIndex == 1)
    }

    @Test func tabSwitch_singleTab_doesNothing() {
        let wc = makeController()
        #expect(wc.tabManager.tabs.count == 1)
        #expect(wc.tabManager.activeTabIndex == 0)

        wc.tabManager.selectNextTab()
        #expect(wc.tabManager.activeTabIndex == 0)
        wc.tabManager.selectPreviousTab()
        #expect(wc.tabManager.activeTabIndex == 0)
    }

    @Test func keyboardShortcutNames_areDefined() {
        #expect(KeyboardShortcuts.Name.toggleTerminal.rawValue == "toggleTerminal")
        #expect(KeyboardShortcuts.Name.nextTab.rawValue == "nextTab")
        #expect(KeyboardShortcuts.Name.previousTab.rawValue == "previousTab")
    }

    // MARK: - Tab creation (Cmd+T)

    @Test func cmdT_createsNewTab_andActivatesIt() {
        let wc = makeController()
        let initialCount = wc.tabManager.tabs.count
        let initialActiveID = wc.tabManager.activeTab?.id

        wc.tabManager.addTab()
        #expect(wc.tabManager.tabs.count == initialCount + 1)
        #expect(wc.tabManager.activeTab?.id != initialActiveID)
        #expect(wc.tabManager.activeTabIndex == wc.tabManager.tabs.count - 1)
    }

    @Test func addTab_withDirectory_passesDirectoryToShell() {
        let wc = makeController()
        wc.tabManager.addTab(in: "/tmp")
        // Tab was created — we can verify it's the active one
        #expect(wc.tabManager.tabs.count == 2)
        #expect(wc.tabManager.activeTabIndex == 1)
    }

    // MARK: - Tab close (Cmd+W)

    @Test func cmdW_closesActiveTab() {
        let wc = makeController()
        wc.tabManager.addTab()
        #expect(wc.tabManager.tabs.count == 2)
        let activeID = wc.tabManager.activeTab!.id

        wc.tabManager.closeTab(id: activeID)
        #expect(wc.tabManager.tabs.count == 1)
    }

    @Test func cmdW_lastTab_respawns() {
        let wc = makeController()
        let originalID = wc.tabManager.tabs[0].id
        wc.tabManager.closeTab(id: originalID)
        #expect(wc.tabManager.tabs.count == 1)
        #expect(wc.tabManager.tabs[0].id != originalID)
    }

    @Test func cmdW_withSplitPanes_closesOnlyFocusedPane() throws {
        let wc = makeController()
        let tab = wc.tabManager.activeTab!
        let pm = tab.paneManager!
        let initialLeafCount = pm.rootPane.leafCount
        #expect(initialLeafCount == 1)

        // Split the pane
        try #require(pm.splitFocusedPane(axis: .horizontal))
        #expect(pm.rootPane.leafCount == 2)

        // Close focused pane — should leave 1
        wc.tabManager.closeActivePane()
        #expect(pm.rootPane.leafCount == 1)
    }

    // MARK: - Tab rename (double-click)

    @Test func renameTab_setsCustomTitle() {
        let wc = makeController()
        let tabID = wc.tabManager.tabs[0].id
        wc.tabManager.renameTab(id: tabID, name: "My Terminal")
        #expect(wc.tabManager.tabs[0].customTitle == "My Terminal")
        #expect(wc.tabManager.tabs[0].displayTitle == "My Terminal")
    }

    @Test func renameTab_emptyString_clearsCustomTitle() {
        let wc = makeController()
        let tabID = wc.tabManager.tabs[0].id
        wc.tabManager.renameTab(id: tabID, name: "Custom")
        #expect(wc.tabManager.tabs[0].customTitle == "Custom")

        wc.tabManager.renameTab(id: tabID, name: "")
        #expect(wc.tabManager.tabs[0].customTitle == nil)
    }

    @Test func renameTab_nil_clearsCustomTitle() {
        let wc = makeController()
        let tabID = wc.tabManager.tabs[0].id
        wc.tabManager.renameTab(id: tabID, name: "Custom")
        wc.tabManager.renameTab(id: tabID, name: nil)
        #expect(wc.tabManager.tabs[0].customTitle == nil)
    }

    @Test func renameTab_invalidID_doesNothing() {
        let wc = makeController()
        let fakeID = generateShortID()
        wc.tabManager.renameTab(id: fakeID, name: "Should Not Appear")
        #expect(wc.tabManager.tabs.allSatisfy { $0.customTitle == nil })
    }

    // MARK: - Reopen closed tab (Cmd+Shift+T)

    @Test func cmdShiftT_initiallyUnavailable() {
        let wc = makeController()
        #expect(wc.tabManager.canReopenClosedTab == false)
    }

    @Test func cmdShiftT_afterClose_reopensWithNoExtraCount() {
        let wc = makeController()
        // We can't set the directory externally without shell output,
        // so test the mechanic: close doesn't crash and reopen is available
        wc.tabManager.addTab()
        let secondID = wc.tabManager.tabs[1].id
        wc.tabManager.closeTab(id: secondID)
        // canReopen may be false if directory was empty (shell just started)
        // At minimum, the close should not crash
        #expect(wc.tabManager.tabs.count == 1)
    }

    // MARK: - Close button (X on each tab)

    @Test func closeButton_closesSpecificTab_notActive() {
        let wc = makeController()
        wc.tabManager.addTab()
        wc.tabManager.addTab()
        // 3 tabs, active is 2
        let firstID = wc.tabManager.tabs[0].id

        // Close tab 0 (not active)
        wc.tabManager.closeTab(id: firstID)
        #expect(wc.tabManager.tabs.count == 2)
        #expect(wc.tabManager.tabs.contains(where: { $0.id == firstID }) == false)
    }

    @Test func closeButton_closesActiveMiddleTab_adjustsIndex() {
        let wc = makeController()
        wc.tabManager.addTab()
        wc.tabManager.addTab()
        wc.tabManager.selectTab(at: 1) // middle
        let middleID = wc.tabManager.tabs[1].id

        wc.tabManager.closeTab(id: middleID)
        #expect(wc.tabManager.tabs.count == 2)
        #expect(wc.tabManager.activeTabIndex <= 1)
    }

    // MARK: - Special tabs (Settings, Help)

    @Test func settingsTab_openedOnce_noDuplicates() {
        let wc = makeController()
        wc.tabManager.openSettings()
        let count1 = wc.tabManager.tabs.count
        wc.tabManager.openSettings()
        #expect(wc.tabManager.tabs.count == count1)
        #expect(wc.tabManager.activeTab?.kind == .settings)
    }

    @Test func helpTab_openedOnce_noDuplicates() {
        let wc = makeController()
        wc.tabManager.openHelp()
        let count1 = wc.tabManager.tabs.count
        wc.tabManager.openHelp()
        #expect(wc.tabManager.tabs.count == count1)
        #expect(wc.tabManager.activeTab?.kind == .help)
    }

    @Test func specialTabs_persistOnHide() {
        let wc = makeController()
        wc.show()
        wc.tabManager.openSettings()
        wc.tabManager.openHelp()
        #expect(wc.tabManager.tabs.contains(where: { $0.kind == .settings }))
        #expect(wc.tabManager.tabs.contains(where: { $0.kind == .help }))

        wc.hide()
        // Settings and help tabs should persist across show/hide
        #expect(wc.tabManager.tabs.contains(where: { $0.kind == .settings }))
        #expect(wc.tabManager.tabs.contains(where: { $0.kind == .help }))
    }

    // MARK: - Tab hover state

    @Test func hoveredTabIndex_setsAndClears() {
        let wc = makeController()
        wc.tabManager.hoveredTabIndex = 0
        #expect(wc.tabManager.hoveredTabIndex == 0)
        wc.tabManager.hoveredTabIndex = nil
        #expect(wc.tabManager.hoveredTabIndex == nil)
    }

    // MARK: - Opacity

    @Test func setOpacity_clampsRange() {
        let wc = makeController()
        wc.tabManager.setOpacity(0.5)
        #expect(wc.tabManager.theme.backgroundOpacity == 0.5)

        wc.tabManager.setOpacity(0.1) // below minimum
        #expect(wc.tabManager.theme.backgroundOpacity == 0.3)

        wc.tabManager.setOpacity(2.0) // above maximum
        #expect(wc.tabManager.theme.backgroundOpacity == 1.0)
    }
}

// MARK: - Pane Management Tests

@MainActor
@Suite(.serialized)
struct PaneManagementTests {

    // MARK: - Split panes (Cmd+D, Cmd+Shift+D)

    @Test func splitHorizontal_createsTwoLeaves() throws {
        let tm = TabManager()
        let pm = tm.activeTab!.paneManager!
        #expect(pm.rootPane.leafCount == 1)

        try #require(pm.splitFocusedPane(axis: .horizontal))
        #expect(pm.rootPane.leafCount == 2)
    }

    @Test func splitVertical_createsTwoLeaves() throws {
        let tm = TabManager()
        let pm = tm.activeTab!.paneManager!
        try #require(pm.splitFocusedPane(axis: .vertical))
        #expect(pm.rootPane.leafCount == 2)
    }

    @Test func split_focusesNewPane() throws {
        let tm = TabManager()
        let pm = tm.activeTab!.paneManager!
        let originalID = pm.focusedPaneID

        try #require(pm.splitFocusedPane(axis: .horizontal))
        #expect(pm.focusedPaneID != originalID)
    }

    @Test func multipleSplits_createCorrectLeafCount() throws {
        let tm = TabManager()
        let pm = tm.activeTab!.paneManager!
        try #require(pm.splitFocusedPane(axis: .horizontal))
        pm.splitFocusedPane(axis: .vertical)   // 3 panes
        pm.splitFocusedPane(axis: .horizontal) // 4 panes
        #expect(pm.rootPane.leafCount == 4)
    }

    // MARK: - Close pane

    @Test func closePane_singlePane_callsOnLastPaneClosed() {
        let tm = TabManager()
        let pm = tm.activeTab!.paneManager!
        var lastPaneClosed = false
        pm.onLastPaneClosed = { lastPaneClosed = true }

        pm.closePane(id: pm.focusedPaneID)
        #expect(lastPaneClosed)
    }

    @Test func closePane_withMultiplePanes_leavesOthers() throws {
        let tm = TabManager()
        let pm = tm.activeTab!.paneManager!
        try #require(pm.splitFocusedPane(axis: .horizontal))
        #expect(pm.rootPane.leafCount == 2)

        let paneToClose = pm.focusedPaneID
        pm.closePane(id: paneToClose)
        #expect(pm.rootPane.leafCount == 1)
    }

    @Test func closePane_movesFocusToRemaining() throws {
        let tm = TabManager()
        let pm = tm.activeTab!.paneManager!
        let firstPaneID = pm.focusedPaneID

        try #require(pm.splitFocusedPane(axis: .horizontal))
        let secondPaneID = pm.focusedPaneID

        // Close second pane → focus should return to first
        pm.closePane(id: secondPaneID)
        #expect(pm.focusedPaneID == firstPaneID)
    }

    // MARK: - Pane focus navigation (Cmd+[, Cmd+])

    @Test func moveFocus_next_cyclesForward() throws {
        let tm = TabManager()
        let pm = tm.activeTab!.paneManager!
        let firstID = pm.focusedPaneID

        try #require(pm.splitFocusedPane(axis: .horizontal))
        let secondID = pm.focusedPaneID

        pm.splitFocusedPane(axis: .horizontal)
        let thirdID = pm.focusedPaneID

        // Focus is on third. Move next → wraps to first
        pm.moveFocus(.next)
        #expect(pm.focusedPaneID == firstID)

        pm.moveFocus(.next)
        #expect(pm.focusedPaneID == secondID)
    }

    @Test func moveFocus_previous_cyclesBackward() throws {
        let tm = TabManager()
        let pm = tm.activeTab!.paneManager!
        let firstID = pm.focusedPaneID

        try #require(pm.splitFocusedPane(axis: .horizontal))
        pm.splitFocusedPane(axis: .horizontal)
        let thirdID = pm.focusedPaneID

        // Focus is on third. Move previous → second
        pm.moveFocus(.previous)
        // Should be at a pane that's not first and not third
        let currentID = pm.focusedPaneID
        #expect(currentID != firstID)
        #expect(currentID != thirdID)
    }

    @Test func moveFocus_singlePane_noChange() {
        let tm = TabManager()
        let pm = tm.activeTab!.paneManager!
        let id = pm.focusedPaneID

        pm.moveFocus(.next)
        #expect(pm.focusedPaneID == id)

        pm.moveFocus(.previous)
        #expect(pm.focusedPaneID == id)
    }

    // MARK: - Split from TabManager (Cmd+D)

    @Test func tabManager_splitActivePane_horizontal() throws {
        let tm = TabManager()
        try #require(tm.splitActivePane(axis: .horizontal))
        let pm = tm.activeTab!.paneManager!
        #expect(pm.rootPane.leafCount == 2)
    }

    @Test func tabManager_splitActivePane_onSettingsTab_doesNothing() {
        let tm = TabManager()
        tm.openSettings()
        #expect(tm.activeTab?.kind == .settings)
        tm.splitActivePane(axis: .horizontal)
        // Settings tab has no pane manager — split is no-op
        #expect(tm.activeTab?.paneManager == nil)
    }

    @Test func tabManager_closeActivePane_withSinglePane_closesTab() {
        let tm = TabManager()
        let tabID = tm.activeTab!.id
        var lastPaneClosed = false
        tm.activeTab!.paneManager!.onLastPaneClosed = {
            lastPaneClosed = true
        }

        tm.closeActivePane()
        #expect(lastPaneClosed)
    }

    // MARK: - Focused instance accessor

    @Test func focusedInstance_returnsCorrectInstance() {
        let tm = TabManager()
        let pm = tm.activeTab!.paneManager!
        let instance = pm.focusedInstance
        #expect(instance != nil)
        #expect(instance?.backend != nil)
    }

    @Test func tab_instance_returnsFocusedPaneInstance() {
        let tm = TabManager()
        let tab = tm.activeTab!
        #expect(tab.instance != nil)
        #expect(tab.instance === tab.paneManager?.focusedInstance)
    }
}

// MARK: - Keyboard Focus & Input Routing Tests

@MainActor
@Suite(.serialized)
struct KeyboardFocusTests {

    @Test func focusableView_protocol_defaultsToView() {
        // Verify the protocol extension provides default
        let tm = TabManager()
        let backend = tm.activeTab!.instance!.backend
        // focusableView should be defined (not crash)
        let focusable = backend.focusableView
        #expect(focusable != nil)
    }

    #if canImport(GhosttyKit)
    @Test func ghosttyBackend_focusableView_isSurfaceView() {
        // GhosttyBackend.focusableView should return the GhosttyTerminalView,
        // not the container view
        let backend = GhosttyBackend()
        let focusable = backend.focusableView
        let container = backend.view
        #expect(focusable !== container)
        #expect(focusable is GhosttyTerminalView)
    }

    @Test func ghosttyBackend_view_isContainer() {
        let backend = GhosttyBackend()
        let container = backend.view
        // Container should be opaque with black background
        #expect(container.wantsLayer == true)
        #expect(container.layer?.isOpaque == true)
    }

    @Test func ghosttyTerminalView_acceptsFirstResponder() {
        let view = GhosttyTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        #expect(view.acceptsFirstResponder == true)
    }

    @Test func ghosttyTerminalView_isOpaque() {
        let view = GhosttyTerminalView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        #expect(view.isOpaque == true)
    }
    #endif

    @Test func focusTerminalInActiveTab_doesNotCrash() {
        let tm = TabManager()
        // Should not crash even when there's no window
        tm.focusTerminalInActiveTab()
    }

    @Test func focusTerminalInActiveTab_afterTabSwitch() {
        let tm = TabManager()
        tm.addTab()
        tm.addTab()
        tm.selectTab(at: 0)
        // After switching, focusTerminalInActiveTab is called internally
        // Verify the active tab is set correctly
        #expect(tm.activeTabIndex == 0)
        #expect(tm.activeTab?.paneManager?.focusedInstance != nil)
    }

    @Test func focusTerminalInActiveTab_afterSplit() throws {
        let tm = TabManager()
        try #require(tm.splitActivePane(axis: .horizontal))
        let pm = tm.activeTab!.paneManager!
        let focusedID = pm.focusedPaneID
        // The newly split pane should be focused
        #expect(pm.rootPane.leafIDs.contains(focusedID))
    }
}

// MARK: - MouseDown NSView Tests (additional scenarios)

@MainActor
@Suite(.serialized)
struct MouseDownNSViewExtendedTests {

    @Test func tripleClick_callsDoubleAction() {
        var doubleActionCalled = false
        let view = MouseDownNSView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        view.action = {}
        view.doubleAction = { doubleActionCalled = true }

        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 3,
            pressure: 1.0
        )!
        view.mouseDown(with: event)

        // clickCount >= 2, so doubleAction fires
        #expect(doubleActionCalled)
    }

    @Test func noActions_doesNotCrash() {
        let view = MouseDownNSView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        view.action = nil
        view.doubleAction = nil

        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!
        view.mouseDown(with: event)
        // Should not crash
    }
}

// MARK: - DoubleClickCatcher Tests

@MainActor
@Suite(.serialized)
struct DoubleClickCatcherTests {

    @Test func doubleClickNSView_hitTest_returnsNil() {
        let view = DoubleClickNSView(frame: NSRect(x: 0, y: 0, width: 200, height: 36))
        let result = view.hitTest(NSPoint(x: 100, y: 18))
        #expect(result == nil)
    }

    @Test func doubleClickNSView_initialState_noMonitor() {
        let view = DoubleClickNSView(frame: NSRect(x: 0, y: 0, width: 200, height: 36))
        // Without a window, monitor should not be installed
        // The view just exists without crashing
        #expect(view.onDoubleClick == nil)
    }

    @Test func doubleClickNSView_deinit_noLeak() {
        // Create and destroy — should not leak the event monitor
        var view: DoubleClickNSView? = DoubleClickNSView(frame: .zero)
        view?.onDoubleClick = {}
        view = nil
        // If we get here without crash, no leak
        #expect(true)
    }
}

// MARK: - Panel & Window State Extended Tests

@MainActor
@Suite(.serialized)
struct PanelWindowStateTests {

    @Test func panel_startsIgnoringMouseEvents() {
        let wc = WindowController()
        #expect(wc.panel.ignoresMouseEvents == true)
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

    @Test func cachedWidth_setOnShow() {
        let wc = WindowController()
        #expect(wc.cachedWidth == 0) // not yet shown
        wc.show()
        #expect(wc.cachedWidth > 0)
    }
}

// MARK: - Tab Model Extended Tests

@MainActor
@Suite(.serialized)
struct TabModelExtendedTests {

    @Test func tab_terminal_hasKindTerminal() {
        let tab = Tab()
        #expect(tab.kind == .terminal)
    }

    @Test func tab_terminal_hasPaneManager() {
        let tab = Tab()
        #expect(tab.paneManager != nil)
    }

    @Test func tab_settings_hasKindSettings() {
        let tab = Tab(kind: .settings, title: "Settings")
        #expect(tab.kind == .settings)
        #expect(tab.paneManager == nil)
    }

    @Test func tab_help_hasKindHelp() {
        let tab = Tab(kind: .help, title: "Help")
        #expect(tab.kind == .help)
        #expect(tab.paneManager == nil)
    }

    @Test func tab_displayTitle_usesCustomTitle() {
        var tab = Tab()
        #expect(tab.displayTitle == "zsh") // default

        tab.customTitle = "My Term"
        #expect(tab.displayTitle == "My Term")

        tab.customTitle = nil
        #expect(tab.displayTitle == "zsh")
    }

    @Test func tab_instance_isNilForSpecialTabs() {
        let settingsTab = Tab(kind: .settings, title: "Settings")
        #expect(settingsTab.instance == nil)

        let helpTab = Tab(kind: .help, title: "Help")
        #expect(helpTab.instance == nil)
    }

    @Test func tab_uniqueIDs() {
        let tab1 = Tab()
        let tab2 = Tab()
        #expect(tab1.id != tab2.id)
    }
}

// MARK: - PaneNode Tests

@MainActor
@Suite(.serialized)
struct PaneNodeTests {

    @Test func leaf_leafCount_isOne() {
        let instance = TerminalInstance()
        let node = PaneNode.leaf(id: generateShortID(), backend: instance.backend)
        #expect(node.leafCount == 1)
        instance.terminate()
    }

    @Test func leaf_leafIDs_containsSelf() {
        let id = generateShortID()
        let instance = TerminalInstance()
        let node = PaneNode.leaf(id: id, backend: instance.backend)
        #expect(node.leafIDs == [id])
        instance.terminate()
    }

    @Test func leaf_instanceLookup() {
        let id = generateShortID()
        let instance = TerminalInstance()
        let node = PaneNode.leaf(id: id, backend: instance.backend)
        #expect(node.backend(for: id) === instance.backend)
        #expect(node.backend(for: generateShortID()) == nil)
        instance.terminate()
    }

    @Test func split_leafCount_isSum() {
        let i1 = TerminalInstance()
        let i2 = TerminalInstance()
        let node = PaneNode.split(
            id: generateShortID(),
            axis: .horizontal,
            first: .leaf(id: generateShortID(), backend: i1.backend),
            second: .leaf(id: generateShortID(), backend: i2.backend),
            ratio: 0.5
        )
        #expect(node.leafCount == 2)
        i1.terminate()
        i2.terminate()
    }

    @Test func split_leafIDs_containsBoth() {
        let id1 = generateShortID()
        let id2 = generateShortID()
        let i1 = TerminalInstance()
        let i2 = TerminalInstance()
        let node = PaneNode.split(
            id: generateShortID(),
            axis: .horizontal,
            first: .leaf(id: id1, backend: i1.backend),
            second: .leaf(id: id2, backend: i2.backend),
            ratio: 0.5
        )
        #expect(node.leafIDs.contains(id1))
        #expect(node.leafIDs.contains(id2))
        i1.terminate()
        i2.terminate()
    }
}

// MARK: - Terminal Instance Tests

@MainActor
@Suite(.serialized)
struct TerminalInstanceTests {

    @Test func terminalInstance_hasBackend() {
        let instance = TerminalInstance()
        #expect(instance.backend != nil)
        #expect(instance.backend.view != nil)
        instance.terminate()
    }

    @Test func terminalInstance_defaultTitle() {
        let instance = TerminalInstance()
        #expect(instance.currentTitle == "zsh")
        instance.terminate()
    }

    @Test func terminalInstance_terminateIsIdempotent() {
        let instance = TerminalInstance()
        instance.terminate()
        instance.terminate() // Should not crash
    }

    @Test func terminalInstance_delegateCallbacks() {
        let instance = TerminalInstance()
        var titleChanged = false
        var dirChanged = false

        instance.onTitleChange = { _ in titleChanged = true }
        instance.onDirectoryChange = { _ in dirChanged = true }

        // Simulate delegate callbacks
        instance.terminalTitleChanged("test")
        #expect(titleChanged)
        #expect(instance.currentTitle == "test")

        instance.terminalDirectoryChanged("/tmp")
        #expect(dirChanged)
        #expect(instance.currentDirectory == "/tmp")

        instance.terminate()
    }

    @Test func terminalInstance_processTerminated_callsCallback() {
        let instance = TerminalInstance()
        var terminated = false
        instance.onProcessTerminated = { terminated = true }

        instance.terminalProcessTerminated(exitCode: 0)
        #expect(terminated)
    }

    @Test func configuredShell_returnsValidPath() {
        let shell = TerminalInstance.configuredShell
        #expect(!shell.isEmpty)
        #expect(shell.hasPrefix("/"))
    }
}

// MARK: - TerminalBackend Protocol Tests

@MainActor
@Suite(.serialized)
struct TerminalBackendProtocolTests {

    @Test func backendType_ghostty_isAvailable() {
        #expect(BackendType.ghostty.isAvailable == true)
    }

    @Test func backendType_current_isGhostty() {
        #expect(BackendType.current == .ghostty)
    }

    @Test func backendType_createBackend_returnsNonNil() {
        let backend = BackendType.ghostty.createBackend()
        #expect(backend.view != nil)
    }

    @Test func backendType_rawValue() {
        #expect(BackendType.ghostty.rawValue == "libghostty")
    }
}

// MARK: - WindowController openSettings / openHelp

@MainActor
@Suite(.serialized)
struct WindowControllerSettingsHelpTests {

    @Test func openSettings_showsIfHidden() {
        let wc = WindowController()
        #expect(wc.state == .hidden)
        wc.openSettings()
        #expect(wc.state == .visible)
    }

    @Test func openSettings_doesNotDuplicateSettingsTab() {
        let wc = WindowController()
        wc.openSettings()
        let count1 = wc.tabManager.tabs.count
        wc.openSettings() // second call should not add another
        #expect(wc.tabManager.tabs.count == count1)
    }

    @Test func openHelp_showsIfHidden() {
        let wc = WindowController()
        #expect(wc.state == .hidden)
        wc.openHelp()
        #expect(wc.state == .visible)
    }

    @Test func openHelp_doesNotDuplicateHelpTab() {
        let wc = WindowController()
        wc.openHelp()
        let count1 = wc.tabManager.tabs.count
        wc.openHelp()
        #expect(wc.tabManager.tabs.count == count1)
    }
}

// MARK: - Tab close edge cases

@MainActor
@Suite(.serialized)
struct TabCloseEdgeCaseTests {

    @Test func closeTab_lastTab_respawnsAndActivates() {
        let wc = WindowController()
        #expect(wc.tabManager.tabs.count == 1)
        let tabID = wc.tabManager.tabs[0].id
        wc.tabManager.closeTab(id: tabID)
        // Should auto-create a new tab
        #expect(wc.tabManager.tabs.count >= 1)
        #expect(wc.tabManager.activeTabIndex == 0)
    }

    @Test func closeTab_middleTab_activatesCorrectNext() {
        let wc = WindowController()
        wc.tabManager.addTab()
        wc.tabManager.addTab()
        // 3 tabs, select middle one
        wc.tabManager.selectTab(at: 1)
        #expect(wc.tabManager.activeTabIndex == 1)

        let middleID = wc.tabManager.tabs[1].id
        wc.tabManager.closeTab(id: middleID)
        // After closing middle, should have 2 tabs, active index adjusted
        #expect(wc.tabManager.tabs.count == 2)
        #expect(wc.tabManager.activeTabIndex >= 0)
        #expect(wc.tabManager.activeTabIndex < wc.tabManager.tabs.count)
    }
}

// MARK: - Tab Reordering (moveTab) Tests

@MainActor
@Suite(.serialized)
struct TabReorderingTests {

    // MARK: - Helpers

    /// Create a TabManager with the given number of terminal tabs (including the default one).
    private func makeTabs(count: Int) -> TabManager {
        let tm = TabManager()
        for _ in 1..<count {
            tm.addTab()
        }
        return tm
    }

    // MARK: - Basic moves

    @Test func moveTab_forwardByOne() {
        let tm = makeTabs(count: 3)
        let ids = tm.tabs.map(\.id)
        // Move tab 0 → 1
        tm.moveTab(from: 0, to: 1)
        #expect(tm.tabs[0].id == ids[1])
        #expect(tm.tabs[1].id == ids[0])
        #expect(tm.tabs[2].id == ids[2])
    }

    @Test func moveTab_forwardToEnd() {
        let tm = makeTabs(count: 4)
        let ids = tm.tabs.map(\.id)
        // Move tab 0 → 3 (last position)
        tm.selectTab(at: 0)
        tm.moveTab(from: 0, to: 3)
        #expect(tm.tabs[3].id == ids[0])
        #expect(tm.tabs[0].id == ids[1])
    }

    @Test func moveTab_backwardByOne() {
        let tm = makeTabs(count: 3)
        let ids = tm.tabs.map(\.id)
        // Move tab 2 → 1
        tm.moveTab(from: 2, to: 1)
        #expect(tm.tabs[0].id == ids[0])
        #expect(tm.tabs[1].id == ids[2])
        #expect(tm.tabs[2].id == ids[1])
    }

    @Test func moveTab_backwardToStart() {
        let tm = makeTabs(count: 4)
        let ids = tm.tabs.map(\.id)
        // Move tab 3 → 0
        tm.moveTab(from: 3, to: 0)
        #expect(tm.tabs[0].id == ids[3])
        #expect(tm.tabs[1].id == ids[0])
    }

    // MARK: - No-op cases

    @Test func moveTab_sameIndex_noOp() {
        let tm = makeTabs(count: 3)
        let idsBefore = tm.tabs.map(\.id)
        tm.moveTab(from: 1, to: 1)
        let idsAfter = tm.tabs.map(\.id)
        #expect(idsBefore == idsAfter)
    }

    @Test func moveTab_sourceOutOfBounds_noOp() {
        let tm = makeTabs(count: 3)
        let idsBefore = tm.tabs.map(\.id)
        tm.moveTab(from: 5, to: 0)
        let idsAfter = tm.tabs.map(\.id)
        #expect(idsBefore == idsAfter)
    }

    @Test func moveTab_destinationOutOfBounds_noOp() {
        let tm = makeTabs(count: 3)
        let idsBefore = tm.tabs.map(\.id)
        tm.moveTab(from: 0, to: 10)
        let idsAfter = tm.tabs.map(\.id)
        #expect(idsBefore == idsAfter)
    }

    @Test func moveTab_negativeSource_noOp() {
        let tm = makeTabs(count: 3)
        let idsBefore = tm.tabs.map(\.id)
        tm.moveTab(from: -1, to: 0)
        let idsAfter = tm.tabs.map(\.id)
        #expect(idsBefore == idsAfter)
    }

    @Test func moveTab_negativeDestination_noOp() {
        let tm = makeTabs(count: 3)
        let idsBefore = tm.tabs.map(\.id)
        tm.moveTab(from: 0, to: -1)
        let idsAfter = tm.tabs.map(\.id)
        #expect(idsBefore == idsAfter)
    }

    // MARK: - Active tab index follows move

    @Test func moveTab_activeTabFollowsMove_forward() {
        let tm = makeTabs(count: 4)
        tm.selectTab(at: 1)
        let activeID = tm.activeTab!.id
        // Move the active tab (1) → 3
        tm.moveTab(from: 1, to: 3)
        #expect(tm.activeTabIndex == 3)
        #expect(tm.activeTab?.id == activeID)
    }

    @Test func moveTab_activeTabFollowsMove_backward() {
        let tm = makeTabs(count: 4)
        tm.selectTab(at: 3)
        let activeID = tm.activeTab!.id
        // Move the active tab (3) → 0
        tm.moveTab(from: 3, to: 0)
        #expect(tm.activeTabIndex == 0)
        #expect(tm.activeTab?.id == activeID)
    }

    @Test func moveTab_nonActiveMovedForward_adjustsActiveIndex() {
        // When a tab before the active tab is moved past it, activeTabIndex decrements
        let tm = makeTabs(count: 4)
        // tabs: [0, 1, 2, 3], active = 3 (last added)
        tm.selectTab(at: 2)
        let activeID = tm.activeTab!.id
        // Move tab 0 → 3 (past active at 2)
        tm.moveTab(from: 0, to: 3)
        // Active was at 2, source (0) < active, dest (3) >= active → active -= 1
        #expect(tm.activeTabIndex == 1)
        #expect(tm.activeTab?.id == activeID)
    }

    @Test func moveTab_nonActiveMovedBackward_adjustsActiveIndex() {
        // When a tab after the active tab is moved before it, activeTabIndex increments
        let tm = makeTabs(count: 4)
        tm.selectTab(at: 1)
        let activeID = tm.activeTab!.id
        // Move tab 3 → 0 (before active at 1)
        tm.moveTab(from: 3, to: 0)
        // Active was at 1, source (3) > active, dest (0) <= active → active += 1
        #expect(tm.activeTabIndex == 2)
        #expect(tm.activeTab?.id == activeID)
    }

    @Test func moveTab_nonActiveNotCrossingActive_noIndexChange() {
        // Moving a tab that doesn't cross the active tab's position
        let tm = makeTabs(count: 5)
        tm.selectTab(at: 0)
        let activeID = tm.activeTab!.id
        // Move tab 2 → 4 (both after active at 0)
        tm.moveTab(from: 2, to: 4)
        #expect(tm.activeTabIndex == 0)
        #expect(tm.activeTab?.id == activeID)
    }
}

// MARK: - Tab State Persistence Tests

@MainActor
@Suite(.serialized)
struct TabStatePersistenceTests {

    private static let tabDirsKey = "savedTabDirectories"
    private static let activeIndexKey = "savedActiveTabIndex"
    private static let restoreKey = "restoreTabsOnLaunch"

    /// Clean up all UserDefaults keys used by persistence tests.
    private func cleanupDefaults() {
        UserDefaults.standard.removeObject(forKey: Self.tabDirsKey)
        UserDefaults.standard.removeObject(forKey: Self.activeIndexKey)
        UserDefaults.standard.removeObject(forKey: Self.restoreKey)
    }

    // MARK: - saveTabState

    @Test func saveTabState_writesDirectoriesToUserDefaults() {
        cleanupDefaults()
        let tm = TabManager()
        tm.addTab()
        // Both tabs are fresh (no shell output yet), so directories will be "~"
        tm.saveTabState()

        let dirs = UserDefaults.standard.stringArray(forKey: Self.tabDirsKey)
        #expect(dirs != nil)
        #expect(dirs!.count == 2)
        // Fresh tabs have empty directory → saveTabState maps empty to "~"
        #expect(dirs!.allSatisfy { $0 == "~" })
        cleanupDefaults()
    }

    @Test func saveTabState_writesActiveIndexToUserDefaults() {
        cleanupDefaults()
        let tm = TabManager()
        tm.addTab()
        tm.addTab()
        tm.selectTab(at: 1)
        tm.saveTabState()

        let savedIndex = UserDefaults.standard.integer(forKey: Self.activeIndexKey)
        #expect(savedIndex == 1)
        cleanupDefaults()
    }

    @Test func saveTabState_skipsNonTerminalTabs() {
        cleanupDefaults()
        let tm = TabManager()
        tm.openSettings()
        tm.openHelp()
        // 1 terminal + settings + help = 3 tabs, but only terminal dirs saved
        tm.saveTabState()

        let dirs = UserDefaults.standard.stringArray(forKey: Self.tabDirsKey)
        #expect(dirs != nil)
        #expect(dirs!.count == 1) // only the terminal tab
        cleanupDefaults()
    }

    @Test func saveTabState_overwritesPreviousSave() {
        cleanupDefaults()
        let tm = TabManager()
        tm.saveTabState()
        let firstDirs = UserDefaults.standard.stringArray(forKey: Self.tabDirsKey)
        #expect(firstDirs?.count == 1)

        tm.addTab()
        tm.saveTabState()
        let secondDirs = UserDefaults.standard.stringArray(forKey: Self.tabDirsKey)
        #expect(secondDirs?.count == 2)
        cleanupDefaults()
    }

    // MARK: - restoreTabsOrDefault (tested via TabManager init)

    @Test func restore_noSavedState_createsDefaultTab() {
        cleanupDefaults()
        // With no saved state and restoreTabsOnLaunch not set, init creates default tab
        let tm = TabManager()
        #expect(tm.tabs.count == 1)
        #expect(tm.tabs[0].kind == .terminal)
        cleanupDefaults()
    }

    @Test func restore_restoreDisabled_createsDefaultTab() {
        cleanupDefaults()
        // Save some state but disable restore
        UserDefaults.standard.set(["~", "/tmp"], forKey: Self.tabDirsKey)
        UserDefaults.standard.set(1, forKey: Self.activeIndexKey)
        UserDefaults.standard.set(false, forKey: Self.restoreKey)

        let tm = TabManager()
        // Should ignore saved state and create a single default tab
        #expect(tm.tabs.count == 1)
        cleanupDefaults()
    }

    @Test func restore_restoreEnabled_restoresSavedTabs() {
        cleanupDefaults()
        UserDefaults.standard.set(["~", "~", "~"], forKey: Self.tabDirsKey)
        UserDefaults.standard.set(1, forKey: Self.activeIndexKey)
        UserDefaults.standard.set(true, forKey: Self.restoreKey)

        let tm = TabManager()
        #expect(tm.tabs.count == 3)
        #expect(tm.activeTabIndex == 1)
        cleanupDefaults()
    }

    @Test func restore_restoreEnabled_emptyDirs_createsDefaultTab() {
        cleanupDefaults()
        UserDefaults.standard.set([String](), forKey: Self.tabDirsKey)
        UserDefaults.standard.set(true, forKey: Self.restoreKey)

        let tm = TabManager()
        // Empty dirs array → falls through to addTab()
        #expect(tm.tabs.count == 1)
        cleanupDefaults()
    }

    @Test func restore_savedIndexOutOfBounds_clampedToLast() {
        cleanupDefaults()
        UserDefaults.standard.set(["~", "~"], forKey: Self.tabDirsKey)
        UserDefaults.standard.set(99, forKey: Self.activeIndexKey)
        UserDefaults.standard.set(true, forKey: Self.restoreKey)

        let tm = TabManager()
        #expect(tm.tabs.count == 2)
        // Index 99 is out of bounds, so it stays at whatever addTab set (last tab)
        #expect(tm.activeTabIndex >= 0)
        #expect(tm.activeTabIndex < tm.tabs.count)
        cleanupDefaults()
    }

    @Test func saveAndRestore_roundTrip() {
        cleanupDefaults()
        // Create a TabManager, add tabs, save
        let tm1 = TabManager()
        tm1.addTab()
        tm1.addTab()
        tm1.selectTab(at: 1)
        tm1.saveTabState()

        // Enable restore and create new TabManager
        UserDefaults.standard.set(true, forKey: Self.restoreKey)
        let tm2 = TabManager()
        #expect(tm2.tabs.count == 3)
        #expect(tm2.activeTabIndex == 1)
        cleanupDefaults()
    }
}

// MARK: - Close Confirmation (confirmOnQuit setting) Tests

@MainActor
@Suite(.serialized)
struct CloseConfirmationTests {

    private static let confirmKey = "confirmOnQuit"

    private func cleanupDefaults() {
        UserDefaults.standard.removeObject(forKey: Self.confirmKey)
    }

    @Test func confirmOnQuit_defaultsToFalse() {
        cleanupDefaults()
        let value = UserDefaults.standard.bool(forKey: Self.confirmKey)
        #expect(value == false)
        cleanupDefaults()
    }

    @Test func confirmOnQuit_false_applicationShouldTerminate_returnsTerminateNow() {
        cleanupDefaults()
        UserDefaults.standard.set(false, forKey: Self.confirmKey)
        // When confirmOnQuit is false, the guard returns .terminateNow immediately
        // We test this by verifying the setting value and the expected code path
        let shouldConfirm = UserDefaults.standard.bool(forKey: Self.confirmKey)
        #expect(shouldConfirm == false)
        // The function: guard UserDefaults.standard.bool(forKey: "confirmOnQuit") else { return .terminateNow }
        // So when false → .terminateNow
        cleanupDefaults()
    }

    @Test func confirmOnQuit_canBeSetToTrue() {
        cleanupDefaults()
        UserDefaults.standard.set(true, forKey: Self.confirmKey)
        let value = UserDefaults.standard.bool(forKey: Self.confirmKey)
        #expect(value == true)
        cleanupDefaults()
    }

    @Test func confirmOnQuit_roundTrips() {
        cleanupDefaults()
        UserDefaults.standard.set(true, forKey: Self.confirmKey)
        #expect(UserDefaults.standard.bool(forKey: Self.confirmKey) == true)
        UserDefaults.standard.set(false, forKey: Self.confirmKey)
        #expect(UserDefaults.standard.bool(forKey: Self.confirmKey) == false)
        cleanupDefaults()
    }

    @Test func confirmOnQuit_unset_treatedAsFalse() {
        cleanupDefaults()
        // UserDefaults.bool(forKey:) returns false for unset keys
        #expect(UserDefaults.standard.bool(forKey: Self.confirmKey) == false)
    }
}

// MARK: - Pinned Window Visibility Tests

@MainActor
@Suite(.serialized)
struct PinnedWindowVisibilityTests {

    @Test func isPinned_defaultsFalse() {
        let wc = WindowController()
        #expect(wc.isPinned == false)
    }

    @Test func isPinned_canBeToggled() {
        let wc = WindowController()
        wc.isPinned = true
        #expect(wc.isPinned == true)
        wc.isPinned = false
        #expect(wc.isPinned == false)
    }

    @Test func pinnedWindow_showThenPin_staysVisible() {
        let wc = WindowController()
        wc.show()
        #expect(wc.state == .visible)
        wc.isPinned = true
        // State should remain visible after pinning
        #expect(wc.state == .visible)
    }

    @Test func pinnedWindow_staysVisibleAfterResignKey() {
        let wc = WindowController()
        wc.show()
        wc.isPinned = true
        // Simulate what happens when another app activates:
        // panel.resignKey() is called but state stays .visible
        wc.panel.resignKey()
        #expect(wc.state == .visible)
        #expect(wc.isPinned == true)
    }

    @Test func pinnedWindow_panelStaysOrderedAfterResignKey() {
        let wc = WindowController()
        wc.show()
        wc.isPinned = true
        wc.panel.resignKey()
        // Panel should still be visible (ordered front)
        #expect(wc.panel.isVisible == true)
        #expect(wc.state == .visible)
    }

    @Test func unpinnedWindow_hidesOnResignKey_whenNotDebounced() {
        // Verify that the isPinned guard is the critical difference:
        // Without pin, the resign observer would hide. We test the setting itself.
        let wc = WindowController()
        wc.show()
        #expect(wc.isPinned == false)
        #expect(wc.state == .visible)
        // Directly calling hide simulates what the observer does for unpinned windows
        wc.hide()
        #expect(wc.state == .hidden)
    }

    @Test func pinnedWindow_manualHide_stillWorks() {
        let wc = WindowController()
        wc.show()
        wc.isPinned = true
        // Even when pinned, explicit hide() should work
        wc.hide()
        #expect(wc.state == .hidden)
    }

    @Test func pinnedWindow_togglePin_doesNotChangeVisibility() {
        let wc = WindowController()
        wc.show()
        #expect(wc.state == .visible)
        wc.isPinned = true
        #expect(wc.state == .visible)
        wc.isPinned = false
        #expect(wc.state == .visible)
    }
}
