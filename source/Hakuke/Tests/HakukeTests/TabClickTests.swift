import Testing
import AppKit
@testable import Hakuke

/// Tests for tab bar click behavior:
/// - Single click on tab → select (via MouseDownOverlay)
/// - Double click on tab → rename
/// - Double click on empty space → new tab (via DoubleClickCatcher + hoveredTabIndex)
/// - Single click on empty space → nothing
///
/// Also tests the layer opacity of the terminal container to prevent
/// transparency regressions (blurry mc/TUI rendering).
@MainActor
@Suite(.serialized)
struct TabClickTests {

    // MARK: - Helpers

    private func makeMouseEvent(clickCount: Int) -> NSEvent {
        NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: clickCount,
            pressure: 1.0
        )!
    }

    // MARK: - MouseDownOverlay tab click scenarios

    @Test func tabClick_single_selectsTab() {
        var selected = false
        let view = MouseDownNSView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        view.action = { selected = true }
        view.doubleAction = { /* rename */ }

        view.mouseDown(with: makeMouseEvent(clickCount: 1))
        #expect(selected, "Single click should select the tab")
    }

    @Test func tabClick_single_doesNotRename() {
        var renamed = false
        let view = MouseDownNSView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        view.action = { /* select */ }
        view.doubleAction = { renamed = true }

        view.mouseDown(with: makeMouseEvent(clickCount: 1))
        #expect(!renamed, "Single click should NOT trigger rename")
    }

    @Test func tabClick_double_renames() {
        var renamed = false
        let view = MouseDownNSView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        view.action = { /* select */ }
        view.doubleAction = { renamed = true }

        view.mouseDown(with: makeMouseEvent(clickCount: 2))
        #expect(renamed, "Double click on tab should trigger rename")
    }

    @Test func tabClick_double_doesNotSelect() {
        var selected = false
        let view = MouseDownNSView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        view.action = { selected = true }
        view.doubleAction = { /* rename */ }

        view.mouseDown(with: makeMouseEvent(clickCount: 2))
        #expect(!selected, "Double click should NOT trigger select (only rename)")
    }

    // MARK: - DoubleClickCatcher empty space scenarios

    @Test func emptySpace_doubleClick_addsTab_whenNoTabHovered() {
        let tm = TabManager()
        let initialCount = tm.tabs.count
        #expect(tm.hoveredTabIndex == nil)

        // Simulate what DoubleClickCatcher does
        if tm.hoveredTabIndex == nil {
            tm.addTab()
        }

        #expect(tm.tabs.count == initialCount + 1)
    }

    @Test func emptySpace_doubleClick_doesNotAddTab_whenTabHovered() {
        let tm = TabManager()
        let initialCount = tm.tabs.count
        tm.hoveredTabIndex = 0  // tab is hovered

        // Simulate what DoubleClickCatcher does
        if tm.hoveredTabIndex == nil {
            tm.addTab()
        }

        #expect(tm.tabs.count == initialCount, "Should NOT add tab when hovering over existing tab")
    }

    // MARK: - Tab selection via TabManager

    @Test func tabManager_selectTab_changesActiveIndex() {
        let tm = TabManager()
        tm.addTab()
        tm.addTab()
        #expect(tm.tabs.count == 3)
        #expect(tm.activeTabIndex == 2)

        tm.selectTab(at: 0)
        #expect(tm.activeTabIndex == 0)

        tm.selectTab(at: 1)
        #expect(tm.activeTabIndex == 1)
    }

    @Test func tabManager_selectTab_outOfBounds_isNoOp() {
        let tm = TabManager()
        tm.selectTab(at: 99)
        #expect(tm.activeTabIndex == 0)

        tm.selectTab(at: -1)
        #expect(tm.activeTabIndex == 0)
    }

    // MARK: - Layer opacity regression test

    #if canImport(GhosttyKit)
    @Test func ghosttyBackend_containerView_isOpaque() {
        // The container view must have an opaque layer with black background
        // to prevent the Metal framebuffer transparency from bleeding through.
        // Regression: removing this causes blurry TUI rendering (mc, htop, etc.)
        let backend = GhosttyBackend()
        let container = backend.view

        #expect(container.wantsLayer == true, "Container must be layer-backed")
        #expect(container.layer?.isOpaque == true, "Container layer must be opaque")

        if let bg = container.layer?.backgroundColor {
            let components = bg.components ?? []
            // Black in grayscale: [0.0, 1.0] (luminance=0, alpha=1)
            // Black in RGB: [0.0, 0.0, 0.0, 1.0]
            let isBlack: Bool
            if components.count == 2 {
                isBlack = components[0] < 0.01 // grayscale luminance
            } else if components.count >= 3 {
                isBlack = components[0] < 0.01 && components[1] < 0.01 && components[2] < 0.01
            } else {
                isBlack = false
            }
            #expect(isBlack, "Container background should be black, got \(components)")
        } else {
            #expect(Bool(false), "Container layer must have backgroundColor set")
        }

        backend.terminate()
    }
    #endif
}
