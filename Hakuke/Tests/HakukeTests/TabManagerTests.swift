import Testing
import AppKit
@testable import Hakuke

/// Tests for TabManager's tab lifecycle: add, close, select, navigate, reopen.
@MainActor
@Suite(.serialized)
struct TabManagerTests {

    // MARK: - Initialization

    @Test func initialState_hasSingleTab() {
        let manager = TabManager()
        #expect(manager.tabs.count == 1)
        #expect(manager.activeTabIndex == 0)
        #expect(manager.activeTab != nil)
    }

    @Test func initialTab_hasDefaultTitle() {
        let manager = TabManager()
        #expect(manager.tabs[0].title == "zsh")
    }

    // MARK: - addTab

    @Test func addTab_increasesTabCount() {
        let manager = TabManager()
        let countBefore = manager.tabs.count
        manager.addTab()
        #expect(manager.tabs.count == countBefore + 1)
    }

    @Test func addTab_activatesNewTab() {
        let manager = TabManager()
        manager.addTab()
        #expect(manager.activeTabIndex == 1)
        manager.addTab()
        #expect(manager.activeTabIndex == 2)
    }

    @Test func addTab_multipleTimes_allTabsHaveUniqueIDs() {
        let manager = TabManager()
        manager.addTab()
        manager.addTab()
        let ids = manager.tabs.map(\.id)
        let uniqueIDs = Set(ids)
        #expect(uniqueIDs.count == ids.count)
    }

    // MARK: - closeTab

    @Test func closeTab_removesTab() {
        let manager = TabManager()
        manager.addTab()
        #expect(manager.tabs.count == 2)
        let secondTabID = manager.tabs[1].id
        manager.closeTab(id: secondTabID)
        #expect(manager.tabs.count == 1)
    }

    @Test func closeTab_lastTab_addsNewTab() {
        let manager = TabManager()
        #expect(manager.tabs.count == 1)
        let onlyTabID = manager.tabs[0].id
        manager.closeTab(id: onlyTabID)
        // Closing the last tab should re-add one automatically
        #expect(manager.tabs.count == 1)
        // The new tab should have a different ID
        #expect(manager.tabs[0].id != onlyTabID)
    }

    @Test func closeTab_adjustsActiveIndex_whenClosingLastPosition() {
        let manager = TabManager()
        manager.addTab()
        manager.addTab()
        // 3 tabs, active is #2 (last)
        #expect(manager.activeTabIndex == 2)
        let lastTabID = manager.tabs[2].id
        manager.closeTab(id: lastTabID)
        // Active index should clamp to new last position
        #expect(manager.activeTabIndex <= manager.tabs.count - 1)
    }

    @Test func closeTab_withInvalidID_doesNothing() {
        let manager = TabManager()
        let countBefore = manager.tabs.count
        manager.closeTab(id: "NONEXIST")
        #expect(manager.tabs.count == countBefore)
    }

    @Test func closeTab_middleTab_preservesOtherTabs() {
        let manager = TabManager()
        manager.addTab()
        manager.addTab()
        // 3 tabs: [0, 1, 2]
        let firstID = manager.tabs[0].id
        let middleID = manager.tabs[1].id
        let lastID = manager.tabs[2].id
        manager.closeTab(id: middleID)
        #expect(manager.tabs.count == 2)
        #expect(manager.tabs[0].id == firstID)
        #expect(manager.tabs[1].id == lastID)
    }

    // MARK: - selectTab

    @Test func selectTab_validIndex_changesActiveTab() {
        let manager = TabManager()
        manager.addTab()
        manager.addTab()
        manager.selectTab(at: 0)
        #expect(manager.activeTabIndex == 0)
        manager.selectTab(at: 2)
        #expect(manager.activeTabIndex == 2)
    }

    @Test func selectTab_negativeIndex_doesNothing() {
        let manager = TabManager()
        manager.addTab()
        manager.selectTab(at: 1)
        manager.selectTab(at: -1)
        #expect(manager.activeTabIndex == 1)
    }

    @Test func selectTab_outOfBoundsIndex_doesNothing() {
        let manager = TabManager()
        manager.addTab()
        manager.selectTab(at: 0)
        manager.selectTab(at: 99)
        #expect(manager.activeTabIndex == 0)
    }

    // MARK: - selectNextTab

    @Test func selectNextTab_wrapsAround() {
        let manager = TabManager()
        manager.addTab()
        manager.addTab()
        // 3 tabs, active is #2 (last)
        #expect(manager.activeTabIndex == 2)
        manager.selectNextTab()
        #expect(manager.activeTabIndex == 0)
    }

    @Test func selectNextTab_advancesForward() {
        let manager = TabManager()
        manager.addTab()
        manager.addTab()
        manager.selectTab(at: 0)
        manager.selectNextTab()
        #expect(manager.activeTabIndex == 1)
        manager.selectNextTab()
        #expect(manager.activeTabIndex == 2)
    }

    @Test func selectNextTab_singleTab_doesNothing() {
        let manager = TabManager()
        #expect(manager.tabs.count == 1)
        manager.selectNextTab()
        #expect(manager.activeTabIndex == 0)
    }

    // MARK: - selectPreviousTab

    @Test func selectPreviousTab_wrapsAround() {
        let manager = TabManager()
        manager.addTab()
        manager.addTab()
        manager.selectTab(at: 0)
        manager.selectPreviousTab()
        #expect(manager.activeTabIndex == 2)
    }

    @Test func selectPreviousTab_goesBackward() {
        let manager = TabManager()
        manager.addTab()
        manager.addTab()
        // Active is #2
        manager.selectPreviousTab()
        #expect(manager.activeTabIndex == 1)
        manager.selectPreviousTab()
        #expect(manager.activeTabIndex == 0)
    }

    @Test func selectPreviousTab_singleTab_doesNothing() {
        let manager = TabManager()
        #expect(manager.tabs.count == 1)
        manager.selectPreviousTab()
        #expect(manager.activeTabIndex == 0)
    }

    // MARK: - reopenClosedTab

    @Test func reopenClosedTab_noHistory_doesNothing() {
        let manager = TabManager()
        let countBefore = manager.tabs.count
        manager.reopenClosedTab()
        // reopenClosedTab only adds a tab if there's a saved directory
        // Since no tab was closed with a non-empty directory, count stays the same
        #expect(manager.tabs.count == countBefore)
    }

    @Test func canReopenClosedTab_initiallyFalse() {
        let manager = TabManager()
        #expect(manager.canReopenClosedTab == false)
    }

    // MARK: - activeTab

    @Test func activeTab_returnsCorrectTab() {
        let manager = TabManager()
        manager.addTab()
        manager.selectTab(at: 0)
        let expectedID = manager.tabs[0].id
        #expect(manager.activeTab?.id == expectedID)

        manager.selectTab(at: 1)
        let expectedID2 = manager.tabs[1].id
        #expect(manager.activeTab?.id == expectedID2)
    }

    // MARK: - Theme

    @Test func defaultTheme_isSet() {
        let manager = TabManager()
        let theme = manager.theme
        #expect(theme.fontSize == 13)
        #expect(theme.fontName == "SF Mono")
        // backgroundOpacity comes from @AppStorage, may vary in test environment
        #expect(theme.backgroundOpacity >= 0.3 && theme.backgroundOpacity <= 1.0)
    }

    // MARK: - hoveredTabIndex

    @Test func hoveredTabIndex_initiallyNil() {
        let manager = TabManager()
        #expect(manager.hoveredTabIndex == nil)
    }

    @Test func hoveredTabIndex_canBeSet() {
        let manager = TabManager()
        manager.hoveredTabIndex = 0
        #expect(manager.hoveredTabIndex == 0)
        manager.hoveredTabIndex = nil
        #expect(manager.hoveredTabIndex == nil)
    }
}
