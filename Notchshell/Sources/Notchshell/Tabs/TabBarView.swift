import SwiftUI
import AppKit

struct TabBarView: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var windowController: WindowController
    @State private var showTabList = false
    @State private var showThemePicker = false
    @State private var tabsOverflow = false
    @State private var draggedTabID: String?
    @State private var showOpacitySlider = false
    @State private var showFontSizeSlider = false
    @State private var opacity = TerminalAppearanceSettings.backgroundOpacity
    @State private var fontSize = TerminalAppearanceSettings.fontSize
    @State private var lastLiveApply = Date.distantPast

    /// Write a setting while the slider is moving.
    ///
    /// Each apply rewrites `overrides.conf` and reparses the whole config, which is far
    /// more than a drag frame needs. Throttle the live ones and always take the release,
    /// so the value that lands in the file is the value under the pointer.
    private func applyLive(_ setting: TerminalSetting, _ text: String, committed: Bool) {
        guard committed || Date().timeIntervalSince(lastLiveApply) > 0.1 else { return }
        lastLiveApply = Date()
        GhosttyApp.shared.apply(setting, to: text)
    }

    private var chrome: PanelChromeStyle {
        windowController.chromeStyle
    }

    private var isSoft: Bool {
        PanelChrome.isSoftLight(chrome)
    }

    private var barHeight: CGFloat { windowController.tabBarHeight }

    private var tabHeight: CGFloat {
        max(barHeight - FolderTab.barMargin, 20)
    }

    var body: some View {
        Group {
            if isSoft {
                // Unclutter: tabs + controls on the BOTTOM strip
                softBottomBar
            } else {
                classicTopBar
            }
        }
        .environment(\.colorScheme, PanelChrome.colorScheme(style: chrome))
        .contentShape(Rectangle())
    }

    // MARK: - Soft bottom bar (tabs left · palette / + / … right)

    private var softBottomBar: some View {
        // Top-aligned: a folder tab has to touch the terminal above it, so the tab row
        // hangs from the bar's top edge and the slack falls below.
        HStack(alignment: .top, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                // Negative spacing by exactly one slant: each tab's leading diagonal
                // lands on its neighbour's trailing diagonal, so the pair share one
                // edge instead of showing two and a gap.
                HStack(spacing: -FolderTab.slant) {
                    ForEach(Array(tabManager.tabs.enumerated()), id: \.element.id) { index, tab in
                        FolderTab(
                            title: shortTitle(tab.displayTitle),
                            kind: tab.kind,
                            isActive: index == tabManager.activeTabIndex,
                            onSelect: { tabManager.selectTab(at: index) },
                            onClose: { tabManager.closeTab(id: tab.id) },
                            onHover: { hovered in
                                tabManager.hoveredTabIndex = hovered ? index : nil
                            },
                            height: tabHeight
                        )
                        // The active tab overlaps both neighbours; the rest stack
                        // leftmost-on-top, which is the direction the diagonals imply.
                        .zIndex(
                            index == tabManager.activeTabIndex
                                ? Double(tabManager.tabs.count + 1)
                                : Double(tabManager.tabs.count - index)
                        )
                        .opacity(draggedTabID == tab.id ? 0.4 : 1.0)
                        .onDrag {
                            draggedTabID = tab.id
                            return NSItemProvider(object: tab.id as NSString)
                        }
                        .onDrop(of: [.text], delegate: TabDropDelegate(
                            tabManager: tabManager,
                            targetTabID: tab.id,
                            draggedTabID: $draggedTabID
                        ))
                    }

                    // New tab sits where the tabs end, not across the bar with the
                    // settings icons — it belongs to the row it extends.
                    Button(action: { tabManager.addTab() }) {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(FolderTabPalette.barIcon)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("New Tab")
                    // Clear the last tab's trailing diagonal before starting.
                    .padding(.leading, FolderTab.slant + 4)
                    .zIndex(0)
                }
                .padding(.leading, 8)
                .padding(.trailing, FolderTab.slant)
            }
            // A ScrollView takes all the height it is offered, so pin it to the tabs'.
            .frame(height: tabHeight)

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                if tabManager.tabs.count > 3 {
                    Button(action: { showTabList.toggle() }) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(FolderTabPalette.barIcon)
                            .frame(width: 24, height: 20)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showTabList, arrowEdge: .top) {
                        TabListPopover(tabManager: tabManager, onDismiss: { showTabList = false })
                    }
                }

                // Palette — right side
                Button(action: { showThemePicker.toggle() }) {
                    Image(systemName: "paintpalette")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(FolderTabPalette.barIcon)
                        .frame(width: 26, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Themes")
                .popover(isPresented: $showThemePicker, arrowEdge: .top) {
                    ThemePickerPopover(windowController: windowController) {
                        showThemePicker = false
                    }
                }
                .onChange(of: showThemePicker) { _, open in
                    if open {
                        windowController.beginTransientInteraction(seconds: 120)
                    } else {
                        windowController.beginTransientInteraction(seconds: 0.8)
                    }
                }

                RecordButton(windowController: windowController, recorder: windowController.recorder)

                // Opacity — the icon is the overlapping-discs mark that means exactly
                // this, and the striped half is what a translucent surface looks like.
                Button(action: { showOpacitySlider.toggle() }) {
                    Image(systemName: "circle.lefthalf.striped.horizontal")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(FolderTabPalette.barIcon)
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Background Opacity")
                .popover(isPresented: $showOpacitySlider, arrowEdge: .top) {
                    BarSliderPopover(
                        title: "Opacity",
                        maxIcon: "circle.fill",
                        minIcon: "circle",
                        value: $opacity,
                        range: TerminalAppearanceSettings.opacityRange,
                        format: { "\(Int(($0 * 100).rounded()))%" },
                        onEditingChanged: { editing in
                            applyLive(.backgroundOpacity,
                                      String(format: "%.2f", opacity),
                                      committed: !editing)
                        }
                    )
                    // The file is the source of truth; someone may have changed it in
                    // Settings since this view was built.
                    .onAppear { opacity = TerminalAppearanceSettings.backgroundOpacity }
                }
                .onChange(of: showOpacitySlider) { _, open in
                    windowController.beginTransientInteraction(seconds: open ? 120 : 0.8)
                }

                Button(action: { showFontSizeSlider.toggle() }) {
                    // `textformat.size` (an A with a size marker), not a magnifying glass
                    // — the loupe read as Find, which is a different thing entirely.
                    Image(systemName: "textformat.size")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(FolderTabPalette.barIcon)
                        .frame(width: 24, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Font Size")
                .popover(isPresented: $showFontSizeSlider, arrowEdge: .top) {
                    BarSliderPopover(
                        title: "Font Size",
                        maxIcon: "textformat.size.larger",
                        minIcon: "textformat.size.smaller",
                        value: $fontSize,
                        range: TerminalAppearanceSettings.fontSizeRange,
                        format: { "\(Int($0.rounded())) pt" },
                        onEditingChanged: { editing in
                            applyLive(.fontSize,
                                      String(Int(fontSize.rounded())),
                                      committed: !editing)
                        }
                    )
                    .onAppear { fontSize = TerminalAppearanceSettings.fontSize }
                }
                .onChange(of: showFontSizeSlider) { _, open in
                    windowController.beginTransientInteraction(seconds: open ? 120 : 0.8)
                }

                // The trailing control is a sidebar toggle, not a menu: it opens Settings
                // in a panel on the right rather than dropping a list of actions. Pin,
                // Hide and Help kept their keyboard shortcuts (⌘⇧P, ⌥Space, ⌘/) and the
                // menu-bar item; they no longer need a home on the tab bar.
                Button {
                    windowController.openSettings()
                } label: {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(windowController.showSettingsSidebar
                                         ? FolderTabPalette.barIconActive
                                         : FolderTabPalette.barIcon)
                        .frame(width: 24, height: 20)
                }
                .buttonStyle(.plain)
                .help("Settings")
            }
            // Full bar height, not tabHeight: the tabs are top-aligned so they join the
            // terminal, but these icons are plain controls and should sit centred in the
            // whole bar. At tabHeight they centred only in the top strip and read as
            // nudged up, with the bar's bottom margin empty beneath them.
            .frame(height: barHeight)
            .padding(.trailing, 10)
        }
        // `alignment: .top` is load-bearing. Without it `.frame` centres the tab row in
        // the taller bar, leaving a strip of bar between the tabs and the terminal —
        // which is the join the whole shape exists to make.
        .frame(height: barHeight, alignment: .top)
        .background(FolderTabPalette.bar)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(FolderTabPalette.barTopEdge)
                .frame(height: 0.5)
        }
        // Drawn last so its hit area sits above the bar, and centred because that is
        // the one stretch holding neither tabs nor icons.
        .overlay(alignment: .bottom) {
            PanelResizeGrabber(windowController: windowController)
        }
        // ⌘-scroll and pinch change the font from over the terminal; keep the slider's
        // value in step so it does not snap back to a stale number when next opened.
        .onReceive(NotificationCenter.default.publisher(for: .terminalFontSizeDidChange)) { _ in
            fontSize = TerminalAppearanceSettings.fontSize
        }
    }

    // MARK: - Classic dark top bar (fallback)

    private var classicTopBar: some View {
        HStack(spacing: 0) {
            GeometryReader { outerGeo in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        HStack(spacing: 1) {
                            ForEach(Array(tabManager.tabs.enumerated()), id: \.element.id) { index, tab in
                                TabItemView(
                                    tabID: tab.id,
                                    index: index + 1,
                                    title: shortTitle(tab.displayTitle),
                                    kind: tab.kind,
                                    isActive: index == tabManager.activeTabIndex,
                                    hasCustomTitle: tab.customTitle != nil,
                                    isEditing: Binding(
                                        get: { tabManager.editingTabID == tab.id },
                                        set: { editing in
                                            tabManager.editingTabID = editing ? tab.id : nil
                                        }
                                    ),
                                    onSelect: { tabManager.selectTab(at: index) },
                                    onClose: { tabManager.closeTab(id: tab.id) },
                                    onRename: { name in
                                        tabManager.renameTab(id: tab.id, name: name)
                                    },
                                    onHover: { hovered in
                                        tabManager.hoveredTabIndex = hovered ? index : nil
                                    }
                                )
                                .opacity(draggedTabID == tab.id ? 0.4 : 1.0)
                                .onDrag {
                                    draggedTabID = tab.id
                                    return NSItemProvider(object: tab.id as NSString)
                                }
                                .onDrop(of: [.text], delegate: TabDropDelegate(
                                    tabManager: tabManager,
                                    targetTabID: tab.id,
                                    draggedTabID: $draggedTabID
                                ))
                            }
                        }
                        .padding(.leading, 4)
                        .background(GeometryReader { innerGeo in
                            Color.clear.onChange(of: tabManager.tabs.count) {
                                tabsOverflow = innerGeo.size.width > outerGeo.size.width
                            }
                            .onAppear {
                                tabsOverflow = innerGeo.size.width > outerGeo.size.width
                            }
                        })

                        Color.clear.frame(maxWidth: .infinity)
                    }
                    .frame(minWidth: outerGeo.size.width, alignment: .leading)
                }
            }
            .overlay(DoubleClickCatcher { [weak tabManager] in
                guard let tabManager, tabManager.hoveredTabIndex == nil else { return }
                tabManager.addTab()
            })

            if tabsOverflow {
                Button(action: { showTabList.toggle() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showTabList, arrowEdge: .bottom) {
                    TabListPopover(tabManager: tabManager, onDismiss: { showTabList = false })
                }
            }

            Spacer()

            Button(action: { windowController.isPinned.toggle() }) {
                Image(systemName: windowController.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(windowController.isPinned ? .yellow.opacity(0.9) : .secondary)
                    .rotationEffect(.degrees(windowController.isPinned ? 0 : 45))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)

            Button(action: { showThemePicker.toggle() }) {
                Image(systemName: "paintpalette")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Themes")
            .popover(isPresented: $showThemePicker, arrowEdge: .bottom) {
                ThemePickerPopover(windowController: windowController) {
                    showThemePicker = false
                }
            }
            .onChange(of: showThemePicker) { _, open in
                if open {
                    windowController.beginTransientInteraction(seconds: 120)
                } else {
                    windowController.beginTransientInteraction(seconds: 0.8)
                }
            }

            Button(action: { windowController.openSettings() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)

            Button(action: { tabManager.addTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
        }
        .padding(.top, 4)
        .frame(height: 36)
        .background(Color.black.opacity(0.85))
    }

    private func shortTitle(_ title: String) -> String {
        tabShortTitle(title)
    }
}

func tabShortTitle(_ title: String) -> String {
    let components = title.split(separator: "/")
    return components.last.map(String.init) ?? title
}

struct TabItemView: View {
    let tabID: String
    let index: Int
    let title: String
    let kind: Tab.TabKind
    let isActive: Bool
    let hasCustomTitle: Bool
    @Binding var isEditing: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    let onRename: (String?) -> Void
    let onHover: (Bool) -> Void

    @State private var isHovered = false
    @State private var editText = ""
    @FocusState private var fieldFocused: Bool

    private var icon: String? {
        switch kind {
        case .settings: return "gearshape"
        case .help: return "questionmark.circle"
        case .terminal: return nil
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10))
                        .foregroundColor(isActive ? .primary : .secondary)
                }
                if isEditing {
                    TextField("Tab name", text: $editText, onCommit: {
                        onRename(editText.isEmpty ? nil : editText)
                        isEditing = false
                    })
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(maxWidth: 120)
                    .focused($fieldFocused)
                    .onExitCommand { isEditing = false }
                    .onChange(of: fieldFocused) {
                        if !fieldFocused {
                            onRename(editText.isEmpty ? nil : editText)
                            isEditing = false
                        }
                    }
                    .onAppear { fieldFocused = true }
                } else {
                    Text(title)
                        .font(.system(size: 11))
                        .foregroundColor(isActive ? .primary : .secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 120)
                }
                if kind == .terminal && index <= 9 {
                    Text("⌘\(index)")
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.5))
                }
            }
            .contentShape(Rectangle())
            .overlay(MouseDownOverlay(
                action: { onSelect() },
                doubleAction: kind == .terminal ? {
                    editText = hasCustomTitle ? title : ""
                    isEditing = true
                } : nil
            ))

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 14, height: 14)
                    .background(Circle().fill(Color.primary.opacity(isHovered ? 0.1 : 0)))
            }
            .buttonStyle(.plain)
            .opacity(isHovered || isActive ? 1 : 0.3)
            .allowsHitTesting(isHovered || isActive)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isActive
                        ? Color.primary.opacity(0.10)
                        : (isHovered ? Color.primary.opacity(0.05) : Color.clear)
                )
        )
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)
        }
    }
}

// MARK: - Mouse / double-click / tab list / drag helpers

struct MouseDownOverlay: NSViewRepresentable {
    let action: () -> Void
    let doubleAction: (() -> Void)?

    func makeNSView(context: Context) -> MouseDownNSView {
        let v = MouseDownNSView()
        v.action = action
        v.doubleAction = doubleAction
        return v
    }

    func updateNSView(_ v: MouseDownNSView, context: Context) {
        v.action = action
        v.doubleAction = doubleAction
    }
}

final class MouseDownNSView: NSView {
    var action: (() -> Void)?
    var doubleAction: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount >= 2, let doubleAction {
            doubleAction()
        } else {
            action?()
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

struct DoubleClickCatcher: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> DoubleClickNSView {
        let v = DoubleClickNSView()
        v.onDoubleClick = action
        return v
    }

    func updateNSView(_ v: DoubleClickNSView, context: Context) {
        v.onDoubleClick = action
    }
}

final class DoubleClickNSView: NSView {
    var onDoubleClick: (() -> Void)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil && monitor == nil {
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, event.clickCount >= 2 else { return event }
                let loc = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(loc) else { return event }
                let winLoc = event.locationInWindow
                if let hitView = self.window?.contentView?.hitTest(winLoc) {
                    var current: NSView? = hitView
                    var depth = 0
                    while let v = current, depth < 20 {
                        if v is MouseDownNSView || v is NSButton || v is NSTextField {
                            return event
                        }
                        if v.gestureRecognizers.contains(where: { $0 is NSClickGestureRecognizer }) {
                            return event
                        }
                        current = v.superview
                        depth += 1
                    }
                }
                self.onDoubleClick?()
                return event
            }
        } else if window == nil, let m = monitor {
            NSEvent.removeMonitor(m)
            monitor = nil
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    deinit {
        if let m = monitor { NSEvent.removeMonitor(m) }
    }
}

struct TabListPopover: View {
    @ObservedObject var tabManager: TabManager
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(tabManager.tabs.enumerated()), id: \.element.id) { index, tab in
                HStack(spacing: 8) {
                    if tab.kind != .terminal {
                        Image(systemName: tab.kind == .settings ? "gearshape" : "questionmark.circle")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    Text(tab.displayTitle)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundColor(index == tabManager.activeTabIndex ? .primary : .secondary)
                    Spacer()
                    Button(action: {
                        tabManager.closeTab(id: tab.id)
                        if tabManager.tabs.count <= 1 { onDismiss() }
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 16, height: 16)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(index == tabManager.activeTabIndex ? Color.primary.opacity(0.08) : Color.clear)
                )
                .onTapGesture {
                    tabManager.selectTab(at: index)
                    onDismiss()
                }
            }
        }
        .padding(6)
        .frame(minWidth: 180)
    }
}

struct TabDropDelegate: DropDelegate {
    let tabManager: TabManager
    let targetTabID: String
    @Binding var draggedTabID: String?

    func performDrop(info: DropInfo) -> Bool {
        draggedTabID = nil
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let draggedID = draggedTabID, draggedID != targetTabID else { return }
        guard let from = tabManager.tabs.firstIndex(where: { $0.id == draggedID }),
              let to = tabManager.tabs.firstIndex(where: { $0.id == targetTabID }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            tabManager.moveTab(from: from, to: to)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggedTabID != nil
    }
}
