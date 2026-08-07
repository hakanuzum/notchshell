import Foundation
import SwiftUI
import os.log

final class PaneManager: ObservableObject {
    @Published var rootPane: PaneNode
    @Published var focusedPaneID: String {
        didSet {
            // Moving between panes changes which directory the tab is "in", and the
            // per-pane callbacks below only fire when a directory *changes*. Without
            // this, focusing a pane sitting in another directory left the tab named
            // after the one you just left.
            guard focusedPaneID != oldValue else { return }
            let directory = instances[focusedPaneID]?.currentDirectory ?? ""
            if !directory.isEmpty { onFocusedDirectoryChange?(directory) }
        }
    }

    /// Called when the focused pane's title changes.
    var onFocusedTitleChange: ((String) -> Void)?
    /// Called when the focused pane's directory changes.
    var onFocusedDirectoryChange: ((String) -> Void)?
    /// Called when the last pane is closed.
    var onLastPaneClosed: (() -> Void)?

    /// The tab this pane tree belongs to, stamped into every shell's environment.
    ///
    /// It is the only thing tying a process back to a tab: libghostty exposes no pid
    /// for a surface, so there is nothing else to match on. Split surfaces inherit it
    /// through `GhosttyBackend`, so every pane of a tab reports the same id.
    let tabID: String?

    init(directory: String? = nil, tabID: String? = nil) {
        self.tabID = tabID
        let instance = TerminalInstance()
        let id = generateShortID()
        self.rootPane = .leaf(id: id, backend: instance.backend)
        self.focusedPaneID = id
        setupCallbacks(for: id, instance: instance)
        instance.startShell(in: directory, environment: PaneManager.environment(tabID: tabID))
        // Keep instance alive — stored via backend reference
        instances[id] = instance
    }

    static func environment(tabID: String?) -> [String: String] {
        guard let tabID, !tabID.isEmpty else { return [:] }
        return [AgentScanner.tabIDEnvVar: tabID]
    }

    /// Tracks TerminalInstance per pane for lifecycle (title, directory, process exit)
    private var instances: [String: TerminalInstance] = [:]

    var focusedInstance: TerminalInstance? {
        instances[focusedPaneID]
    }

    func instance(for paneID: String) -> TerminalInstance? {
        instances[paneID]
    }

    /// Tell every pane in this tab whether it is on screen — splits included, since a
    /// hidden panel hides all of them at once.
    func setSurfacesVisible(_ visible: Bool) {
        for instance in instances.values {
            instance.backend.setVisible(visible)
        }
    }

    var focusedBackend: TerminalBackend? {
        rootPane.backend(for: focusedPaneID)
    }

    var currentDirectory: String {
        focusedInstance?.currentDirectory ?? ""
    }

    // MARK: - Split (native Ghostty surfaces)

    @discardableResult
    func splitPane(id: String, axis: Axis, ratio: CGFloat = 0.5) -> Bool {
        guard let sourceBackend = rootPane.backend(for: id),
              let newBackend = sourceBackend.createSplitBackend() else {
            os_log(.error, "Failed to create split surface")
            return false
        }
        let newInstance = TerminalInstance(existingBackend: newBackend)

        let newPaneID = generateShortID()
        instances[newPaneID] = newInstance
        setupCallbacks(for: newPaneID, instance: newInstance)

        rootPane = splitNode(rootPane, targetID: id, axis: axis, newBackend: newBackend, newPaneID: newPaneID, ratio: ratio)
        focusedPaneID = newPaneID
        return true
    }

    @discardableResult
    func splitFocusedPane(axis: Axis, ratio: CGFloat = 0.5) -> Bool {
        splitPane(id: focusedPaneID, axis: axis, ratio: ratio)
    }

    // MARK: - Close

    @discardableResult
    func closePane(id: String) -> Bool {
        if case .leaf(let leafID, let backend) = rootPane, leafID == id {
            backend.terminate()
            instances.removeValue(forKey: id)
            onLastPaneClosed?()
            return false
        }

        if let newRoot = removeNode(rootPane, targetID: id) {
            rootPane = newRoot
            instances.removeValue(forKey: id)
            if !rootPane.leafIDs.contains(focusedPaneID) {
                focusedPaneID = rootPane.leafIDs.first!
            }
            return true
        }
        return true
    }

    // MARK: - Resize

    /// Update the ratio of a specific split node.
    func updateSplitRatio(splitID: String, ratio: CGFloat) {
        rootPane = updateRatio(rootPane, splitID: splitID, ratio: ratio)
    }

    /// Resize the split containing the focused pane by a delta amount.
    /// Positive delta increases the focused pane's share.
    func resizeFocusedSplit(delta: CGFloat) {
        guard let splitID = parentSplitID(of: focusedPaneID, in: rootPane) else { return }
        if case .split(_, _, let first, _, let ratio) = findSplit(splitID, in: rootPane) ?? rootPane {
            let isInFirst = first.leafIDs.contains(focusedPaneID)
            let newRatio = isInFirst ? ratio + delta : ratio - delta
            rootPane = updateRatio(rootPane, splitID: splitID, ratio: newRatio)
        }
    }

    /// Set all split ratios to 0.5 (equalize).
    func equalizeSplits() {
        rootPane = equalizeRatios(rootPane)
    }

    /// Find a split node by ID.
    private func findSplit(_ splitID: String, in node: PaneNode) -> PaneNode? {
        switch node {
        case .leaf:
            return nil
        case .split(let id, _, let first, let second, _):
            if id == splitID { return node }
            return findSplit(splitID, in: first) ?? findSplit(splitID, in: second)
        }
    }

    // MARK: - Navigation

    enum NavigationDirection {
        case next, previous
    }

    func moveFocus(_ direction: NavigationDirection) {
        let leaves = rootPane.leafIDs
        guard leaves.count > 1, let currentIndex = leaves.firstIndex(of: focusedPaneID) else { return }
        switch direction {
        case .next:
            focusedPaneID = leaves[(currentIndex + 1) % leaves.count]
        case .previous:
            focusedPaneID = leaves[(currentIndex - 1 + leaves.count) % leaves.count]
        }
    }

    // MARK: - Callbacks

    private func setupCallbacks(for paneID: String, instance: TerminalInstance) {
        instance.onTitleChange = { [weak self] title in
            Task { @MainActor in
                guard let self else { return }
                if self.focusedPaneID == paneID {
                    self.onFocusedTitleChange?(title)
                }
            }
        }

        instance.onDirectoryChange = { [weak self] dir in
            Task { @MainActor in
                guard let self else { return }
                if self.focusedPaneID == paneID {
                    self.onFocusedDirectoryChange?(dir)
                }
            }
        }

        instance.onProcessTerminated = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.closePane(id: paneID)
            }
        }

        instance.onResizeSplit = { [weak self] delta in
            Task { @MainActor in
                guard let self else { return }
                self.resizeFocusedSplit(delta: delta)
            }
        }

        instance.onEqualizeSplits = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.equalizeSplits()
            }
        }
    }
}
