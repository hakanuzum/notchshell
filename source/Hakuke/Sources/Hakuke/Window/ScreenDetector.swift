import AppKit

struct ScreenInfo {
    let hasTopInset: Bool
    let topInsetRect: NSRect       // top safe area in screen coordinates
    let topInsetWidth: CGFloat
    let topInsetHeight: CGFloat
    let screenFrame: NSRect     // full screen frame
    let visibleFrame: NSRect    // usable area
}

enum ScreenDetector {
    static func detect(for screen: NSScreen? = nil) -> ScreenInfo {
        let screen = screen ?? NSScreen.main ?? NSScreen.screens.first!
        let frame = screen.frame
        let visible = screen.visibleFrame
        let safeTop = screen.safeAreaInsets.top

        let hasTopInset = safeTop > 0

        let topInsetWidth: CGFloat
        let topInsetHeight: CGFloat
        let topInsetRect: NSRect

        if hasTopInset {
            // Use auxiliaryTopLeftArea and auxiliaryTopRightArea to calculate top inset geometry
            if let leftArea = screen.auxiliaryTopLeftArea,
               let rightArea = screen.auxiliaryTopRightArea {
                let leftPadding = leftArea.width
                let rightPadding = rightArea.width
                // +4 correction to match physical safe area inset
                topInsetWidth = frame.width - leftPadding - rightPadding + 4
                topInsetHeight = safeTop
                topInsetRect = NSRect(
                    x: frame.origin.x + leftPadding - 2,
                    y: frame.maxY - topInsetHeight,
                    width: topInsetWidth,
                    height: topInsetHeight
                )
            } else {
                // Fallback: approximate top inset size (typical MacBook Pro)
                topInsetWidth = 170
                topInsetHeight = safeTop
                topInsetRect = NSRect(
                    x: frame.midX - topInsetWidth / 2,
                    y: frame.maxY - topInsetHeight,
                    width: topInsetWidth,
                    height: topInsetHeight
                )
            }
        } else {
            // No top inset: provide a centered virtual area for positioning
            topInsetWidth = 200
            topInsetHeight = 0
            topInsetRect = NSRect(
                x: frame.midX - topInsetWidth / 2,
                y: frame.maxY,
                width: topInsetWidth,
                height: 0
            )
        }

        return ScreenInfo(
            hasTopInset: hasTopInset,
            topInsetRect: topInsetRect,
            topInsetWidth: topInsetWidth,
            topInsetHeight: topInsetHeight,
            screenFrame: frame,
            visibleFrame: visible
        )
    }
}
