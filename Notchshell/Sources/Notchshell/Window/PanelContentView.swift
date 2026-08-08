import SwiftUI

/// Root SwiftUI view inside TerminalPanel.
/// Top-docked shelf: full-width under menu bar; soft chrome puts tabs on the BOTTOM.
struct PanelContentView: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var windowController: WindowController

    @State private var dragStartSize: CGSize = .zero
    @State private var resizePreview: CGSize? = nil

    /// Transient "copied N chars" confirmation, shown in the terminal's bottom-right
    /// after a copy-on-select. `copyToastToken` cancels a pending dismissal when a new
    /// copy arrives before the last has faded.
    @State private var copyToast: String? = nil
    @State private var copyToastToken = 0

    private var isVisible: Bool {
        windowController.state == .visible
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

    private var menuBarHeight: CGFloat { windowController.menuBarHeight }

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

    /// Settings sidebar width: 30% of the shelf, with a floor so it stays usable on a
    /// narrow panel.
    private var settingsSidebarWidth: CGFloat {
        max(fullWidth * 0.30, 280)
    }

    // MARK: - Content: terminal body + tab bar placement

    private var terminalContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
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
                .overlay(alignment: .bottomTrailing) {
                    if let copyToast {
                        Text(copyToast)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.black.opacity(0.72), in: Capsule())
                            .padding(16)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .terminalDidCopy)) { note in
                    let count = note.userInfo?["count"] as? Int ?? 0
                    copyToastToken += 1
                    let token = copyToastToken
                    withAnimation(.easeOut(duration: 0.15)) {
                        copyToast = "copied \(count) chars to clipboard"
                    }
                    // Hold, then fade — unless another copy has since replaced it.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        guard token == copyToastToken else { return }
                        withAnimation(.easeOut(duration: 0.3)) { copyToast = nil }
                    }
                }

                // Settings, docked to the trailing edge at 30% of the shelf width. The
                // terminal keeps the rest — a real side panel, not an overlay. It appears
                // and disappears instantly: a slide animation flickered the desktop
                // through the translucent terminal, and it is opaque so its text never
                // falls onto whatever shows through the terminal.
                if windowController.showSettingsSidebar {
                    Rectangle()
                        .fill(PanelChrome.border(style: windowController.chromeStyle))
                        .frame(width: 0.5)
                    SettingsView(windowController: windowController)
                        .frame(width: settingsSidebarWidth)
                        .background(opaqueBodyBackground)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // The tab bar sits below the terminal, in both palettes. A folder tab flares
            // upward to meet the content above it, which only works on this edge.
            TabBarView(tabManager: tabManager, windowController: windowController)
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
                    lineWidth: 0.75
                )
            )
            .shadow(
                color: isVisible ? PanelChrome.shadow(style: windowController.chromeStyle) : .clear,
                radius: 18,
                x: 0,
                y: 6
            )
            .opacity(isVisible ? 1 : 0)
            // Over the terminal rather than in the tab bar: the palette is a place you
            // go, and it wants the height. Anchored to the top so it does not move as
            // the list under it grows and shrinks with what you type.
            .overlay(alignment: .top) {
                if windowController.showCommandPalette && isVisible {
                    CommandPalette(windowController: windowController) {
                        windowController.showCommandPalette = false
                    }
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.75)
                    )
                    .shadow(color: .black.opacity(0.35), radius: 22, y: 10)
                    .padding(.top, 40)
                    // The panel's chrome setting, not the system appearance. They agree
                    // on Auto, but Light and Dark *force* the chrome, and a palette
                    // following macOS instead would come up light on a panel the user
                    // set to dark. The tab bar and Settings resolve it the same way.
                    //
                    // Last, so it wraps the background too. Applied before it, the text
                    // turned dark-mode white while `.regularMaterial` kept resolving in
                    // the outer environment and stayed light — white on white.
                    .environment(\.colorScheme,
                                 PanelChrome.colorScheme(style: windowController.chromeStyle))
                }
            }
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
