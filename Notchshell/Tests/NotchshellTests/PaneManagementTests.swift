import Testing
import AppKit
import SwiftUI
@testable import Notchshell

/// Comprehensive integration tests for pane management:
/// split, focus, navigation, close, and interaction with tabs.
@MainActor
@Suite(.serialized)
struct PaneIntegrationTests {

    // MARK: - Basic split

    @Test func split_horizontal_createsTwoPanes() throws {
        let pm = PaneManager()
        #expect(pm.rootPane.leafCount == 1)
        let originalID = pm.focusedPaneID

        try #require(pm.splitFocusedPane(axis: .horizontal))

        #expect(pm.rootPane.leafCount == 2)
        #expect(pm.focusedPaneID != originalID, "Focus should move to new pane")
        #expect(pm.rootPane.leafIDs.contains(originalID), "Original pane still exists")
    }

    @Test func split_vertical_createsTwoPanes() throws {
        let pm = PaneManager()
        try #require(pm.splitFocusedPane(axis: .vertical))

        #expect(pm.rootPane.leafCount == 2)
    }

    @Test func split_multiple_createsTree() throws {
        let pm = PaneManager()
        try #require(pm.splitFocusedPane(axis: .horizontal))
        pm.splitFocusedPane(axis: .vertical)

        #expect(pm.rootPane.leafCount == 3)
        let ids = pm.rootPane.leafIDs
        #expect(ids.count == 3)
        #expect(Set(ids).count == 3, "All pane IDs should be unique")
    }

    @Test func split_fourWay() throws {
        let pm = PaneManager()
        try #require(pm.splitFocusedPane(axis: .horizontal))
        pm.splitFocusedPane(axis: .vertical)   // 3 panes, focus on 3rd
        // Focus on the 1st pane and split it
        pm.focusedPaneID = pm.rootPane.leafIDs[0]
        pm.splitFocusedPane(axis: .vertical)   // 4 panes

        #expect(pm.rootPane.leafCount == 4)
    }

    // MARK: - Focus navigation

    @Test func moveFocus_next_wrapsAround() throws {
        let pm = PaneManager()
        try #require(pm.splitFocusedPane(axis: .horizontal))
        pm.splitFocusedPane(axis: .vertical)
        // 3 panes, focused on last

        let ids = pm.rootPane.leafIDs
        #expect(pm.focusedPaneID == ids[2])

        pm.moveFocus(.next)
        #expect(pm.focusedPaneID == ids[0], "Should wrap to first")
    }

    @Test func moveFocus_previous_wrapsAround() throws {
        let pm = PaneManager()
        try #require(pm.splitFocusedPane(axis: .horizontal))

        let ids = pm.rootPane.leafIDs
        pm.focusedPaneID = ids[0] // focus first

        pm.moveFocus(.previous)
        #expect(pm.focusedPaneID == ids[1], "Should wrap to last")
    }

    @Test func moveFocus_singlePane_noChange() {
        let pm = PaneManager()
        let id = pm.focusedPaneID

        pm.moveFocus(.next)
        #expect(pm.focusedPaneID == id)

        pm.moveFocus(.previous)
        #expect(pm.focusedPaneID == id)
    }

    @Test func focusedBackend_matchesFocusedPaneID() throws {
        let pm = PaneManager()
        try #require(pm.splitFocusedPane(axis: .horizontal))

        let focusedBackend = pm.focusedBackend
        let backendFromTree = pm.rootPane.backend(for: pm.focusedPaneID)

        #expect(focusedBackend != nil)
        #expect(focusedBackend === backendFromTree)
    }

    // MARK: - Close panes

    @Test func close_onlyPane_callsOnLastPaneClosed() {
        let pm = PaneManager()
        var lastPaneClosed = false
        pm.onLastPaneClosed = { lastPaneClosed = true }

        let result = pm.closePane(id: pm.focusedPaneID)

        #expect(result == false, "No panes remain")
        #expect(lastPaneClosed)
    }

    @Test func close_oneOfTwo_leavesOne() throws {
        let pm = PaneManager()
        let firstID = pm.focusedPaneID
        try #require(pm.splitFocusedPane(axis: .horizontal))
        let secondID = pm.focusedPaneID

        let result = pm.closePane(id: secondID)

        #expect(result == true, "One pane remains")
        #expect(pm.rootPane.leafCount == 1)
        #expect(pm.focusedPaneID == firstID, "Focus moves to remaining pane")
    }

    @Test func close_focusedPane_movesFocusToSibling() throws {
        let pm = PaneManager()
        try #require(pm.splitFocusedPane(axis: .horizontal))
        pm.splitFocusedPane(axis: .vertical)
        // 3 panes, focused on third

        let focusedBefore = pm.focusedPaneID
        pm.closePane(id: focusedBefore)

        #expect(pm.rootPane.leafCount == 2)
        #expect(pm.focusedPaneID != focusedBefore, "Focus should move away from closed pane")
        #expect(pm.rootPane.leafIDs.contains(pm.focusedPaneID), "Focus is on a valid pane")
    }

    @Test func close_allButOne_fromMany() throws {
        let pm = PaneManager()
        try #require(pm.splitFocusedPane(axis: .horizontal))
        pm.splitFocusedPane(axis: .vertical)
        pm.splitFocusedPane(axis: .horizontal)
        #expect(pm.rootPane.leafCount == 4)

        while pm.rootPane.leafCount > 1 {
            let idToClose = pm.rootPane.leafIDs.last!
            pm.closePane(id: idToClose)
        }

        #expect(pm.rootPane.leafCount == 1)
    }

    // MARK: - Pane instances are independent

    @Test func splitPanes_haveDistinctBackends() throws {
        let pm = PaneManager()
        let b1 = pm.focusedBackend
        try #require(pm.splitFocusedPane(axis: .horizontal))
        let b2 = pm.focusedBackend

        #expect(b1 !== b2, "Each pane should have its own backend")
    }

    // MARK: - Tab + Pane interaction

    @Test func tab_withSplitPanes_closesAll() throws {
        let tm = TabManager()
        guard let pm = tm.activeTab?.paneManager else {
            #expect(Bool(false), "Active tab should have paneManager")
            return
        }

        try #require(pm.splitFocusedPane(axis: .horizontal))
        pm.splitFocusedPane(axis: .vertical)
        #expect(pm.rootPane.leafCount == 3)

        let tabID = tm.activeTab!.id
        tm.closeTab(id: tabID)

        // Tab closes, new one auto-created
        #expect(tm.tabs.count == 1)
        #expect(tm.tabs[0].id != tabID)
    }

    @Test func multipleTabs_independentPanes() throws {
        let tm = TabManager()
        tm.addTab()
        #expect(tm.tabs.count == 2)

        let pm0 = tm.tabs[0].paneManager!
        let pm1 = tm.tabs[1].paneManager!

        try #require(pm0.splitFocusedPane(axis: .horizontal))
        #expect(pm0.rootPane.leafCount == 2)
        #expect(pm1.rootPane.leafCount == 1, "Second tab's panes should be unaffected")
    }

    @Test func switchTab_preservesPaneFocus() throws {
        let tm = TabManager()
        guard let pm = tm.activeTab?.paneManager else { return }

        try #require(pm.splitFocusedPane(axis: .horizontal))
        let focusedInTab0 = pm.focusedPaneID

        tm.addTab() // switches to tab 1
        #expect(tm.activeTabIndex == 1)

        tm.selectTab(at: 0) // back to tab 0
        #expect(pm.focusedPaneID == focusedInTab0, "Pane focus should be preserved")
    }

    // MARK: - PaneNode leaf operations

    @Test func leafIDs_returnsAllLeaves() throws {
        let pm = PaneManager()
        try #require(pm.splitFocusedPane(axis: .horizontal))
        pm.splitFocusedPane(axis: .vertical)

        let ids = pm.rootPane.leafIDs
        #expect(ids.count == 3)
        #expect(Set(ids).count == 3)
    }

    @Test func backend_forID_returnsCorrect() throws {
        let pm = PaneManager()
        let id1 = pm.focusedPaneID
        try #require(pm.splitFocusedPane(axis: .horizontal))
        let id2 = pm.focusedPaneID

        let b1 = pm.rootPane.backend(for: id1)
        let b2 = pm.rootPane.backend(for: id2)

        #expect(b1 != nil)
        #expect(b2 != nil)
        #expect(b1 !== b2)
    }

    @Test func backend_forInvalidID_returnsNil() {
        let pm = PaneManager()
        #expect(pm.rootPane.backend(for: "NONEXIST") == nil)
    }

    // MARK: - Resize splits

    @Test func updateSplitRatio_changesRatio() throws {
        let pm = PaneManager()
        try #require(pm.splitFocusedPane(axis: .horizontal))

        guard case .split(let splitID, _, _, _, let ratio) = pm.rootPane else {
            Issue.record("Expected split root"); return
        }
        #expect(abs(ratio - 0.5) < 0.001)

        pm.updateSplitRatio(splitID: splitID, ratio: 0.7)

        if case .split(_, _, _, _, let newRatio) = pm.rootPane {
            #expect(abs(newRatio - 0.7) < 0.001)
        }
    }

    @Test func resizeFocusedSplit_growsFocusedPane() throws {
        let pm = PaneManager()
        let firstID = pm.focusedPaneID
        try #require(pm.splitFocusedPane(axis: .horizontal))
        // Focus is on second pane. Grow it by +0.1 → ratio decreases (second gets more space)
        pm.resizeFocusedSplit(delta: 0.1)

        if case .split(_, _, _, _, let ratio) = pm.rootPane {
            #expect(ratio < 0.5, "Second pane growing means first pane's ratio shrinks")
        }
    }

    @Test func resizeFocusedSplit_firstPane_growsRatio() throws {
        let pm = PaneManager()
        let firstID = pm.focusedPaneID
        try #require(pm.splitFocusedPane(axis: .horizontal))
        // Switch focus to first pane
        pm.focusedPaneID = firstID
        pm.resizeFocusedSplit(delta: 0.1)

        if case .split(_, _, _, _, let ratio) = pm.rootPane {
            #expect(ratio > 0.5, "First pane growing means ratio increases")
        }
    }

    @Test func resizeFocusedSplit_singlePane_noOp() {
        let pm = PaneManager()
        // Should not crash with single pane
        pm.resizeFocusedSplit(delta: 0.1)
        #expect(pm.rootPane.leafCount == 1)
    }

    @Test func equalizeSplits_resetsAllRatios() throws {
        let pm = PaneManager()
        try #require(pm.splitFocusedPane(axis: .horizontal))

        // Change ratio away from 0.5
        if case .split(let splitID, _, _, _, _) = pm.rootPane {
            pm.updateSplitRatio(splitID: splitID, ratio: 0.3)
        }

        pm.equalizeSplits()

        if case .split(_, _, _, _, let ratio) = pm.rootPane {
            #expect(abs(ratio - 0.5) < 0.001)
        }
    }

    @Test func splitPane_customRatio_applied() throws {
        let pm = PaneManager()
        try #require(pm.splitFocusedPane(axis: .horizontal, ratio: 0.7))

        if case .split(_, _, _, _, let ratio) = pm.rootPane {
            #expect(abs(ratio - 0.7) < 0.001)
        }
    }
}
