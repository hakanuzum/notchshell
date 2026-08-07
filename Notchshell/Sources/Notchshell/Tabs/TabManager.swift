import Foundation
import SwiftUI

struct Tab: Identifiable {
    let id: String
    let kind: TabKind
    let paneManager: PaneManager?
    var title: String
    var customTitle: String?
    /// The focused pane's working directory, as a name to show. Kept apart from
    /// `title` because they answer to different things: this follows `cd`, while
    /// `title` is whatever the shell last announced over OSC — which for a prompt that
    /// sets its own title is an abbreviated path frozen at the moment it was written.
    var directoryTitle: String?

    enum TabKind {
        case terminal
        case settings
        case help
    }

    var displayTitle: String {
        customTitle ?? directoryTitle ?? title
    }

    /// A directory as a tab name: its last component.
    ///
    /// The home directory used to be special-cased to `~`, the way most terminals write
    /// it. It read as a placeholder rather than a name — a fresh tab looked unnamed —
    /// so the exception is gone and home is named after its folder like anywhere else.
    /// One rule, no special cases.
    static func name(forDirectory path: String) -> String? {
        guard !path.isEmpty else { return nil }
        let standardized = (path as NSString).standardizingPath
        let last = (standardized as NSString).lastPathComponent
        return last.isEmpty ? standardized : last
    }

    /// Backward-compatible accessor: returns the focused pane's instance.
    var instance: TerminalInstance? {
        paneManager?.focusedInstance
    }

    /// Terminal tab
    init(directory: String? = nil) {
        let id = generateShortID()
        self.id = id
        self.kind = .terminal
        self.paneManager = PaneManager(directory: directory, tabID: id)
        self.title = "zsh"
        self.directoryTitle = directory.flatMap(Tab.name(forDirectory:))
    }

    /// Special tab (settings, help)
    init(kind: TabKind, title: String) {
        self.id = generateShortID()
        self.kind = kind
        self.paneManager = nil
        self.title = title
    }
}

@MainActor
final class TabManager: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var activeTabIndex: Int = 0
    @Published var hoveredTabIndex: Int? = nil
    @Published var editingTabID: String? = nil
    /// Tab id → the agent CLI running in it, refreshed by `agentMonitor` while the
    /// panel is on screen. Empty is the normal state; a tab without an entry shows
    /// no badge.
    @Published var agents: [String: AgentKind] = [:]

    private let agentMonitor = AgentMonitor()

    /// Stack of directories from recently closed tabs (for ⌘⇧T reopen)
    private var closedTabDirectories: [String] = []

    var activeTab: Tab? {
        guard activeTabIndex >= 0, activeTabIndex < tabs.count else { return nil }
        return tabs[activeTabIndex]
    }

    var theme: TerminalTheme = .default

    @AppStorage("terminalOpacity") private var savedOpacity: Double = 0.95

    private var splitObserver: Any?

    init() {
        theme.backgroundOpacity = savedOpacity
        restoreTabsOrDefault()
        // Listen for split requests from context menu (right-click in terminal)
        splitObserver = NotificationCenter.default.addObserver(
            forName: .splitRequest, object: nil, queue: .main
        ) { [weak self] notif in
            guard let self, let axis = notif.userInfo?["axis"] as? String,
                  let pm = self.activeTab?.paneManager else { return }
            pm.splitFocusedPane(axis: axis == "horizontal" ? .horizontal : .vertical)
        }
        agentMonitor.onChange = { [weak self] agents in
            self?.agents = agents
        }
    }

    func setOpacity(_ value: Double) {
        let clamped = min(max(value, 0.3), 1.0)
        theme.backgroundOpacity = clamped
        savedOpacity = clamped
        objectWillChange.send()
    }

    func addTab(in directory: String? = nil) {
        let tab = Tab(directory: directory)
        let tabID = tab.id

        // Wire PaneManager callbacks. These look the tab up by id on every call rather
        // than closing over the index it had when it was created: closing a tab to its
        // left shifts everything down, and an index captured here would then point at a
        // different tab — or past the end — and the guard would silently stop updating
        // this one for the rest of its life.
        tab.paneManager?.onFocusedTitleChange = { [weak self] title in
            guard let self, let index = self.tabs.firstIndex(where: { $0.id == tabID }) else { return }
            self.tabs[index].title = title
        }

        // Without this the tab name never followed `cd`. PaneManager has reported the
        // focused pane's directory all along and nothing was listening.
        tab.paneManager?.onFocusedDirectoryChange = { [weak self] directory in
            guard let self, let index = self.tabs.firstIndex(where: { $0.id == tabID }) else { return }
            self.tabs[index].directoryTitle = Tab.name(forDirectory: directory)
        }

        tab.paneManager?.onLastPaneClosed = { [weak self] in
            guard let self else { return }
            self.closeTab(id: tabID)
        }

        tabs.append(tab)
        activeTabIndex = tabs.count - 1
        focusTerminalInActiveTab()
    }

    func closeTab(id: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }

        // Save directory for ⌘⇧T reopen (terminal tabs only)
        if let pm = tabs[index].paneManager {
            let dir = pm.currentDirectory
            if !dir.isEmpty {
                closedTabDirectories.append(dir)
            }
            // Disconnect callbacks before terminating to prevent re-entrant closeTab
            pm.onLastPaneClosed = nil
            pm.rootPane.terminateAll()
        }

        tabs.remove(at: index)

        if tabs.isEmpty {
            addTab()
        } else if activeTabIndex >= tabs.count {
            activeTabIndex = tabs.count - 1
        }
    }

    func reopenClosedTab() {
        guard let dir = closedTabDirectories.popLast() else { return }
        addTab(in: dir)
    }

    var canReopenClosedTab: Bool {
        !closedTabDirectories.isEmpty
    }

    func renameTab(id: String, name: String?) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].customTitle = (name?.isEmpty ?? true) ? nil : name
    }

    // MARK: - Split Panes

    @discardableResult
    func splitActivePane(axis: Axis) -> Bool {
        guard let tab = activeTab, tab.kind == .terminal, let pm = tab.paneManager else { return false }
        return pm.splitFocusedPane(axis: axis)
    }

    func closeActivePane() {
        guard let tab = activeTab, tab.kind == .terminal, let pm = tab.paneManager else { return }
        pm.closePane(id: pm.focusedPaneID)
        // If last pane closed, onLastPaneClosed callback handles closeTab
    }

    func moveFocusInActiveTab(_ direction: PaneManager.NavigationDirection) {
        guard let tab = activeTab, let pm = tab.paneManager else { return }
        pm.moveFocus(direction)
    }

    // MARK: - Special Tabs

    func openSettings() {
        if let idx = tabs.firstIndex(where: { $0.kind == .settings }) {
            if activeTabIndex == idx {
                closeTab(id: tabs[idx].id)
            } else {
                selectTab(at: idx)
            }
            return
        }
        let tab = Tab(kind: .settings, title: "Settings")
        tabs.append(tab)
        activeTabIndex = tabs.count - 1
    }

    func openHelp() {
        if let idx = tabs.firstIndex(where: { $0.kind == .help }) {
            if activeTabIndex == idx {
                closeTab(id: tabs[idx].id)
            } else {
                selectTab(at: idx)
            }
            return
        }
        let tab = Tab(kind: .help, title: "Help")
        tabs.append(tab)
        activeTabIndex = tabs.count - 1
    }

    func closeSpecialTabs() {
        tabs.removeAll { $0.kind != .terminal }
        if tabs.isEmpty {
            addTab()
        } else if activeTabIndex >= tabs.count {
            activeTabIndex = tabs.count - 1
        }
    }

    // MARK: - Tab Navigation

    func moveTab(from source: Int, to destination: Int) {
        guard source != destination,
              source >= 0, source < tabs.count,
              destination >= 0, destination < tabs.count else { return }
        let tab = tabs.remove(at: source)
        tabs.insert(tab, at: destination)
        // Keep active tab index pointing to the same tab
        if activeTabIndex == source {
            activeTabIndex = destination
        } else if source < activeTabIndex && destination >= activeTabIndex {
            activeTabIndex -= 1
        } else if source > activeTabIndex && destination <= activeTabIndex {
            activeTabIndex += 1
        }
    }

    func selectTab(at index: Int) {
        guard index >= 0, index < tabs.count else { return }
        activeTabIndex = index
        focusTerminalInActiveTab()
    }

    func selectNextTab() {
        guard tabs.count > 1 else { return }
        activeTabIndex = (activeTabIndex + 1) % tabs.count
        focusTerminalInActiveTab()
    }

    func selectPreviousTab() {
        guard tabs.count > 1 else { return }
        activeTabIndex = (activeTabIndex - 1 + tabs.count) % tabs.count
        focusTerminalInActiveTab()
    }

    /// Make the focused pane's terminal view the first responder so it receives keyboard input.
    func focusTerminalInActiveTab() {
        guard let tab = activeTab, let pm = tab.paneManager,
              let backend = pm.focusedBackend else { return }
        let termView = backend.focusableView
        DispatchQueue.main.async {
            termView.window?.makeFirstResponder(termView)
        }
    }

    /// Tell every surface in every tab whether the panel is on screen.
    ///
    /// All tabs, not just the active one: the panel dropping away hides all of them,
    /// and restoring them all is what they were doing before this existed. Pausing
    /// background tabs too would be a further win, but it belongs to tab selection
    /// rather than to the panel.
    func setSurfacesVisible(_ visible: Bool) {
        for tab in tabs {
            tab.paneManager?.setSurfacesVisible(visible)
        }
        // The agent scan rides the same signal for the same reason: a panel that is
        // down is meant to cost nothing.
        agentMonitor.setActive(visible)
    }

    // MARK: - Tab State Persistence

    private static let savedTabsKey = "savedTabDirectories"
    private static let savedActiveIndexKey = "savedActiveTabIndex"

    /// Save current tab working directories to UserDefaults.
    func saveTabState() {
        let dirs = tabs.compactMap { tab -> String? in
            guard tab.kind == .terminal else { return nil }
            let dir = tab.paneManager?.currentDirectory ?? ""
            return dir.isEmpty ? "~" : dir
        }
        UserDefaults.standard.set(dirs, forKey: Self.savedTabsKey)
        UserDefaults.standard.set(activeTabIndex, forKey: Self.savedActiveIndexKey)
    }

    /// Restore tabs from saved state or create a default tab.
    private func restoreTabsOrDefault() {
        guard UserDefaults.standard.bool(forKey: "restoreTabsOnLaunch"),
              let dirs = UserDefaults.standard.stringArray(forKey: Self.savedTabsKey),
              !dirs.isEmpty else {
            addTab()
            return
        }

        for dir in dirs {
            let resolved = dir == "~" ? nil : dir
            addTab(in: resolved)
        }

        let savedIndex = UserDefaults.standard.integer(forKey: Self.savedActiveIndexKey)
        if savedIndex >= 0 && savedIndex < tabs.count {
            activeTabIndex = savedIndex
        }
    }
}
