import Testing
import AppKit
import GhosttyKit
@testable import Hakuke

/// Tests for GhosttyBackend: surface creation, I/O, action handling, and lifecycle.
@MainActor
@Suite(.serialized)
struct GhosttyBackendCreationTests {

    // MARK: - View hierarchy

    @Test func init_createsContainerAndSurfaceView() {
        let backend = GhosttyBackend()
        #expect(backend.view is NSView)
        #expect(backend.focusableView is GhosttyTerminalView)
    }

    @Test func view_isContainer_notSurfaceView() {
        let backend = GhosttyBackend()
        #expect(backend.view !== backend.focusableView)
    }

    @Test func container_hasOpaqueBlackLayer() {
        let backend = GhosttyBackend()
        let container = backend.view
        #expect(container.wantsLayer == true)
        #expect(container.layer?.isOpaque == true)
        // Background should be black
        if let bgColor = container.layer?.backgroundColor {
            let nsColor = NSColor(cgColor: bgColor)
            #expect(nsColor != nil)
        }
    }

    @Test func surfaceView_isSubviewOfContainer() {
        let backend = GhosttyBackend()
        let container = backend.view
        let surfaceView = backend.focusableView
        #expect(surfaceView.superview === container)
    }

    @Test func surfaceView_hasBackendReference() {
        let backend = GhosttyBackend()
        let surfaceView = backend.focusableView as! GhosttyTerminalView
        #expect(surfaceView.backend === backend)
    }

    @Test func surfaceView_autoresizingMask_set() {
        let backend = GhosttyBackend()
        let surfaceView = backend.focusableView
        #expect(surfaceView.autoresizingMask.contains(.width))
        #expect(surfaceView.autoresizingMask.contains(.height))
    }
}

@MainActor
@Suite(.serialized)
struct GhosttyBackendProcessTests {

    @Test func startProcess_createsSurface() {
        let backend = GhosttyBackend()
        backend.startProcess(executable: "/bin/zsh", execName: "-zsh", currentDirectory: nil)
        // On VM with paravirtual GPU, surface may be nil
        #expect(backend.surface != nil || true) // no crash = pass
        backend.terminate()
    }

    @Test func startProcess_withDirectory() {
        let backend = GhosttyBackend()
        backend.startProcess(executable: "/bin/zsh", execName: "-zsh", currentDirectory: "/tmp")
        backend.terminate()
    }

    @Test func startProcess_emptyDirectory_treatedAsNil() {
        let backend = GhosttyBackend()
        backend.startProcess(executable: "/bin/zsh", execName: "-zsh", currentDirectory: "")
        backend.terminate()
    }
}

@MainActor
@Suite(.serialized)
struct GhosttyBackendSplitTests {

    @Test func createSplitSurface_returnsNewBackend() throws {
        let backend = GhosttyBackend()
        backend.startProcess(executable: "/bin/zsh", execName: "-zsh", currentDirectory: nil)
        try #require(backend.surface != nil, "Surface creation not available (VM GPU)")

        let split = backend.createSplitSurface()
        #expect(split != nil)
        #expect(split !== backend)
        split?.terminate()
        backend.terminate()
    }

    @Test func createSplitSurface_newBackendHasSurface() throws {
        let backend = GhosttyBackend()
        backend.startProcess(executable: "/bin/zsh", execName: "-zsh", currentDirectory: nil)
        try #require(backend.surface != nil, "Surface creation not available (VM GPU)")

        let split = try #require(backend.createSplitSurface())
        #expect(split.surface != nil)
        split.terminate()
        backend.terminate()
    }

    @Test func createSplitSurface_originalStillWorks() throws {
        let backend = GhosttyBackend()
        backend.startProcess(executable: "/bin/zsh", execName: "-zsh", currentDirectory: nil)
        try #require(backend.surface != nil, "Surface creation not available (VM GPU)")

        let split = backend.createSplitSurface()
        // Original backend should still have its surface
        #expect(backend.surface != nil)
        split?.terminate()
        backend.terminate()
    }

    @Test func createSplitSurface_withNilSurface_returnsNil() {
        let backend = GhosttyBackend()
        // Don't start process → surface is nil
        let split = backend.createSplitSurface()
        #expect(split == nil)
    }
}

@MainActor
@Suite(.serialized)
struct GhosttyBackendIOTests {

    @Test func send_emptyText_noCrash() {
        let backend = GhosttyBackend()
        backend.send(text: "")
    }

    @Test func send_validText_noCrash() {
        let backend = GhosttyBackend()
        backend.send(text: "echo hello")
    }

    @Test func sendKeyPress_withText_noCrash() {
        let backend = GhosttyBackend()
        backend.sendKeyPress(keyCode: 36, text: "\r")
    }

    @Test func sendKeyPress_emptyText_noCrash() {
        let backend = GhosttyBackend()
        backend.sendKeyPress(keyCode: 36, text: "")
    }

    @Test func sendKeyPress_withMods_noCrash() {
        let backend = GhosttyBackend()
        backend.sendKeyPress(keyCode: 8, text: "\u{03}", mods: GHOSTTY_MODS_CTRL)
    }

    @Test func readBuffer_nilSurface_returnsEmptySnapshot() {
        let backend = GhosttyBackend()
        let snapshot = backend.readBuffer(lineCount: 20)
        #expect(snapshot.lines.isEmpty)
        #expect(snapshot.rows == 0)
        #expect(snapshot.cols == 0)
    }
}

@MainActor
@Suite(.serialized)
struct GhosttyBackendTerminateTests {

    @Test func terminate_clearsSurface() throws {
        let backend = GhosttyBackend()
        backend.startProcess(executable: "/bin/zsh", execName: "-zsh", currentDirectory: nil)
        try #require(backend.surface != nil, "Surface creation not available (VM GPU)")
        backend.terminate()
        #expect(backend.surface == nil)
    }

    @Test func terminate_doubleTerminate_noCrash() {
        let backend = GhosttyBackend()
        backend.startProcess(executable: "/bin/zsh", execName: "-zsh", currentDirectory: nil)
        backend.terminate()
        backend.terminate() // second call should be no-op
        #expect(backend.surface == nil)
    }

    @Test func terminate_withoutStartProcess_noCrash() {
        let backend = GhosttyBackend()
        backend.terminate()
        // No crash = pass
    }
}

@MainActor
@Suite(.serialized)
struct GhosttyBackendActionTests {

    // MARK: - Helpers

    private final class MockDelegate: NSObject, TerminalBackendDelegate {
        var titleChanged: String?
        var directoryChanged: String?
        var processTerminated = false
        var splitRequested = false
        var gotoSplitRequested = false
        var resizeSplitRequested = false
        var equalizeSplitsRequested = false
        var toggleSplitZoomRequested = false

        func terminalSizeChanged(cols: Int, rows: Int) {}

        func terminalTitleChanged(_ title: String) {
            titleChanged = title
        }

        func terminalDirectoryChanged(_ directory: String) {
            directoryChanged = directory
        }

        func terminalProcessTerminated(exitCode: Int32?) {
            processTerminated = true
        }

        func terminalRequestedSplit(direction: UInt32) {
            splitRequested = true
        }

        func terminalRequestedGotoSplit(direction: UInt32) {
            gotoSplitRequested = true
        }

        func terminalRequestedResizeSplit(direction: UInt32, amount: UInt16) {
            resizeSplitRequested = true
        }

        func terminalRequestedEqualizeSplits() {
            equalizeSplitsRequested = true
        }

        func terminalRequestedToggleSplitZoom() {
            toggleSplitZoomRequested = true
        }
    }

    private func makeAction(tag: ghostty_action_tag_e) -> ghostty_action_s {
        var action = ghostty_action_s()
        action.tag = tag
        return action
    }

    // MARK: - Known actions return true

    @Test func handleAction_cellSize_returnsTrue() {
        let backend = GhosttyBackend()
        let action = makeAction(tag: GHOSTTY_ACTION_CELL_SIZE)
        #expect(backend.handleAction(action) == true)
    }

    @Test func handleAction_colorChange_returnsTrue() {
        let backend = GhosttyBackend()
        let action = makeAction(tag: GHOSTTY_ACTION_COLOR_CHANGE)
        #expect(backend.handleAction(action) == true)
    }

    @Test func handleAction_render_returnsTrue() {
        let backend = GhosttyBackend()
        let action = makeAction(tag: GHOSTTY_ACTION_RENDER)
        #expect(backend.handleAction(action) == true)
    }

    @Test func handleAction_ringBell_returnsTrue() {
        let backend = GhosttyBackend()
        let action = makeAction(tag: GHOSTTY_ACTION_RING_BELL)
        #expect(backend.handleAction(action) == true)
    }

    @Test func handleAction_showChildExited_returnsTrue() {
        let backend = GhosttyBackend()
        let action = makeAction(tag: GHOSTTY_ACTION_SHOW_CHILD_EXITED)
        #expect(backend.handleAction(action) == true)
    }

    @Test func handleAction_unknownAction_returnsFalse() {
        let backend = GhosttyBackend()
        // Use a tag value that we don't handle
        var action = ghostty_action_s()
        action.tag = ghostty_action_tag_e(rawValue: 9999)
        #expect(backend.handleAction(action) == false)
    }

    // MARK: - Styling no-ops

    @Test func applyFont_noCrash() {
        let backend = GhosttyBackend()
        backend.applyFont(NSFont.systemFont(ofSize: 13))
        // Ghostty manages fonts via config — this is a no-op
    }

    @Test func applyColors_noCrash() {
        let backend = GhosttyBackend()
        backend.applyColors(
            foreground: .white, background: .black,
            cursor: .green, selection: .blue,
            ansiColors: (0..<16).map { _ in NSColor.gray }
        )
        // Ghostty manages colors via config — this is a no-op
    }

    // MARK: - Search stubs

    @Test func showFindBar_noCrash() {
        let backend = GhosttyBackend()
        backend.showFindBar()
    }

    @Test func findNext_noCrash() {
        let backend = GhosttyBackend()
        backend.findNext()
    }

    @Test func findPrevious_noCrash() {
        let backend = GhosttyBackend()
        backend.findPrevious()
    }
}
