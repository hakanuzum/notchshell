import Testing
import AppKit
@testable import Notchshell

@Suite(.serialized)
struct ScreenInfoTests {

    @Test func screenInfo_withTopInset_propertiesAreConsistent() {
        let info = ScreenInfo(
            hasTopInset: true,
            topInsetRect: NSRect(x: 500, y: 1400, width: 200, height: 38),
            topInsetWidth: 200,
            topInsetHeight: 38,
            screenFrame: NSRect(x: 0, y: 0, width: 1512, height: 1438),
            visibleFrame: NSRect(x: 0, y: 0, width: 1512, height: 1400)
        )
        #expect(info.hasTopInset == true)
        #expect(info.topInsetWidth == 200)
        #expect(info.topInsetHeight == 38)
        #expect(info.topInsetRect.width == info.topInsetWidth)
        #expect(info.topInsetRect.height == info.topInsetHeight)
    }

    @Test func screenInfo_withoutTopInset_heightIsZero() {
        let info = ScreenInfo(
            hasTopInset: false,
            topInsetRect: NSRect(x: 860, y: 1080, width: 200, height: 0),
            topInsetWidth: 200,
            topInsetHeight: 0,
            screenFrame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1055)
        )
        #expect(info.hasTopInset == false)
        #expect(info.topInsetHeight == 0)
        #expect(info.topInsetRect.height == 0)
    }

    @Test func screenInfo_screenFrame_matchesExpected() {
        let frame = NSRect(x: 0, y: 0, width: 2560, height: 1600)
        let info = ScreenInfo(
            hasTopInset: true,
            topInsetRect: NSRect(x: 1180, y: 1562, width: 200, height: 38),
            topInsetWidth: 200,
            topInsetHeight: 38,
            screenFrame: frame,
            visibleFrame: NSRect(x: 0, y: 0, width: 2560, height: 1562)
        )
        #expect(info.screenFrame == frame)
        #expect(info.screenFrame.width == 2560)
        #expect(info.screenFrame.height == 1600)
    }
}

@Suite(.serialized)
struct ScreenDetectorTests {

    @Test func detect_returnsValidInfo() {
        // ScreenDetector.detect() uses NSScreen.main which may be nil in test environments
        // but on a real macOS machine this should always work
        let info = ScreenDetector.detect()
        // screenFrame should have non-zero dimensions
        #expect(info.screenFrame.width > 0)
        #expect(info.screenFrame.height > 0)
        // visibleFrame should be within screenFrame
        #expect(info.visibleFrame.width <= info.screenFrame.width)
        #expect(info.visibleFrame.height <= info.screenFrame.height)
        // topInsetWidth should be positive
        #expect(info.topInsetWidth > 0)
        // topInsetHeight is 0 when no safe area inset, positive otherwise
        #expect(info.topInsetHeight >= 0)
    }

    @Test func detect_forMainScreen_topInsetRectIsWithinScreen() {
        let info = ScreenDetector.detect()
        if info.hasTopInset {
            // Top inset rect should be at the top of the screen
            #expect(info.topInsetRect.maxY <= info.screenFrame.maxY + 1) // +1 for float precision
            #expect(info.topInsetRect.minX >= info.screenFrame.minX)
        } else {
            // Virtual area centered on screen top
            #expect(info.topInsetHeight == 0)
        }
    }

    @Test func detect_forSpecificScreen_usesProvidedScreen() {
        guard let screen = NSScreen.main else {
            // Skip if no screen available (headless CI)
            return
        }
        let info = ScreenDetector.detect(for: screen)
        #expect(info.screenFrame == screen.frame)
    }
}

// MARK: - ScreenInfo edge cases

@Suite(.serialized)
struct ScreenInfoEdgeCaseTests {

    @Test func noTopInset_topInsetWidthIs200() {
        let info = ScreenInfo(
            hasTopInset: false,
            topInsetRect: NSRect(x: 860, y: 1080, width: 200, height: 0),
            topInsetWidth: 200,
            topInsetHeight: 0,
            screenFrame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1055)
        )
        #expect(info.topInsetWidth == 200)
    }

    @Test func noTopInset_topInsetHeightIsZero() {
        let info = ScreenInfo(
            hasTopInset: false,
            topInsetRect: NSRect(x: 860, y: 1080, width: 200, height: 0),
            topInsetWidth: 200,
            topInsetHeight: 0,
            screenFrame: NSRect(x: 0, y: 0, width: 1920, height: 1080),
            visibleFrame: NSRect(x: 0, y: 0, width: 1920, height: 1055)
        )
        #expect(info.topInsetHeight == 0)
    }

    @Test func noTopInset_topInsetRectCenteredOnScreen() {
        let screenWidth: CGFloat = 1920
        let info = ScreenInfo(
            hasTopInset: false,
            topInsetRect: NSRect(x: screenWidth / 2 - 100, y: 1080, width: 200, height: 0),
            topInsetWidth: 200,
            topInsetHeight: 0,
            screenFrame: NSRect(x: 0, y: 0, width: screenWidth, height: 1080),
            visibleFrame: NSRect(x: 0, y: 0, width: screenWidth, height: 1055)
        )
        // Rect should be roughly centered
        let rectCenterX = info.topInsetRect.midX
        let screenCenterX = info.screenFrame.midX
        #expect(abs(rectCenterX - screenCenterX) < 1)
    }

    @Test func detect_withNilScreen_usesMain() {
        let info = ScreenDetector.detect(for: nil)
        #expect(info.screenFrame.width > 0)
        #expect(info.screenFrame.height > 0)
    }

    @Test func detect_allScreens_returnValidInfo() {
        for screen in NSScreen.screens {
            let info = ScreenDetector.detect(for: screen)
            #expect(info.screenFrame.width > 0)
            #expect(info.screenFrame.height > 0)
            #expect(info.visibleFrame.width <= info.screenFrame.width)
            #expect(info.visibleFrame.height <= info.screenFrame.height)
        }
    }

    @Test func screenInfo_visibleFrameWithinScreenFrame() {
        let info = ScreenDetector.detect()
        #expect(info.visibleFrame.width <= info.screenFrame.width)
        #expect(info.visibleFrame.height <= info.screenFrame.height)
        #expect(info.visibleFrame.minX >= info.screenFrame.minX)
        #expect(info.visibleFrame.minY >= info.screenFrame.minY)
    }

    @Test(arguments: zip(
        [1920.0, 2560.0, 1512.0, 3456.0],
        [1080.0, 1600.0, 982.0, 2234.0]
    ))
    func screenInfo_multipleResolutions_valid(width: Double, height: Double) {
        let w = CGFloat(width)
        let h = CGFloat(height)
        let info = ScreenInfo(
            hasTopInset: false,
            topInsetRect: NSRect(x: w / 2 - 100, y: h, width: 200, height: 0),
            topInsetWidth: 200,
            topInsetHeight: 0,
            screenFrame: NSRect(x: 0, y: 0, width: w, height: h),
            visibleFrame: NSRect(x: 0, y: 0, width: w, height: h - 25)
        )
        #expect(info.screenFrame.width == w)
        #expect(info.screenFrame.height == h)
        #expect(info.visibleFrame.height < info.screenFrame.height)
    }
}
