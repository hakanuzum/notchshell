import Testing
import SwiftUI
@testable import Notchshell

/// Zoom is a flag rather than a pane id, so that navigating while zoomed cycles panes
/// instead of dead-ending on one. These pin the consequences of that choice.
@MainActor
@Suite(.serialized)
struct PaneZoomTests {

    @Test func zoom_isOffToBeginWith() {
        let pm = PaneManager()
        #expect(!pm.isZoomed)
    }

    /// One pane is already filling the tab; there is nothing to zoom out of, and a flag
    /// set here would make `⌘⇧Enter` look broken rather than inapplicable.
    @Test func zoom_singlePane_staysOff() {
        let pm = PaneManager()
        pm.toggleZoom()
        #expect(!pm.isZoomed)
    }

    @Test func zoom_withSplit_togglesOnAndOff() throws {
        let pm = PaneManager()
        try #require(pm.splitFocusedPane(axis: .horizontal))

        pm.toggleZoom()
        #expect(pm.isZoomed)
        pm.toggleZoom()
        #expect(!pm.isZoomed)
    }

    /// Splitting inside a zoom would show the new pane alone, which reads as the split
    /// having replaced the tab rather than divided it.
    @Test func zoom_splittingClearsIt() throws {
        let pm = PaneManager()
        try #require(pm.splitFocusedPane(axis: .horizontal))
        pm.toggleZoom()
        #expect(pm.isZoomed)

        try #require(pm.splitFocusedPane(axis: .vertical))
        #expect(!pm.isZoomed)
    }

    /// Closing back down to one pane leaves nothing to be zoomed out of.
    @Test func zoom_closingBackToOnePaneClearsIt() throws {
        let pm = PaneManager()
        try #require(pm.splitFocusedPane(axis: .horizontal))
        pm.toggleZoom()
        #expect(pm.isZoomed)

        pm.closePane(id: pm.focusedPaneID)
        #expect(pm.rootPane.leafCount == 1)
        #expect(!pm.isZoomed)
    }

    /// The zoom follows focus, so the zoomed pane is always the focused one and `⌘]`
    /// keeps working while zoomed.
    @Test func zoom_followsFocus() throws {
        let pm = PaneManager()
        try #require(pm.splitFocusedPane(axis: .horizontal))
        let second = pm.focusedPaneID
        pm.toggleZoom()

        pm.moveFocus(.next)
        #expect(pm.isZoomed)
        #expect(pm.focusedPaneID != second)
        #expect(pm.rootPane.leafIDs.contains(pm.focusedPaneID))
    }

    /// The renderer picks the pane to draw by looking the focused id up in the tree,
    /// so that lookup has to find a leaf and not a split.
    @Test func leafNode_findsOnlyLeaves() throws {
        let pm = PaneManager()
        try #require(pm.splitFocusedPane(axis: .horizontal))

        for id in pm.rootPane.leafIDs {
            let node = pm.rootPane.leafNode(for: id)
            #expect(node != nil)
            if case .split = node { Issue.record("leafNode returned a split for \(id)") }
        }
        #expect(pm.rootPane.leafNode(for: pm.rootPane.id) == nil)
    }
}
