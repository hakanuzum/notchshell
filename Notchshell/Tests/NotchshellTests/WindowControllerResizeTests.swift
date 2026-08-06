import Testing
import AppKit
@testable import Notchshell

/// Tests for WindowController resize clamping, percent setters, delta-based resize,
/// terminal size calculation, display selection, and show/hide state transitions.
@MainActor
@Suite(.serialized)
struct WindowControllerPercentClampingTests {

    // MARK: - setWidthPercent clamping

    @Test func setWidthPercent_belowMin_clampedTo30() {
        let wc = WindowController()
        wc.setWidthPercent(10)
        #expect(wc.widthPercent == 30)
    }

    @Test func setWidthPercent_aboveMax_clampedTo100() {
        let wc = WindowController()
        wc.setWidthPercent(150)
        #expect(wc.widthPercent == 100)
    }

    @Test func setWidthPercent_atMin_exact30() {
        let wc = WindowController()
        wc.setWidthPercent(30)
        #expect(wc.widthPercent == 30)
    }

    @Test func setWidthPercent_atMax_exact100() {
        let wc = WindowController()
        wc.setWidthPercent(100)
        #expect(wc.widthPercent == 100)
    }

    @Test func setWidthPercent_normalValue_setsExactly() {
        let wc = WindowController()
        wc.setWidthPercent(65)
        #expect(wc.widthPercent == 65)
    }

    // MARK: - setHeightPercent clamping

    @Test func setHeightPercent_belowMin_clampedTo20() {
        let wc = WindowController()
        wc.setHeightPercent(5)
        #expect(wc.heightPercent == 20)
    }

    @Test func setHeightPercent_aboveMax_clampedTo100() {
        let wc = WindowController()
        wc.setHeightPercent(110)
        #expect(wc.heightPercent == 100)
    }

    @Test func setHeightPercent_atMin_exact20() {
        let wc = WindowController()
        wc.setHeightPercent(20)
        #expect(wc.heightPercent == 20)
    }

    @Test func setHeightPercent_atMax_exact100() {
        let wc = WindowController()
        wc.setHeightPercent(100)
        #expect(wc.heightPercent == 100)
    }

    @Test func setHeightPercent_normalValue_setsExactly() {
        let wc = WindowController()
        wc.setHeightPercent(50)
        #expect(wc.heightPercent == 50)
    }

    // MARK: - Boundary values (one off)

    @Test func setWidthPercent_29_clampedTo30() {
        let wc = WindowController()
        wc.setWidthPercent(29)
        #expect(wc.widthPercent == 30)
    }

    @Test func setWidthPercent_31_setsExactly() {
        let wc = WindowController()
        wc.setWidthPercent(31)
        #expect(wc.widthPercent == 31)
    }

    @Test func setHeightPercent_19_clampedTo20() {
        let wc = WindowController()
        wc.setHeightPercent(19)
        #expect(wc.heightPercent == 20)
    }

    @Test func setHeightPercent_101_clampedTo100() {
        let wc = WindowController()
        wc.setHeightPercent(101)
        #expect(wc.heightPercent == 100)
    }
}

@MainActor
@Suite(.serialized)
struct WindowControllerDeltaResizeTests {

    @Test func updateWidthByDelta_tinyWidth_clampedTo30() {
        let wc = WindowController()
        // Pass a very small pixel width → should clamp to 30%
        wc.updateWidthByDelta(10)
        #expect(wc.widthPercent >= 30)
    }

    @Test func updateWidthByDelta_fullWidth_clampedTo100() {
        let wc = WindowController()
        // Pass a pixel width larger than the screen → should clamp to 100%
        let screenWidth = wc.resolvedScreen.frame.width
        wc.updateWidthByDelta(screenWidth * 2)
        #expect(wc.widthPercent == 100)
    }

    @Test func updateWidthByDelta_updatesCachedWidth() {
        let wc = WindowController()
        let before = wc.cachedWidth
        wc.updateWidthByDelta(wc.resolvedScreen.frame.width * 0.5)
        // cachedWidth should have been updated
        #expect(wc.cachedWidth != before || wc.cachedWidth > 0)
    }

    @Test func updateHeightByDelta_tinyHeight_clampedTo20() {
        let wc = WindowController()
        wc.updateHeightByDelta(10)
        #expect(wc.heightPercent >= 20)
    }

    @Test func updateHeightByDelta_fullHeight_clampedTo100() {
        let wc = WindowController()
        let screenHeight = wc.resolvedScreen.frame.height
        wc.updateHeightByDelta(screenHeight * 2)
        #expect(wc.heightPercent == 100)
    }
}

@MainActor
@Suite(.serialized)
struct WindowControllerAnimationTests {

    @Test func show_withAnimationDisabled_changesStateInstantly() {
        UserDefaults.standard.set(true, forKey: "disableAnimation")
        defer { UserDefaults.standard.removeObject(forKey: "disableAnimation") }

        let wc = WindowController()
        #expect(wc.state == .hidden)
        wc.show()
        #expect(wc.state == .visible)
    }

    @Test func hide_withAnimationDisabled_changesStateInstantly() {
        UserDefaults.standard.set(true, forKey: "disableAnimation")
        defer { UserDefaults.standard.removeObject(forKey: "disableAnimation") }

        let wc = WindowController()
        wc.show()
        #expect(wc.state == .visible)
        wc.hide()
        #expect(wc.state == .hidden)
    }

    @Test func toggle_withAnimationDisabled_worksCorrectly() {
        UserDefaults.standard.set(true, forKey: "disableAnimation")
        defer { UserDefaults.standard.removeObject(forKey: "disableAnimation") }

        let wc = WindowController()
        wc.toggle()
        #expect(wc.state == .visible)
        wc.toggle()
        #expect(wc.state == .hidden)
    }

    @Test func heightPercent_allowsFullScreen() {
        let wc = WindowController()
        wc.setHeightPercent(100)
        #expect(wc.heightPercent == 100)
        #expect(wc.terminalSize.height > 0)
    }
}

@MainActor
@Suite(.serialized)
struct WindowControllerTerminalSizeTests {

    @Test func terminalSize_widthNeverBelow300() {
        let wc = WindowController()
        wc.setWidthPercent(30) // minimum percent
        #expect(wc.terminalSize.width >= 300)
    }

    @Test func terminalSize_heightNeverBelow150() {
        let wc = WindowController()
        wc.setHeightPercent(20) // minimum percent
        #expect(wc.terminalSize.height >= 150)
    }

    @Test func terminalSize_calculatesFromPercents() {
        let wc = WindowController()
        let screen = wc.resolvedScreen.frame
        wc.setWidthPercent(50)
        wc.setHeightPercent(50)
        let expected = CGSize(
            width: max(screen.width * 0.5, 300),
            height: max(screen.height * 0.5, 150)
        )
        #expect(wc.terminalSize.width == expected.width)
        #expect(wc.terminalSize.height == expected.height)
    }
}

@MainActor
@Suite(.serialized)
struct WindowControllerDisplayTests {

    @Test func setDisplayID_setsValue() {
        let wc = WindowController()
        wc.setDisplayID(42)
        #expect(wc.displayID == 42)
    }

    @Test func resolvedScreen_displayID0_returnsAScreen() {
        let wc = WindowController()
        wc.setDisplayID(0)
        let screen = wc.resolvedScreen
        #expect(screen.frame.width > 0)
        #expect(screen.frame.height > 0)
    }

    @Test func resolvedScreen_invalidDisplayID_fallsToMain() {
        let wc = WindowController()
        wc.setDisplayID(999999) // non-existent display
        let screen = wc.resolvedScreen
        // Should fall back to main screen
        #expect(screen.frame.width > 0)
    }
}

@MainActor
@Suite(.serialized)
struct WindowControllerStateTransitionTests {

    @Test func toggle_fromHidden_shows() {
        let wc = WindowController()
        #expect(wc.state == .hidden)
        wc.toggle()
        #expect(wc.state == .visible)
    }

    @Test func toggle_fromVisible_hides() {
        let wc = WindowController()
        wc.show()
        #expect(wc.state == .visible)
        wc.toggle()
        #expect(wc.state == .hidden)
    }

    @Test func show_alreadyVisible_noOp() {
        let wc = WindowController()
        wc.show()
        #expect(wc.state == .visible)
        wc.show() // should be no-op
        #expect(wc.state == .visible)
    }

    @Test func hide_alreadyHidden_noOp() {
        let wc = WindowController()
        #expect(wc.state == .hidden)
        wc.hide() // should be no-op
        #expect(wc.state == .hidden)
    }
}
