import SwiftUI
import AppKit

/// Recursively renders a PaneNode tree as split terminal views.
struct PaneSplitView: View {
    private let explicitNode: PaneNode?
    @ObservedObject var paneManager: PaneManager
    @ObservedObject var tabManager: TabManager
    var theme: TerminalTheme

    /// The split ratio at the moment a divider drag began, so the drag can be measured
    /// as a translation from it rather than from the divider's shifting position.
    @State private var dragStartRatio: CGFloat? = nil

    /// Root init — reads paneManager.rootPane directly so ForEach cache doesn't stale it.
    init(paneManager: PaneManager, tabManager: TabManager, theme: TerminalTheme) {
        self.explicitNode = nil
        self.paneManager = paneManager
        self.tabManager = tabManager
        self.theme = theme
    }

    /// Recursive init — uses a specific subtree node.
    init(node: PaneNode, paneManager: PaneManager, tabManager: TabManager, theme: TerminalTheme) {
        self.explicitNode = node
        self.paneManager = paneManager
        self.tabManager = tabManager
        self.theme = theme
    }

    private var node: PaneNode {
        explicitNode ?? paneManager.rootPane
    }

    /// Minimum pane size in points.
    private let minPaneSize: CGFloat = 40

    var body: some View {
        switch node {
        case .leaf(let id, let backend):
            ZStack {
                TerminalContentView(backend: backend, theme: theme)

                // Focus indicator when multiple panes exist
                if paneManager.focusedPaneID == id && paneManager.rootPane.leafCount > 1 {
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.accentColor.opacity(0.6), lineWidth: 2)
                        .padding(1)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                paneManager.focusedPaneID = id
                tabManager.focusTerminalInActiveTab()
            })
            .contextMenu {
                Button("Split Right") {
                    paneManager.splitPane(id: id, axis: .horizontal)
                }
                Button("Split Down") {
                    paneManager.splitPane(id: id, axis: .vertical)
                }

                Divider()

                if paneManager.rootPane.leafCount > 1 {
                    Button("Close Pane") {
                        paneManager.closePane(id: id)
                    }

                    Divider()
                }

                Button("New Tab Here") {
                    let dir = paneManager.focusedInstance?.currentDirectory
                    tabManager.addTab(in: dir)
                }
            }

        case .split(let splitID, let axis, let first, let second, let ratio):
            GeometryReader { geo in
                if axis == .horizontal {
                    let firstWidth = (geo.size.width - 1) * ratio
                    HStack(spacing: 0) {
                        PaneSplitView(node: first, paneManager: paneManager, tabManager: tabManager, theme: theme)
                            .frame(width: firstWidth)

                        SplitDivider(axis: .horizontal)
                            .gesture(DragGesture()
                                .onChanged { value in
                                    // Drive the ratio from the drag's translation off a
                                    // captured start, not value.location. location is in
                                    // the divider's own frame, and the divider moves as
                                    // the ratio changes — so reading it fed the divider's
                                    // motion back into the ratio and the split juddered.
                                    let start = dragStartRatio ?? ratio
                                    if dragStartRatio == nil { dragStartRatio = ratio }
                                    let delta = value.translation.width / geo.size.width
                                    let clamped = min(max(start + delta, minPaneSize / geo.size.width),
                                                      1 - minPaneSize / geo.size.width)
                                    paneManager.updateSplitRatio(splitID: splitID, ratio: clamped)
                                }
                                .onEnded { _ in dragStartRatio = nil }
                            )
                            .onTapGesture(count: 2) {
                                paneManager.updateSplitRatio(splitID: splitID, ratio: 0.5)
                            }

                        PaneSplitView(node: second, paneManager: paneManager, tabManager: tabManager, theme: theme)
                    }
                } else {
                    let firstHeight = (geo.size.height - 1) * ratio
                    VStack(spacing: 0) {
                        PaneSplitView(node: first, paneManager: paneManager, tabManager: tabManager, theme: theme)
                            .frame(height: firstHeight)

                        SplitDivider(axis: .vertical)
                            .gesture(DragGesture()
                                .onChanged { value in
                                    let start = dragStartRatio ?? ratio
                                    if dragStartRatio == nil { dragStartRatio = ratio }
                                    let delta = value.translation.height / geo.size.height
                                    let clamped = min(max(start + delta, minPaneSize / geo.size.height),
                                                      1 - minPaneSize / geo.size.height)
                                    paneManager.updateSplitRatio(splitID: splitID, ratio: clamped)
                                }
                                .onEnded { _ in dragStartRatio = nil }
                            )
                            .onTapGesture(count: 2) {
                                paneManager.updateSplitRatio(splitID: splitID, ratio: 0.5)
                            }

                        PaneSplitView(node: second, paneManager: paneManager, tabManager: tabManager, theme: theme)
                    }
                }
            }
        }
    }
}

/// Draggable divider between split panes.
/// Visible line is 1pt, but hit target is 7pt wide for easy grabbing.
private struct SplitDivider: View {
    let axis: Axis

    var body: some View {
        ZStack {
            // Invisible hit target
            Rectangle()
                .fill(Color.clear)
                .frame(
                    width: axis == .horizontal ? 7 : nil,
                    height: axis == .vertical ? 7 : nil
                )
                .contentShape(Rectangle())

            // Visible divider line
            Rectangle()
                .fill(Color.gray.opacity(0.4))
                .frame(
                    width: axis == .horizontal ? 1 : nil,
                    height: axis == .vertical ? 1 : nil
                )
        }
        .frame(
            width: axis == .horizontal ? 7 : nil,
            height: axis == .vertical ? 7 : nil
        )
        .onHover { hovering in
            if hovering {
                if axis == .horizontal {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.resizeUpDown.push()
                }
            } else {
                NSCursor.pop()
            }
        }
    }
}
