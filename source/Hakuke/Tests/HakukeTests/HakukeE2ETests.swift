import Testing
import AppKit
@testable import Hakuke

/// End-to-end tests that exercise the app's major flows through the real
/// WindowController — show/hide lifecycle, tab management, resizing,
/// pin toggle, and settings/help window opening.
///
/// These tests create actual AppKit windows and panels, so they require
/// a macOS environment with a display (CI must use a virtual framebuffer).
@MainActor
@Suite(.serialized)
struct HakukeE2ETests {

    // MARK: - Helpers

    /// Create a fresh WindowController for each test.
    /// We don't keep it as a stored property because `@Suite` structs
    /// create a new instance per test method anyway.
    private func makeController() -> WindowController {
        WindowController()
    }

    // MARK: - 1. Show / Hide lifecycle

    @Test func toggle_fromHidden_showsPanel() {
        let wc = makeController()
        #expect(wc.state == .hidden)

        wc.toggle()
        #expect(wc.state == .visible)
    }

    @Test func toggle_fromVisible_hidesPanel() {
        let wc = makeController()
        wc.show()
        #expect(wc.state == .visible)

        wc.toggle()
        #expect(wc.state == .hidden)
    }

    @Test func show_whenAlreadyVisible_isNoOp() {
        let wc = makeController()
        wc.show()
        #expect(wc.state == .visible)

        wc.show()
        #expect(wc.state == .visible)
    }

    @Test func hide_whenAlreadyHidden_isNoOp() {
        let wc = makeController()
        #expect(wc.state == .hidden)

        wc.hide()
        #expect(wc.state == .hidden)
    }

    @Test func show_makesPanel_acceptMouseEvents() {
        let wc = makeController()
        // Panel starts ignoring mouse events (set in init)
        #expect(wc.panel.ignoresMouseEvents == true)

        wc.show()
        #expect(wc.panel.ignoresMouseEvents == false)
    }

    @Test func hide_makesPanel_ignoreMouseEvents() {
        let wc = makeController()
        wc.show()
        wc.hide()
        #expect(wc.panel.ignoresMouseEvents == true)
    }

    @Test func doubleToggle_returnsToHidden() {
        let wc = makeController()
        #expect(wc.state == .hidden)

        wc.toggle()
        #expect(wc.state == .visible)

        wc.toggle()
        #expect(wc.state == .hidden)
    }

    @Test func tripleToggle_endsVisible() {
        let wc = makeController()
        wc.toggle()
        wc.toggle()
        wc.toggle()
        #expect(wc.state == .visible)
    }

    // MARK: - 2. Tab lifecycle: create -> switch -> close -> reopen

    @Test func newController_hasOneTab() {
        let wc = makeController()
        #expect(wc.tabManager.tabs.count == 1)
        #expect(wc.tabManager.activeTabIndex == 0)
    }

    @Test func tabLifecycle_addSwitchCloseReopen() {
        let wc = makeController()

        // Start with 1 tab
        #expect(wc.tabManager.tabs.count == 1)
        let firstTabID = wc.tabManager.tabs[0].id

        // Add a second tab → automatically becomes active
        wc.tabManager.addTab()
        #expect(wc.tabManager.tabs.count == 2)
        #expect(wc.tabManager.activeTabIndex == 1)
        let secondTabID = wc.tabManager.tabs[1].id

        // Switch back to first tab
        wc.tabManager.selectTab(at: 0)
        #expect(wc.tabManager.activeTabIndex == 0)
        #expect(wc.tabManager.activeTab?.id == firstTabID)

        // Close the second tab
        wc.tabManager.closeTab(id: secondTabID)
        #expect(wc.tabManager.tabs.count == 1)
        #expect(wc.tabManager.tabs[0].id == firstTabID)

        // Close the last remaining tab — a new one should be auto-created
        wc.tabManager.closeTab(id: firstTabID)
        #expect(wc.tabManager.tabs.count == 1)
        #expect(wc.tabManager.tabs[0].id != firstTabID)
    }

    @Test func tabNavigation_nextAndPrevious_withMultipleTabs() {
        let wc = makeController()
        wc.tabManager.addTab()
        wc.tabManager.addTab()
        // 3 tabs: indices 0, 1, 2 — active is 2
        #expect(wc.tabManager.tabs.count == 3)
        #expect(wc.tabManager.activeTabIndex == 2)

        // Next wraps to 0
        wc.tabManager.selectNextTab()
        #expect(wc.tabManager.activeTabIndex == 0)

        // Previous wraps to 2
        wc.tabManager.selectPreviousTab()
        #expect(wc.tabManager.activeTabIndex == 2)

        // Previous goes to 1
        wc.tabManager.selectPreviousTab()
        #expect(wc.tabManager.activeTabIndex == 1)
    }

    @Test func tabLifecycle_multipleClosesRespawnSingleTab() {
        let wc = makeController()
        // Add 3 more tabs (total 4)
        wc.tabManager.addTab()
        wc.tabManager.addTab()
        wc.tabManager.addTab()
        #expect(wc.tabManager.tabs.count == 4)

        // Close all tabs one by one from the end
        while wc.tabManager.tabs.count > 1 {
            let lastID = wc.tabManager.tabs.last!.id
            wc.tabManager.closeTab(id: lastID)
        }
        // Close the very last one — auto-respawn
        let finalID = wc.tabManager.tabs[0].id
        wc.tabManager.closeTab(id: finalID)
        #expect(wc.tabManager.tabs.count == 1)
        #expect(wc.tabManager.activeTabIndex == 0)
    }

    // MARK: - 3. Resize methods

    @Test func setWidthPercent_clampsToValidRange() {
        let wc = makeController()

        wc.setWidthPercent(50)
        #expect(wc.widthPercent == 50)

        // Below minimum (30)
        wc.setWidthPercent(10)
        #expect(wc.widthPercent == 30)

        // Above maximum (100)
        wc.setWidthPercent(120)
        #expect(wc.widthPercent == 100)

        // Exact boundaries
        wc.setWidthPercent(30)
        #expect(wc.widthPercent == 30)
        wc.setWidthPercent(100)
        #expect(wc.widthPercent == 100)
    }

    @Test func setHeightPercent_clampsToValidRange() {
        let wc = makeController()

        wc.setHeightPercent(60)
        #expect(wc.heightPercent == 60)

        // Below minimum (20)
        wc.setHeightPercent(5)
        #expect(wc.heightPercent == 20)

        // Above maximum (90)
        wc.setHeightPercent(95)
        #expect(wc.heightPercent == 90)

        // Exact boundaries
        wc.setHeightPercent(20)
        #expect(wc.heightPercent == 20)
        wc.setHeightPercent(90)
        #expect(wc.heightPercent == 90)
    }

    @Test func updateHeightByDelta_convertsPixelsToPercent() {
        let wc = makeController()
        let screenHeight = wc.resolvedScreen.frame.height

        // Set height to half the screen in pixels
        let halfScreenPixels = screenHeight / 2
        wc.updateHeightByDelta(halfScreenPixels)
        #expect(wc.heightPercent == 50)
    }

    @Test func updateHeightByDelta_clampsExtremes() {
        let wc = makeController()
        let screenHeight = wc.resolvedScreen.frame.height

        // Very small → clamps to 20%
        wc.updateHeightByDelta(10)
        #expect(wc.heightPercent == 20)

        // Very large → clamps to 90%
        wc.updateHeightByDelta(screenHeight * 2)
        #expect(wc.heightPercent == 90)
    }

    @Test func updateWidthByDelta_convertsPixelsToPercent() {
        let wc = makeController()
        let screenWidth = wc.resolvedScreen.frame.width

        // Set width to 75% of screen in pixels
        let seventyFivePercent = screenWidth * 0.75
        wc.updateWidthByDelta(seventyFivePercent)
        #expect(wc.widthPercent == 75)
    }

    @Test func updateWidthByDelta_clampsExtremes() {
        let wc = makeController()
        let screenWidth = wc.resolvedScreen.frame.width

        // Very small → clamps to 30%
        wc.updateWidthByDelta(10)
        #expect(wc.widthPercent == 30)

        // Very large → clamps to 100%
        wc.updateWidthByDelta(screenWidth * 3)
        #expect(wc.widthPercent == 100)
    }

    @Test func terminalSize_reflectsPercentages() {
        let wc = makeController()
        let screen = wc.resolvedScreen.frame

        wc.setWidthPercent(50)
        wc.setHeightPercent(40)

        let expectedWidth = max(screen.width * 0.50, 300)
        let expectedHeight = max(screen.height * 0.40, 150)

        #expect(wc.terminalSize.width == expectedWidth)
        #expect(wc.terminalSize.height == expectedHeight)
    }

    @Test func terminalSize_respectsMinimumDimensions() {
        let wc = makeController()

        // Set to minimum percentages
        wc.setWidthPercent(30)
        wc.setHeightPercent(20)

        // Width should be at least 300, height at least 150
        #expect(wc.terminalSize.width >= 300)
        #expect(wc.terminalSize.height >= 150)
    }

    // MARK: - 4. Pin toggle

    @Test func isPinned_initiallyFalse() {
        let wc = makeController()
        #expect(wc.isPinned == false)
    }

    @Test func isPinned_togglesCorrectly() {
        let wc = makeController()

        wc.isPinned = true
        #expect(wc.isPinned == true)

        wc.isPinned = false
        #expect(wc.isPinned == false)
    }

    @Test func pinned_preventsHideOnToggle_whenVisible() {
        // When pinned, the panel should still respond to explicit toggle()
        // (pin only prevents auto-hide from focus loss, not manual toggle)
        let wc = makeController()
        wc.show()
        wc.isPinned = true

        // Manual toggle should still work even when pinned
        wc.toggle()
        #expect(wc.state == .hidden)
    }

    @Test func pinned_showThenHide_stateTransitionsCorrectly() {
        let wc = makeController()
        wc.isPinned = true

        wc.show()
        #expect(wc.state == .visible)
        #expect(wc.isPinned == true)

        wc.hide()
        #expect(wc.state == .hidden)
    }

    // MARK: - 5. Settings and Help (as tabs)

    @Test func openSettings_createsSettingsTab() {
        let wc = makeController()
        let initialCount = wc.tabManager.tabs.count
        wc.openSettings()

        #expect(wc.tabManager.tabs.count == initialCount + 1)
        #expect(wc.tabManager.activeTab?.kind == .settings)
        #expect(wc.tabManager.activeTab?.title == "Settings")
    }

    @Test func openSettings_calledTwice_reusesTab() {
        let wc = makeController()
        wc.openSettings()
        let countAfterFirst = wc.tabManager.tabs.count

        wc.openSettings()
        #expect(wc.tabManager.tabs.count == countAfterFirst)
        #expect(wc.tabManager.activeTab?.kind == .settings)
    }

    @Test func openHelp_createsHelpTab() {
        let wc = makeController()
        let initialCount = wc.tabManager.tabs.count
        wc.openHelp()

        #expect(wc.tabManager.tabs.count == initialCount + 1)
        #expect(wc.tabManager.activeTab?.kind == .help)
        #expect(wc.tabManager.activeTab?.title == "Help")
    }

    @Test func openHelp_calledTwice_reusesTab() {
        let wc = makeController()
        wc.openHelp()
        let countAfterFirst = wc.tabManager.tabs.count

        wc.openHelp()
        #expect(wc.tabManager.tabs.count == countAfterFirst)
        #expect(wc.tabManager.activeTab?.kind == .help)
    }

    // MARK: - 6. Display ID

    @Test func setDisplayID_updatesProperty() {
        let wc = makeController()
        #expect(wc.displayID == 0) // default: auto (follow cursor)

        wc.setDisplayID(42)
        #expect(wc.displayID == 42)

        wc.setDisplayID(0)
        #expect(wc.displayID == 0)
    }

    // MARK: - 7. Panel configuration

    @Test func panel_isCorrectType() {
        let wc = makeController()
        #expect(wc.panel is TerminalPanel)
    }

    @Test func panel_canBecomeKey() {
        let wc = makeController()
        #expect(wc.panel.canBecomeKey == true)
    }

    @Test func panel_cannotBecomeMain() {
        let wc = makeController()
        #expect(wc.panel.canBecomeMain == false)
    }

    @Test func panel_isNotOpaque() {
        let wc = makeController()
        #expect(wc.panel.isOpaque == false)
    }

    @Test func panel_hasNoShadow() {
        let wc = makeController()
        #expect(wc.panel.hasShadow == false)
    }

    @Test func panel_isNotMovable() {
        let wc = makeController()
        #expect(wc.panel.isMovable == false)
    }

    // MARK: - 8. Combined flow: show, create tabs, resize, pin, hide

    @Test func fullFlow_showTabsResizePinHide() {
        let wc = makeController()

        // 1. Show the terminal
        wc.show()
        #expect(wc.state == .visible)
        #expect(wc.tabManager.tabs.count == 1)

        // 2. Add two more tabs
        wc.tabManager.addTab()
        wc.tabManager.addTab()
        #expect(wc.tabManager.tabs.count == 3)
        #expect(wc.tabManager.activeTabIndex == 2)

        // 3. Switch to first tab
        wc.tabManager.selectTab(at: 0)
        #expect(wc.tabManager.activeTabIndex == 0)

        // 4. Resize
        wc.setWidthPercent(80)
        wc.setHeightPercent(60)
        #expect(wc.widthPercent == 80)
        #expect(wc.heightPercent == 60)

        // 5. Pin
        wc.isPinned = true
        #expect(wc.isPinned == true)

        // 6. Close middle tab
        let middleTabID = wc.tabManager.tabs[1].id
        wc.tabManager.closeTab(id: middleTabID)
        #expect(wc.tabManager.tabs.count == 2)

        // 7. Hide (should work even when pinned via explicit hide())
        wc.hide()
        #expect(wc.state == .hidden)

        // 8. Unpin and show again
        wc.isPinned = false
        wc.show()
        #expect(wc.state == .visible)
        #expect(wc.isPinned == false)

        // Clean up
        wc.hide()
    }

    @Test func fullFlow_rapidToggle() {
        let wc = makeController()

        // Rapid toggles should leave state consistent
        for _ in 0..<10 {
            wc.toggle()
        }
        // 10 toggles = 5 show + 5 hide = hidden
        #expect(wc.state == .hidden)
    }

    @Test func fullFlow_resizeThenTogglePreservesSize() {
        let wc = makeController()

        wc.setWidthPercent(60)
        wc.setHeightPercent(45)

        wc.show()
        #expect(wc.widthPercent == 60)
        #expect(wc.heightPercent == 45)

        wc.hide()
        #expect(wc.widthPercent == 60)
        #expect(wc.heightPercent == 45)

        // Show again — sizes should be preserved
        wc.show()
        #expect(wc.widthPercent == 60)
        #expect(wc.heightPercent == 45)

        wc.hide()
    }
}
