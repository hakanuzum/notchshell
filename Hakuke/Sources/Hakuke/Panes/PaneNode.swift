import Foundation
import SwiftUI

/// Generate a random 8-character hex ID (e.g. "A3F1B2C4").
func generateShortID() -> String {
    String(UUID().uuidString.prefix(8))
}

/// A binary tree node representing either a single terminal pane or a split.
indirect enum PaneNode: Identifiable {
    case leaf(id: String, backend: TerminalBackend)
    case split(id: String, axis: Axis, first: PaneNode, second: PaneNode, ratio: CGFloat)

    var id: String {
        switch self {
        case .leaf(let id, _): return id
        case .split(let id, _, _, _, _): return id
        }
    }

    /// All leaf pane IDs in order (left-to-right / top-to-bottom).
    var leafIDs: [String] {
        switch self {
        case .leaf(let id, _):
            return [id]
        case .split(_, _, let first, let second, _):
            return first.leafIDs + second.leafIDs
        }
    }

    /// Find the backend for a given pane ID.
    func backend(for paneID: String) -> TerminalBackend? {
        switch self {
        case .leaf(let id, let b):
            return id == paneID ? b : nil
        case .split(_, _, let first, let second, _):
            return first.backend(for: paneID) ?? second.backend(for: paneID)
        }
    }

    /// Total number of leaf panes.
    var leafCount: Int {
        switch self {
        case .leaf: return 1
        case .split(_, _, let first, let second, _):
            return first.leafCount + second.leafCount
        }
    }

    /// Terminate all backends in this subtree.
    func terminateAll() {
        switch self {
        case .leaf(_, let backend):
            backend.terminate()
        case .split(_, _, let first, let second, _):
            first.terminateAll()
            second.terminateAll()
        }
    }
}

// MARK: - Tree operations (pure functions returning new trees)

/// Insert a new pane next to the target leaf, splitting it along the given axis.
func splitNode(_ node: PaneNode, targetID: String, axis: Axis, newBackend: TerminalBackend, newPaneID: String, ratio: CGFloat = 0.5) -> PaneNode {
    switch node {
    case .leaf(let id, _) where id == targetID:
        return .split(
            id: generateShortID(),
            axis: axis,
            first: node,
            second: .leaf(id: newPaneID, backend: newBackend),
            ratio: ratio
        )
    case .leaf:
        return node
    case .split(let id, let ax, let first, let second, let r):
        let newFirst = splitNode(first, targetID: targetID, axis: axis, newBackend: newBackend, newPaneID: newPaneID, ratio: ratio)
        if newFirst.id != first.id {
            return .split(id: id, axis: ax, first: newFirst, second: second, ratio: r)
        }
        let newSecond = splitNode(second, targetID: targetID, axis: axis, newBackend: newBackend, newPaneID: newPaneID, ratio: ratio)
        return .split(id: id, axis: ax, first: first, second: newSecond, ratio: r)
    }
}

/// Update the ratio of a split node identified by its ID.
func updateRatio(_ node: PaneNode, splitID: String, ratio: CGFloat) -> PaneNode {
    let clamped = min(max(ratio, 0.1), 0.9)
    switch node {
    case .leaf:
        return node
    case .split(let id, let axis, let first, let second, let r):
        if id == splitID {
            return .split(id: id, axis: axis, first: first, second: second, ratio: clamped)
        }
        let newFirst = updateRatio(first, splitID: splitID, ratio: ratio)
        let newSecond = updateRatio(second, splitID: splitID, ratio: ratio)
        return .split(id: id, axis: axis, first: newFirst, second: newSecond, ratio: r)
    }
}

/// Find the parent split ID for a given leaf pane.
func parentSplitID(of paneID: String, in node: PaneNode) -> String? {
    switch node {
    case .leaf:
        return nil
    case .split(let id, _, let first, let second, _):
        if first.leafIDs.contains(paneID) || second.leafIDs.contains(paneID) {
            // Check if the pane is a direct child leaf
            if case .leaf(let lid, _) = first, lid == paneID { return id }
            if case .leaf(let lid, _) = second, lid == paneID { return id }
            // Otherwise recurse into the child that contains it
            return parentSplitID(of: paneID, in: first) ?? parentSplitID(of: paneID, in: second)
        }
        return nil
    }
}

/// Set all split ratios in the tree to 0.5 (equal).
func equalizeRatios(_ node: PaneNode) -> PaneNode {
    switch node {
    case .leaf:
        return node
    case .split(let id, let axis, let first, let second, _):
        return .split(id: id, axis: axis,
                      first: equalizeRatios(first),
                      second: equalizeRatios(second),
                      ratio: 0.5)
    }
}

/// Remove a leaf node and collapse its parent split.
func removeNode(_ node: PaneNode, targetID: String) -> PaneNode? {
    switch node {
    case .leaf(let id, let backend) where id == targetID:
        backend.terminate()
        return nil
    case .leaf:
        return node
    case .split(let id, let axis, let first, let second, let ratio):
        if first.leafIDs.contains(targetID) {
            if let newFirst = removeNode(first, targetID: targetID) {
                return .split(id: id, axis: axis, first: newFirst, second: second, ratio: ratio)
            }
            return second
        }
        if second.leafIDs.contains(targetID) {
            if let newSecond = removeNode(second, targetID: targetID) {
                return .split(id: id, axis: axis, first: first, second: newSecond, ratio: ratio)
            }
            return first
        }
        return node
    }
}
