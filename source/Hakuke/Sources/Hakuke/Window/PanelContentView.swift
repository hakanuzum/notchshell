import SwiftUI

/// The root SwiftUI view hosted inside TerminalPanel.
/// Animation is driven explicitly by withAnimation in show()/hide().
struct PanelContentView: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var windowController: WindowController

    // Resize preview: shows outline during drag, applies on release
    @State private var dragStartSize: CGSize = .zero
    @State private var resizePreview: CGSize? = nil

    private var isVisible: Bool {
        windowController.state == .visible
    }

    private var currentWidth: CGFloat {
        windowController.cachedWidth > 0
            ? windowController.cachedWidth
            : windowController.terminalSize.width
    }

    private var currentSize: CGSize {
        CGSize(
            width: currentWidth,
            height: isVisible ? windowController.terminalSize.height : 0
        )
    }

    private var menuBarHeight: CGFloat {
        let screen = windowController.resolvedScreen
        let fromFrame = screen.frame.maxY - screen.visibleFrame.maxY
        // safeAreaInsets.top gives the menu bar / safe area height
        let safeTop = screen.safeAreaInsets.top
        return max(fromFrame, safeTop)
    }

    // MARK: - Terminal content (always full size — animation only clips)

    private var terminalContent: some View {
        VStack(spacing: 0) {
            TabBarView(tabManager: tabManager, windowController: windowController)

            ZStack {
                ForEach(tabManager.tabs) { tab in
                    Group {
                        switch tab.kind {
                        case .terminal:
                            if let pm = tab.paneManager {
                                PaneSplitView(
                                    paneManager: pm,
                                    tabManager: tabManager,
                                    theme: tabManager.theme
                                )
                            }
                        case .settings:
                            SettingsView(windowController: windowController)
                        case .help:
                            HelpView()
                        }
                    }
                    .zIndex(tab.id == tabManager.activeTab?.id ? 1 : 0)
                    .offset(x: tab.id == tabManager.activeTab?.id ? 0 : 99999)
                    .allowsHitTesting(tab.id == tabManager.activeTab?.id)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
        .frame(width: currentWidth, height: windowController.terminalSize.height)
    }

    // MARK: - Corner drag gesture (preview border, apply on release)

    private func cornerDragGesture(edge: HorizontalEdge) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStartSize == .zero {
                    dragStartSize = windowController.terminalSize
                }
                let widthDelta: CGFloat = (edge == .left)
                    ? -value.translation.width * 2
                    : value.translation.width * 2
                let screen = windowController.resolvedScreen.frame
                let newW = max(dragStartSize.width + widthDelta, 300)
                let newH = max(dragStartSize.height + value.translation.height, 150)
                resizePreview = CGSize(
                    width: min(newW, screen.width),
                    height: min(newH, screen.height * 0.9)
                )
            }
            .onEnded { _ in
                if let preview = resizePreview {
                    windowController.updateWidthByDelta(preview.width)
                    windowController.updateHeightByDelta(preview.height)
                }
                resizePreview = nil
                dragStartSize = .zero
            }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Dismiss layer
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { windowController.hide() }
                .allowsHitTesting(isVisible && !windowController.isPinned)

            VStack(spacing: 0) {
                Color.clear.frame(height: menuBarHeight)

                ZStack(alignment: .top) {
                    // Terminal always at full size, clipped by animated container.
                    // This prevents SIGWINCH on every animation frame.
                    terminalContent
                        .frame(height: currentSize.height, alignment: .top)
                        .clipped()
                        .clipShape(UnevenRoundedRectangle(
                            topLeadingRadius: 0, bottomLeadingRadius: 12,
                            bottomTrailingRadius: 12, topTrailingRadius: 0
                        ))
                        .overlay(
                            UnevenRoundedRectangle(
                                topLeadingRadius: 0, bottomLeadingRadius: 12,
                                bottomTrailingRadius: 12, topTrailingRadius: 0
                            )
                            .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                        )
                        .opacity(isVisible ? 1 : 0)

                    // Resize preview border (shown during drag)
                    if let preview = resizePreview, isVisible {
                        UnevenRoundedRectangle(
                            topLeadingRadius: 0, bottomLeadingRadius: 12,
                            bottomTrailingRadius: 12, topTrailingRadius: 0
                        )
                        .stroke(Color.white.opacity(0.3), lineWidth: 2)
                        .frame(width: preview.width, height: preview.height)
                    }

                    // Corner resize handles (overlaid at bottom corners)
                    if isVisible {
                        VStack {
                            Spacer()
                                .frame(height: currentSize.height - 16)
                            HStack {
                                // Bottom-left corner
                                CornerResizeHandle(edge: .left)
                                    .gesture(cornerDragGesture(edge: .left))
                                    .padding(.leading, (windowController.resolvedScreen.frame.width - currentSize.width) / 2)

                                Spacer()

                                // Bottom-right corner
                                CornerResizeHandle(edge: .right)
                                    .gesture(cornerDragGesture(edge: .right))
                                    .padding(.trailing, (windowController.resolvedScreen.frame.width - currentSize.width) / 2)
                            }
                        }
                    }
                }

                Spacer()
            }
            .frame(width: windowController.panelWidth > 0 ? windowController.panelWidth : nil)
        }
    }
}

enum HorizontalEdge {
    case left, right
}

struct CornerResizeHandle: View {
    let edge: HorizontalEdge

    var body: some View {
        Color.clear
            .frame(width: 16, height: 16)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                switch phase {
                case .active:
                    NSCursor.crosshair.push()
                case .ended:
                    NSCursor.pop()
                }
            }
    }
}
