import SwiftUI

/// Root SwiftUI view inside TerminalPanel.
/// Top-docked shelf: full-width under menu bar; soft chrome puts tabs on the BOTTOM.
struct PanelContentView: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var windowController: WindowController

    @State private var dragStartSize: CGSize = .zero
    @State private var resizePreview: CGSize? = nil

    private var isVisible: Bool {
        windowController.state == .visible
    }

    private var isSoft: Bool {
        PanelChrome.isSoftLight(windowController.chromeStyle)
    }

    private var fullWidth: CGFloat {
        windowController.cachedWidth > 0
            ? windowController.cachedWidth
            : windowController.terminalSize.width
    }

    private var fullHeight: CGFloat {
        windowController.terminalSize.height
    }

    private var animatedHeight: CGFloat {
        isVisible ? fullHeight : 0
    }

    private var menuBarHeight: CGFloat {
        let screen = windowController.resolvedScreen
        let fromFrame = screen.frame.maxY - screen.visibleFrame.maxY
        let safeTop = screen.safeAreaInsets.top
        return max(fromFrame, safeTop)
    }

    private var clipShape: UnevenRoundedRectangle {
        PanelChrome.clipShape()
    }

    /// Behind a terminal. Ghostty already paints the background at the requested alpha,
    /// so painting it again here would stack a second opaque copy underneath and cancel
    /// the transparency out.
    private var bodyBackground: Color {
        TerminalAppearanceSettings.isTranslucent
            ? Color.clear
            : Color(nsColor: tabManager.theme.background)
    }

    private var opaqueBodyBackground: Color {
        Color(nsColor: tabManager.theme.background)
    }

    // MARK: - Content: terminal body + tab bar placement

    private var terminalContent: some View {
        VStack(spacing: 0) {
            // Soft (Unclutter): tabs BOTTOM. Dark: tabs TOP.
            if !isSoft {
                TabBarView(tabManager: tabManager, windowController: windowController)
            }

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
                    // Settings and Help are ordinary views with no background of their
                    // own, so they carry the terminal's — and they must stay opaque
                    // even when the terminal is not, or the text sits on the desktop.
                    .background(tab.kind == .terminal ? bodyBackground : opaqueBodyBackground)
                    .zIndex(tab.id == tabManager.activeTab?.id ? 1 : 0)
                    .offset(x: tab.id == tabManager.activeTab?.id ? 0 : 99999)
                    .allowsHitTesting(tab.id == tabManager.activeTab?.id)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if isSoft {
                TabBarView(tabManager: tabManager, windowController: windowController)
            }
        }
        .frame(width: fullWidth, height: fullHeight)
    }

    private var panelChrome: some View {
        terminalContent
            .frame(width: fullWidth, height: animatedHeight, alignment: .top)
            .clipped()
            .clipShape(clipShape)
            .overlay(
                clipShape.stroke(
                    PanelChrome.border(style: windowController.chromeStyle),
                    lineWidth: isSoft ? 0.75 : 0.5
                )
            )
            .shadow(
                color: isVisible ? PanelChrome.shadow(style: windowController.chromeStyle) : .clear,
                radius: isSoft ? 18 : 10,
                x: 0,
                y: 6
            )
            .opacity(isVisible ? 1 : 0)
    }

    // MARK: - Resize

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
                    windowController.cachedWidth = windowController.terminalSize.width
                }
                resizePreview = nil
                dragStartSize = .zero
            }
    }

    private var horizontalInset: CGFloat {
        let screenW = windowController.resolvedScreen.frame.width
        return max((screenW - fullWidth) / 2, 0)
    }

    var body: some View {
        let screenW = windowController.panelWidth > 0
            ? windowController.panelWidth
            : windowController.resolvedScreen.frame.width

        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { windowController.hide() }
                .allowsHitTesting(isVisible && !windowController.isPinned)

            VStack(spacing: 0) {
                Color.clear.frame(height: menuBarHeight)

                ZStack(alignment: .top) {
                    // Center full-width (or % width) shelf under menu bar
                    HStack {
                        Spacer(minLength: 0)
                        panelChrome
                        Spacer(minLength: 0)
                    }

                    if let preview = resizePreview, isVisible {
                        clipShape
                            .stroke(Color.primary.opacity(0.25), lineWidth: 2)
                            .frame(width: preview.width, height: preview.height)
                    }

                    if isVisible {
                        VStack {
                            Spacer()
                                .frame(height: animatedHeight - 16)
                            HStack {
                                CornerResizeHandle(edge: .left)
                                    .gesture(cornerDragGesture(edge: .left))
                                    .padding(.leading, horizontalInset)
                                Spacer()
                                CornerResizeHandle(edge: .right)
                                    .gesture(cornerDragGesture(edge: .right))
                                    .padding(.trailing, horizontalInset)
                            }
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .frame(width: screenW)
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
                case .active: NSCursor.crosshair.push()
                case .ended: NSCursor.pop()
                }
            }
    }
}
