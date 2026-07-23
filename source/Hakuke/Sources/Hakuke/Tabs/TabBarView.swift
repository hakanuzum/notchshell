import SwiftUI
import AppKit

struct TabBarView: View {
    @ObservedObject var tabManager: TabManager
    @ObservedObject var windowController: WindowController
    @State private var showTabList = false
    @State private var tabsOverflow = false
    @State private var draggedTabID: String?

    var body: some View {
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
                                    onSelect: {
                                        tabManager.selectTab(at: index)
                                    },
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

                        // Spacer to fill remaining width
                        Color.clear
                            .frame(maxWidth: .infinity)
                    }
                    .frame(minWidth: outerGeo.size.width, alignment: .leading)
                }
            }
            .overlay(DoubleClickCatcher { [weak tabManager] in
                guard let tabManager, tabManager.hoveredTabIndex == nil else { return }
                tabManager.addTab()
            })

            // Tab list button — visible when tabs overflow
            if tabsOverflow {
                Button(action: { showTabList.toggle() }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                                .popover(isPresented: $showTabList, arrowEdge: .bottom) {
                    TabListPopover(tabManager: tabManager, onDismiss: { showTabList = false })
                }
            }

            Spacer()

            // Pin button
            Button(action: { windowController.isPinned.toggle() }) {
                Image(systemName: windowController.isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(windowController.isPinned ? .yellow.opacity(0.9) : .secondary)
                    .rotationEffect(.degrees(windowController.isPinned ? 0 : 45))
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(windowController.isPinned ? Color.white.opacity(0.1) : Color.clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(windowController.isPinned ? "Unpin (auto-hide on focus loss)" : "Pin (stay visible)")
            .animation(.easeInOut(duration: 0.15), value: windowController.isPinned)
            
            // Settings button
            Button(action: { windowController.openSettings() }) {
                Image(systemName: "gearshape")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Settings")
            
            Button(action: { tabManager.addTab() }) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 8)
                    }
        .padding(.top, 4)
        .frame(height: 36)
        .background(Color.black.opacity(0.85))
        .environment(\.colorScheme, .dark)
        .contentShape(Rectangle())
    }

    private func shortTitle(_ title: String) -> String {
        tabShortTitle(title)
    }
}

/// Extract last path component for tab display. Testable free function.
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
            // Clickable content area (icon + text + badge)
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
                    .onExitCommand {
                        isEditing = false
                    }
                    .onChange(of: fieldFocused) {
                        if !fieldFocused {
                            onRename(editText.isEmpty ? nil : editText)
                            isEditing = false
                        }
                    }
                    .onAppear {
                        fieldFocused = true
                    }
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

            // Close button — separate from tap gesture area
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 14, height: 14)
                    .background(
                        Circle()
                            .fill(Color.primary.opacity(isHovered ? 0.1 : 0))
                    )
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
                .fill(isActive ? Color.primary.opacity(0.1) : (isHovered ? Color.primary.opacity(0.05) : Color.clear))
        )
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)
        }
    }
}

// MARK: - MouseDown handler for instant tab clicks

/// Transparent NSView overlay that fires actions on mouseDown.
/// Single click calls `action`, double click calls `doubleAction`.
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

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}

// MARK: - Double-click catcher (pass-through overlay using event monitor)

/// Detects double-clicks anywhere in its bounds without blocking other events.
/// Uses a local event monitor so buttons and tabs underneath still work.
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
                // Only fire on empty space — skip if another interactive view handles this click.
                // Walk up the hit view hierarchy checking for known interactive types
                // or SwiftUI gesture recognizers (installed by .onTapGesture on tab items).
                let winLoc = event.locationInWindow
                if let hitView = self.window?.contentView?.hitTest(winLoc) {
                    var current: NSView? = hitView
                    var depth = 0
                    // Walk up ~20 levels — enough to find SwiftUI gesture recognizers
                    // on tab items without reaching high-level views (e.g. dismiss gesture)
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

// MARK: - Tab list popover

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
                            .background(Circle().fill(Color.primary.opacity(0.05)))
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

// MARK: - Tab drag & drop

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
