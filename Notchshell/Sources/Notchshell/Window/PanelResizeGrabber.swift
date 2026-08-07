import SwiftUI
import AppKit

/// The handle on the panel's bottom edge that sets how much height the terminal takes.
///
/// A short horizontal capsule rather than a three-dot grip: the bar already carries an
/// `ellipsis.circle` for its overflow menu, and two different meanings should not share
/// one mark. A capsule on an edge says "drag this edge" and nothing else.
///
/// Centred horizontally, which is the one stretch of the bar that holds neither tabs
/// nor icons, so the handle never competes for a click with either.
struct PanelResizeGrabber: View {
    @ObservedObject var windowController: WindowController

    /// Panel height when the drag began. Zero means no drag is in progress — the height
    /// is clamped to a floor well above zero, so it is not a reachable value.
    @State private var dragStartHeight: CGFloat = 0
    @State private var isHovered = false

    private static let barWidth: CGFloat = 38
    private static let barThickness: CGFloat = 4.5

    var body: some View {
        Capsule()
            .fill(FolderTabPalette.barIcon.opacity(isHovered || dragStartHeight != 0 ? 0.62 : 0.34))
            .frame(width: Self.barWidth, height: Self.barThickness)
            // The drawn capsule is 4.5pt tall, which is nothing to aim at. The hit area
            // is the whole strip around it.
            .padding(.vertical, 6)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovered = hovering
                if hovering { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
            .gesture(
                // Global coordinates: dragging the bottom edge moves the bar, and with
                // it this view. A view-local translation would then be measured from a
                // start point that is itself moving, and the panel would run away.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        if dragStartHeight == 0 {
                            dragStartHeight = windowController.terminalSize.height
                            windowController.beginTransientInteraction(seconds: 30)
                        }
                        windowController.updateHeightByDelta(
                            dragStartHeight + drag.translation.height
                        )
                    }
                    .onEnded { _ in
                        dragStartHeight = 0
                        // `updateHeightByDelta` already wrote the persisted percentage,
                        // so there is nothing to commit here.
                        windowController.beginTransientInteraction(seconds: 1)
                    }
            )
            .help("Drag to resize · double-click to reset")
            .onTapGesture(count: 2) {
                windowController.setHeightPercent(WindowController.defaultHeightPercent)
            }
    }
}
