import Foundation
import SwiftUI

/// A pane tree as it survives a quit: the shape, the ratios, and where each pane was.
///
/// Deliberately not `PaneNode`. That tree holds backends, and a backend is exactly the
/// part that cannot be written down — a live surface with a shell behind it. What comes
/// back is the arrangement, refilled with new shells.
indirect enum SavedPane: Codable, Equatable {
    case leaf(directory: String)
    case split(vertical: Bool, first: SavedPane, second: SavedPane, ratio: Double)

    /// Where the subtree's first pane sat. Restoring splits an existing pane in two,
    /// and that pane keeps standing in for everything on the `first` side, so this is
    /// the directory it has to have been opened in.
    var firstLeafDirectory: String {
        switch self {
        case .leaf(let directory): return directory
        case .split(_, let first, _, _): return first.firstLeafDirectory
        }
    }

    var leafCount: Int {
        switch self {
        case .leaf: return 1
        case .split(_, let first, let second, _): return first.leafCount + second.leafCount
        }
    }
}

/// One tab, as it survives a quit.
struct SavedTab: Codable, Equatable {
    /// A name you typed. A name derived from the directory is not saved — it is
    /// rederived on restore, and saving it would freeze a stale one in place.
    var customTitle: String?
    var layout: SavedPane

    var directory: String { layout.firstLeafDirectory }
}

extension PaneManager {
    /// The live tree, written down.
    func layoutSnapshot() -> SavedPane {
        snapshot(of: rootPane)
    }

    private func snapshot(of node: PaneNode) -> SavedPane {
        switch node {
        case .leaf(let id, _):
            let directory = instance(for: id)?.currentDirectory ?? ""
            return .leaf(directory: directory.isEmpty ? "~" : directory)
        case .split(_, let axis, let first, let second, let ratio):
            return .split(
                vertical: axis == .vertical,
                first: snapshot(of: first),
                second: snapshot(of: second),
                ratio: Double(ratio)
            )
        }
    }

    /// Rebuild a saved shape on top of the single pane this manager starts with.
    ///
    /// Each split lands the new pane in its own saved directory rather than letting it
    /// inherit the one it was split from — a two-pane tab spanning two projects would
    /// otherwise come back with both panes in the same one.
    func restoreLayout(_ saved: SavedPane) {
        rebuild(saved, into: focusedPaneID)
        // The first pane is the one you were left looking at least recently; restoring
        // ends focused on the last split made, which is arbitrary. Start at the top.
        if let first = rootPane.leafIDs.first { focusedPaneID = first }
    }

    private func rebuild(_ saved: SavedPane, into paneID: String) {
        guard case .split(let vertical, let first, let second, let ratio) = saved else { return }
        let created = splitPane(
            id: paneID,
            axis: vertical ? .vertical : .horizontal,
            ratio: CGFloat(ratio),
            directory: second.firstLeafDirectory
        )
        guard created else { return }
        // `splitPane` focuses what it just made, which is the `second` side.
        let newPaneID = focusedPaneID
        rebuild(first, into: paneID)
        rebuild(second, into: newPaneID)
    }
}
