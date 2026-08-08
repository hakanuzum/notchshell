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
    /// Tabs that asked for attention while you were looking elsewhere. Looking at one
    /// is the answer, so selecting a tab clears it.
    @Published private(set) var attentionTabIDs: Set<String> = []

    private let agentMonitor = AgentMonitor()

    /// Whether the panel is on screen. An ask that arrives while you are already
    /// reading the tab is not worth interrupting you over, and this is half of
    /// knowing that — `activeTabIndex` is the other half.
    private var panelVisible: Bool = false

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
            guard let self else { return }
            self.agents = agents
            self.recordAgentsSeen(agents)
            self.refreshDormantAgents()
        }
    }

    func setOpacity(_ value: Double) {
        let clamped = min(max(value, 0.3), 1.0)
        theme.backgroundOpacity = clamped
        savedOpacity = clamped
        objectWillChange.send()
    }

    func addTab(in directory: String? = nil,
                layout: SavedPane? = nil,
                customTitle: String? = nil) {
        var tab = Tab(directory: directory)
        tab.customTitle = customTitle
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
            // `cd` into a project you have used an agent in should say so straight away,
            // not on the agent monitor's next tick.
            self.refreshDormantAgents()
        }

        tab.paneManager?.onLastPaneClosed = { [weak self] in
            guard let self else { return }
            self.closeTab(id: tabID)
        }

        tab.paneManager?.onAttention = { [weak self] title, body in
            self?.handleAttention(tabID: tabID, title: title, body: body)
        }

        // After the callbacks are wired, so the rebuilt panes report through them, and
        // before the tab is on screen, so the shape is already right when it appears.
        if let layout { tab.paneManager?.restoreLayout(layout) }

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
        attentionTabIDs.remove(id)
        TerminalNotifier.shared.clear(tabID: id)

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

    func toggleZoomInActiveTab() {
        guard let tab = activeTab, tab.kind == .terminal, let pm = tab.paneManager else { return }
        pm.toggleZoom()
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

    // MARK: - Agent history

    /// Tab id → agents that have run in that tab's directory before but are not running
    /// in it now. This is what turns the badge slot from a live indicator into a way
    /// back: a directory you have used an agent in says so when you return to it.
    @Published private(set) var dormantAgents: [String: [AgentKind]] = [:]

    private func recordAgentsSeen(_ agents: [String: AgentKind]) {
        for (tabID, agent) in agents {
            guard let tab = tabs.first(where: { $0.id == tabID }),
                  let directory = tab.paneManager?.currentDirectory,
                  !directory.isEmpty else { continue }
            AgentHistoryStore.shared.record(agent: agent, in: directory)
        }
    }

    /// A tab shows a dormant badge only when nothing is running in it — a live agent
    /// already owns that slot, and it says more.
    func refreshDormantAgents() {
        var next: [String: [AgentKind]] = [:]
        for tab in tabs where tab.kind == .terminal {
            guard agents[tab.id] == nil,
                  let directory = tab.paneManager?.currentDirectory,
                  !directory.isEmpty else { continue }
            let past = AgentHistoryStore.shared.agents(in: directory).compactMap(\.kind)
            if !past.isEmpty { next[tab.id] = past }
        }
        if next != dormantAgents { dormantAgents = next }
    }

    /// Run an agent's own resume command in the tab's focused pane.
    ///
    /// Typed in and entered, exactly as you would have. Notchshell does not know what
    /// sessions exist — the tool takes it from here.
    func resumeAgent(tabID: String, command: String) {
        guard let tab = tabs.first(where: { $0.id == tabID }),
              let backend = tab.paneManager?.focusedBackend else { return }
        backend.send(text: command + "\n")
    }

    // MARK: - Attention

    /// A pane asked for attention. Whether that is worth interrupting you over depends
    /// entirely on where you are looking.
    private func handleAttention(tabID: String, title: String, body: String) {
        guard let index = tabs.firstIndex(where: { $0.id == tabID }) else { return }
        // Already watching it. The ask has been answered by the time it arrived.
        if panelVisible && index == activeTabIndex { return }

        attentionTabIDs.insert(tabID)

        let tabName = tabs[index].displayTitle
        // A bell carries no text of its own, so the tab has to speak for it.
        TerminalNotifier.shared.notify(
            title: title.isEmpty ? AppIdentity.displayName : title,
            subtitle: tabName,
            body: body.isEmpty ? "\(tabName) wants your attention" : body,
            tabID: tabID
        )
    }

    /// Looking at a tab clears its mark, in the tab bar and in Notification Centre.
    private func clearAttentionForActiveTab() {
        guard let tab = activeTab, attentionTabIDs.contains(tab.id) else { return }
        attentionTabIDs.remove(tab.id)
        TerminalNotifier.shared.clear(tabID: tab.id)
    }

    /// Select the tab a clicked notification came from, dropping the panel if needed.
    func revealTab(id: String) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        selectTab(at: index)
    }

    /// Make the focused pane's terminal view the first responder so it receives keyboard input.
    func focusTerminalInActiveTab() {
        clearAttentionForActiveTab()
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
        panelVisible = visible
        for tab in tabs {
            tab.paneManager?.setSurfacesVisible(visible)
        }
        // Dropping the panel onto a tab that was waiting for you counts as reading it.
        if visible { clearAttentionForActiveTab() }
        // The agent scan rides the same signal for the same reason: a panel that is
        // down is meant to cost nothing.
        agentMonitor.setActive(visible)
    }

    // MARK: - Tab State Persistence

    /// Directories only. Superseded by `savedTabsKey`, still read once so an upgrade
    /// does not lose the tabs you had open.
    private static let legacyTabsKey = "savedTabDirectories"
    private static let savedTabsKey = "savedTabs"
    private static let savedActiveIndexKey = "savedActiveTabIndex"

    /// Save the tabs as they stand: each one's split shape, ratios, per-pane
    /// directories, and any name you typed.
    func saveTabState() {
        let saved = tabs.compactMap { tab -> SavedTab? in
            guard tab.kind == .terminal, let pm = tab.paneManager else { return nil }
            return SavedTab(customTitle: tab.customTitle, layout: pm.layoutSnapshot())
        }
        if let data = try? JSONEncoder().encode(saved) {
            UserDefaults.standard.set(data, forKey: Self.savedTabsKey)
        }
        UserDefaults.standard.set(activeTabIndex, forKey: Self.savedActiveIndexKey)
    }

    /// Restore tabs from saved state or create a default tab.
    private func restoreTabsOrDefault() {
        guard UserDefaults.standard.bool(forKey: "restoreTabsOnLaunch") else {
            addTab()
            return
        }

        let saved = Self.readSavedTabs()
        guard !saved.isEmpty else {
            addTab()
            return
        }

        for tab in saved {
            let directory = tab.directory
            addTab(
                in: directory == "~" ? nil : directory,
                layout: tab.layout.leafCount > 1 ? tab.layout : nil,
                customTitle: tab.customTitle
            )
        }

        let savedIndex = UserDefaults.standard.integer(forKey: Self.savedActiveIndexKey)
        if savedIndex >= 0 && savedIndex < tabs.count {
            activeTabIndex = savedIndex
        }
    }

    private static func readSavedTabs() -> [SavedTab] {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: savedTabsKey),
           let decoded = try? JSONDecoder().decode([SavedTab].self, from: data) {
            return decoded
        }
        // Upgrade path: the old format knew only where each tab was.
        guard let dirs = defaults.stringArray(forKey: legacyTabsKey) else { return [] }
        return dirs.map { SavedTab(customTitle: nil, layout: .leaf(directory: $0)) }
    }
}
