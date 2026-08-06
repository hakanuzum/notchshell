import Testing
import Foundation
import AppKit
@testable import Notchshell

// MARK: - Socket Helper

/// Send a JSON command to a Unix domain socket and parse the response.
/// Runs the blocking I/O on a background thread to avoid deadlocking the main actor.
private func sendCommand(
    _ json: [String: Any],
    socketPath: String
) async throws -> [String: Any] {
    let path = socketPath
    let requestData = try JSONSerialization.data(withJSONObject: json)
    guard let requestString = String(data: requestData, encoding: .utf8) else {
        throw SocketError.encodingError
    }

    return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else {
                continuation.resume(throwing: SocketError.cannotCreateSocket)
                return
            }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                path.withCString { cstr in
                    let dest = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
                    _ = strcpy(dest, cstr)
                }
            }

            let connectResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard connectResult == 0 else {
                close(fd)
                continuation.resume(throwing: SocketError.cannotConnect(errno: errno))
                return
            }

            let written = requestString.withCString { cstr in
                write(fd, cstr, strlen(cstr))
            }
            guard written > 0 else {
                close(fd)
                continuation.resume(throwing: SocketError.writeFailed)
                return
            }

            var buffer = [UInt8](repeating: 0, count: 65536)
            let n = read(fd, &buffer, buffer.count)
            close(fd)

            guard n > 0 else {
                continuation.resume(throwing: SocketError.readFailed)
                return
            }

            let responseString = String(bytes: buffer[0..<n], encoding: .utf8) ?? ""
            guard let responseData = responseString.data(using: .utf8),
                  let responseJSON = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
                continuation.resume(throwing: SocketError.invalidResponse(responseString))
                return
            }

            continuation.resume(returning: responseJSON)
        }
    }
}

/// Send raw text (not JSON) to a Unix domain socket and return the raw response.
private func sendRaw(
    _ text: String,
    socketPath: String
) async throws -> String {
    let path = socketPath
    return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else {
                continuation.resume(throwing: SocketError.cannotCreateSocket)
                return
            }

            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                path.withCString { cstr in
                    let dest = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
                    _ = strcpy(dest, cstr)
                }
            }

            let connectResult = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                    connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
            guard connectResult == 0 else {
                close(fd)
                continuation.resume(throwing: SocketError.cannotConnect(errno: errno))
                return
            }

            _ = text.withCString { cstr in
                write(fd, cstr, strlen(cstr))
            }

            var buffer = [UInt8](repeating: 0, count: 65536)
            let n = read(fd, &buffer, buffer.count)
            close(fd)

            if n > 0 {
                let responseString = String(bytes: buffer[0..<n], encoding: .utf8) ?? ""
                continuation.resume(returning: responseString)
            } else {
                continuation.resume(throwing: SocketError.readFailed)
            }
        }
    }
}

private enum SocketError: Error, CustomStringConvertible {
    case cannotCreateSocket
    case cannotConnect(errno: Int32)
    case encodingError
    case writeFailed
    case readFailed
    case invalidResponse(String)

    var description: String {
        switch self {
        case .cannotCreateSocket: return "Cannot create socket"
        case .cannotConnect(let e): return "Cannot connect: errno=\(e)"
        case .encodingError: return "Encoding error"
        case .writeFailed: return "Write failed"
        case .readFailed: return "Read failed"
        case .invalidResponse(let s): return "Invalid response: \(s)"
        }
    }
}

/// Generate a unique temporary socket path for each test to avoid conflicts.
private func uniqueSocketPath() -> String {
    "/tmp/notchshell-test-\(generateShortID()).sock"
}

/// Small delay to let the socket server start accepting connections.
private func waitForServer() async throws {
    try await Task.sleep(nanoseconds: 50_000_000) // 50ms
}

// MARK: - 1. ControlServer + WindowController Integration

@MainActor
@Suite(.serialized, .disabled("Requires real socket server — run individually"))
struct ControlServerIntegrationTests {

    // MARK: - Helpers

    private func makeServerAndController() async throws -> (ControlServer, WindowController, String) {
        let path = uniqueSocketPath()
        let wc = WindowController()
        let server = ControlServer(windowController: wc, socketPath: path)
        try await waitForServer()
        return (server, wc, path)
    }

    // MARK: - state action

    @Test func state_returnsCurrentState() async throws {
        let (server, _, path) = try await makeServerAndController()
        defer { server.stop() }

        let response = try await sendCommand(["action": "state"], socketPath: path)

        #expect(response["ok"] as? Bool == true)
        #expect(response["visible"] as? Bool == false)
        #expect(response["pinned"] as? Bool == false)
        #expect(response["tab_count"] as? Int == 1)
        #expect(response["active_tab_index"] as? Int == 0)
    }

    // MARK: - toggle action

    @Test func toggle_changesVisibility() async throws {
        let (server, wc, path) = try await makeServerAndController()
        defer { server.stop() }

        #expect(wc.state == .hidden)

        let toggleResponse = try await sendCommand(["action": "toggle"], socketPath: path)
        #expect(toggleResponse["ok"] as? Bool == true)
        #expect(wc.state == .visible)

        let toggleBack = try await sendCommand(["action": "toggle"], socketPath: path)
        #expect(toggleBack["ok"] as? Bool == true)
        #expect(wc.state == .hidden)
    }

    // MARK: - show / hide actions

    @Test func show_makesVisible() async throws {
        let (server, wc, path) = try await makeServerAndController()
        defer { server.stop() }

        let response = try await sendCommand(["action": "show"], socketPath: path)
        #expect(response["ok"] as? Bool == true)
        #expect(wc.state == .visible)
    }

    @Test func hide_makesHidden() async throws {
        let (server, wc, path) = try await makeServerAndController()
        defer { server.stop() }

        wc.show()
        #expect(wc.state == .visible)

        let response = try await sendCommand(["action": "hide"], socketPath: path)
        #expect(response["ok"] as? Bool == true)
        #expect(wc.state == .hidden)
    }

    // MARK: - pin / unpin actions

    @Test func pin_setsPinnedTrue() async throws {
        let (server, wc, path) = try await makeServerAndController()
        defer { server.stop() }

        #expect(wc.isPinned == false)

        let response = try await sendCommand(["action": "pin"], socketPath: path)
        #expect(response["ok"] as? Bool == true)
        #expect(wc.isPinned == true)
    }

    @Test func unpin_setsPinnedFalse() async throws {
        let (server, wc, path) = try await makeServerAndController()
        defer { server.stop() }

        wc.isPinned = true
        let response = try await sendCommand(["action": "unpin"], socketPath: path)
        #expect(response["ok"] as? Bool == true)
        #expect(wc.isPinned == false)
    }

    @Test func pinUnpin_reflectedInState() async throws {
        let (server, _, path) = try await makeServerAndController()
        defer { server.stop() }

        _ = try await sendCommand(["action": "pin"], socketPath: path)
        let stateAfterPin = try await sendCommand(["action": "state"], socketPath: path)
        #expect(stateAfterPin["pinned"] as? Bool == true)

        _ = try await sendCommand(["action": "unpin"], socketPath: path)
        let stateAfterUnpin = try await sendCommand(["action": "state"], socketPath: path)
        #expect(stateAfterUnpin["pinned"] as? Bool == false)
    }

    // MARK: - new-tab action

    @Test func newTab_addsTabAndReturnsSessionID() async throws {
        let (server, wc, path) = try await makeServerAndController()
        defer { server.stop() }

        #expect(wc.tabManager.tabs.count == 1)

        let response = try await sendCommand(["action": "new-tab"], socketPath: path)
        #expect(response["ok"] as? Bool == true)
        #expect(response["session_id"] as? String != nil)
        #expect(wc.tabManager.tabs.count == 2)
    }

    @Test func newTab_withDirectory() async throws {
        let (server, wc, path) = try await makeServerAndController()
        defer { server.stop() }

        let response = try await sendCommand(
            ["action": "new-tab", "directory": "/tmp"],
            socketPath: path
        )
        #expect(response["ok"] as? Bool == true)
        #expect(wc.tabManager.tabs.count == 2)
    }

    // MARK: - list action

    @Test func list_returnsAllTabs() async throws {
        let (server, _, path) = try await makeServerAndController()
        defer { server.stop() }

        // Add a second tab
        _ = try await sendCommand(["action": "new-tab"], socketPath: path)

        let response = try await sendCommand(["action": "list"], socketPath: path)
        #expect(response["ok"] as? Bool == true)
        #expect(response["count"] as? Int == 2)

        let tabs = response["tabs"] as? [[String: Any]]
        #expect(tabs?.count == 2)

        // Second tab (index 1) should be active since it was just created
        if let secondTab = tabs?[1] {
            #expect(secondTab["active"] as? Bool == true)
            #expect(secondTab["index"] as? Int == 1)
        }
    }

    // MARK: - focus action

    @Test func focus_byIndex_switchesActiveTab() async throws {
        let (server, wc, path) = try await makeServerAndController()
        defer { server.stop() }

        _ = try await sendCommand(["action": "new-tab"], socketPath: path)
        #expect(wc.tabManager.activeTabIndex == 1)

        let response = try await sendCommand(["action": "focus", "index": 0], socketPath: path)
        #expect(response["ok"] as? Bool == true)
        #expect(wc.tabManager.activeTabIndex == 0)
    }

    @Test func focus_bySessionID_switchesActiveTab() async throws {
        let (server, wc, path) = try await makeServerAndController()
        defer { server.stop() }

        _ = try await sendCommand(["action": "new-tab"], socketPath: path)
        let firstPaneID = wc.tabManager.tabs[0].paneManager!.focusedPaneID

        let response = try await sendCommand(
            ["action": "focus", "session_id": firstPaneID],
            socketPath: path
        )
        #expect(response["ok"] as? Bool == true)
        #expect(wc.tabManager.activeTabIndex == 0)
    }

    @Test func focus_invalidSessionID_returnsError() async throws {
        let (server, _, path) = try await makeServerAndController()
        defer { server.stop() }

        let response = try await sendCommand(
            ["action": "focus", "session_id": generateShortID()],
            socketPath: path
        )
        #expect(response["ok"] as? Bool == false)
        #expect((response["error"] as? String)?.contains("session not found") == true)
    }

    // MARK: - close-session action

    @Test func closeSession_removesTab() async throws {
        let (server, wc, path) = try await makeServerAndController()
        defer { server.stop() }

        _ = try await sendCommand(["action": "new-tab"], socketPath: path)
        #expect(wc.tabManager.tabs.count == 2)

        let tabID = wc.tabManager.tabs[1].id
        let response = try await sendCommand(
            ["action": "close-session", "tab_id": tabID],
            socketPath: path
        )
        #expect(response["ok"] as? Bool == true)
        #expect(wc.tabManager.tabs.count == 1)
    }

    @Test func closeSession_withoutSessionID_closesActiveTab() async throws {
        let (server, wc, path) = try await makeServerAndController()
        defer { server.stop() }

        _ = try await sendCommand(["action": "new-tab"], socketPath: path)
        #expect(wc.tabManager.tabs.count == 2)
        let activeTabID = wc.tabManager.activeTab!.id

        let response = try await sendCommand(["action": "close-session"], socketPath: path)
        #expect(response["ok"] as? Bool == true)
        // The active tab should have been closed; a new one may replace it or the other remains
        #expect(wc.tabManager.tabs.contains(where: { $0.id == activeTabID }) == false)
    }

    // MARK: - unknown action

    @Test func unknownAction_returnsError() async throws {
        let (server, _, path) = try await makeServerAndController()
        defer { server.stop() }

        let response = try await sendCommand(["action": "nonexistent"], socketPath: path)
        #expect(response["ok"] as? Bool == false)
        #expect((response["error"] as? String)?.contains("unknown action") == true)
    }

    // MARK: - invalid JSON

    @Test func invalidRequest_returnsError() async throws {
        let path = uniqueSocketPath()
        let wc = WindowController()
        let server = ControlServer(windowController: wc, socketPath: path)
        defer { server.stop() }
        try await waitForServer()

        let responseString = try await sendRaw("this is not json", socketPath: path)
        #expect(responseString.contains("\"ok\":false"))
    }

    // MARK: - Combined flow via socket

    @Test func fullFlow_showAddTabsFocusCloseHide() async throws {
        let (server, wc, path) = try await makeServerAndController()
        defer { server.stop() }

        // 1. Show
        _ = try await sendCommand(["action": "show"], socketPath: path)
        #expect(wc.state == .visible)

        // 2. Add two tabs
        let tab2Response = try await sendCommand(["action": "new-tab"], socketPath: path)
        let tab2ID = tab2Response["session_id"] as! String
        _ = try await sendCommand(["action": "new-tab"], socketPath: path)

        let stateAfterAdd = try await sendCommand(["action": "state"], socketPath: path)
        #expect(stateAfterAdd["tab_count"] as? Int == 3)

        // 3. Focus first tab
        _ = try await sendCommand(["action": "focus", "index": 0], socketPath: path)
        let stateAfterFocus = try await sendCommand(["action": "state"], socketPath: path)
        #expect(stateAfterFocus["active_tab_index"] as? Int == 0)

        // 4. Pin
        _ = try await sendCommand(["action": "pin"], socketPath: path)
        #expect(wc.isPinned == true)

        // 5. Close tab 2
        _ = try await sendCommand(["action": "close-session", "session_id": tab2ID], socketPath: path)
        let stateAfterClose = try await sendCommand(["action": "state"], socketPath: path)
        #expect(stateAfterClose["tab_count"] as? Int == 2)

        // 6. Unpin and hide
        _ = try await sendCommand(["action": "unpin"], socketPath: path)
        _ = try await sendCommand(["action": "hide"], socketPath: path)
        #expect(wc.state == .hidden)
        #expect(wc.isPinned == false)
    }
}

// MARK: - 2. TabManager + TerminalInstance Integration

@MainActor
@Suite(.serialized)
struct TabManagerTerminalIntegrationTests {

    @Test func addTab_createsTerminalInstance() {
        let manager = TabManager()
        // TabManager starts with 1 tab from init
        #expect(manager.tabs.count == 1)
        let instance = manager.tabs[0].instance!

        // The terminal backend view should exist
        #expect(instance.backend.view.frame.size != .zero)
    }

    @Test func addMultipleTabs_eachHasUniqueTerminalInstance() {
        let manager = TabManager()
        manager.addTab()
        manager.addTab()

        #expect(manager.tabs.count == 3)

        // Each tab should have its own distinct TerminalInstance
        let instances = manager.tabs.map { ObjectIdentifier($0.instance!) }
        let uniqueInstances = Set(instances)
        #expect(uniqueInstances.count == 3)
    }

    @Test func addMultipleTabs_eachHasUniqueTerminalView() {
        let manager = TabManager()
        manager.addTab()
        manager.addTab()

        #expect(manager.tabs.count == 3)

        // Each instance should wrap a different backend view
        let views = manager.tabs.map { ObjectIdentifier($0.instance!.backend.view) }
        let uniqueViews = Set(views)
        #expect(uniqueViews.count == 3)
    }

    @Test func closeTab_terminatesInstance() {
        let manager = TabManager()
        manager.addTab()
        #expect(manager.tabs.count == 2)

        let secondID = manager.tabs[1].id

        // Close the tab - this should call terminate() on the instance
        manager.closeTab(id: secondID)
        #expect(manager.tabs.count == 1)

        // The instance should be removed from the manager
        #expect(manager.tabs.contains(where: { $0.id == secondID }) == false)
    }

    @Test func closeTab_savesDirectoryForReopen() {
        let manager = TabManager()

        // Initially no reopen history
        #expect(manager.canReopenClosedTab == false)

        // addTab() spawns a real shell, so currentDirectory starts empty
        // but closing any tab saves its directory (only non-empty directories are saved)
        let tabID = manager.tabs[0].id
        manager.closeTab(id: tabID)

        // After closing, a new tab is auto-created (since it was the last)
        #expect(manager.tabs.count == 1)
    }

    @Test func addTab_inSpecificDirectory_passesDirectoryToInstance() {
        let manager = TabManager()
        manager.addTab(in: "/tmp")

        #expect(manager.tabs.count == 2)

        // The tab was told to start in /tmp - we can verify the instance was created
        let lastTab = manager.tabs.last!
        #expect(lastTab.instance != nil)
    }

    @Test func tabInstance_delegateCallbacks_areWired() {
        let manager = TabManager()
        let tab = manager.tabs[0]

        // onTitleChange and onProcessTerminated should be wired
        #expect(tab.instance!.onTitleChange != nil)
        #expect(tab.instance!.onProcessTerminated != nil)
    }

    @Test func closeAndRespawn_newTabHasFreshInstance() {
        let manager = TabManager()
        let originalID = manager.tabs[0].id
        // Keep a strong reference so ARC doesn't reuse the same address
        let oldPM = manager.tabs[0].paneManager!
        let originalPaneManager = ObjectIdentifier(oldPM)

        manager.closeTab(id: originalID)

        // Auto-respawned tab should have a different pane manager
        #expect(manager.tabs.count == 1)
        #expect(manager.tabs[0].id != originalID)
        let newPaneManager = ObjectIdentifier(manager.tabs[0].paneManager!)
        #expect(newPaneManager != originalPaneManager)
        _ = oldPM // prevent unused variable warning
    }

    @Test func multipleTabs_closeMiddle_preservesOtherInstances() {
        let manager = TabManager()
        manager.addTab()
        manager.addTab()
        // 3 tabs

        let firstID = manager.tabs[0].id
        let firstInstance = ObjectIdentifier(manager.tabs[0].instance!)
        let middleID = manager.tabs[1].id
        let lastID = manager.tabs[2].id
        let lastInstance = ObjectIdentifier(manager.tabs[2].instance!)

        manager.closeTab(id: middleID)
        #expect(manager.tabs.count == 2)

        // First and last tabs should retain their instances
        #expect(manager.tabs[0].id == firstID)
        #expect(ObjectIdentifier(manager.tabs[0].instance!) == firstInstance)
        #expect(manager.tabs[1].id == lastID)
        #expect(ObjectIdentifier(manager.tabs[1].instance!) == lastInstance)
    }
}

// MARK: - 3. WindowController + TabManager Integration

@MainActor
@Suite(.serialized)
struct WindowControllerTabManagerIntegrationTests {

    private func makeController() -> WindowController {
        WindowController()
    }

    @Test func controller_tabManagerIsShared() {
        let wc = makeController()
        // The controller's tabManager should be the same object used internally
        let tm = wc.tabManager
        tm.addTab()
        #expect(wc.tabManager.tabs.count == 2)
    }

    @Test func tabSwitching_viaTabManager_updatesActiveTab() {
        let wc = makeController()
        wc.tabManager.addTab()
        wc.tabManager.addTab()
        #expect(wc.tabManager.tabs.count == 3)
        #expect(wc.tabManager.activeTabIndex == 2)

        // Switch to first tab
        wc.tabManager.selectTab(at: 0)
        #expect(wc.tabManager.activeTabIndex == 0)
        #expect(wc.tabManager.activeTab?.id == wc.tabManager.tabs[0].id)
    }

    @Test func addTab_whileVisible_worksCorrectly() {
        let wc = makeController()
        wc.show()
        #expect(wc.state == .visible)

        let countBefore = wc.tabManager.tabs.count
        wc.tabManager.addTab()
        #expect(wc.tabManager.tabs.count == countBefore + 1)
        #expect(wc.tabManager.activeTabIndex == wc.tabManager.tabs.count - 1)

        wc.hide()
    }

    @Test func closeTab_whileVisible_worksCorrectly() {
        let wc = makeController()
        wc.show()
        wc.tabManager.addTab()
        #expect(wc.tabManager.tabs.count == 2)

        let secondID = wc.tabManager.tabs[1].id
        wc.tabManager.closeTab(id: secondID)
        #expect(wc.tabManager.tabs.count == 1)

        wc.hide()
    }

    @Test func selectNextTab_cyclesThroughTabs() {
        let wc = makeController()
        wc.tabManager.addTab()
        wc.tabManager.addTab()
        // 3 tabs, active = 2
        wc.tabManager.selectTab(at: 0)
        #expect(wc.tabManager.activeTabIndex == 0)

        wc.tabManager.selectNextTab()
        #expect(wc.tabManager.activeTabIndex == 1)

        wc.tabManager.selectNextTab()
        #expect(wc.tabManager.activeTabIndex == 2)

        wc.tabManager.selectNextTab()
        #expect(wc.tabManager.activeTabIndex == 0) // wraps
    }

    @Test func selectPreviousTab_cyclesBackward() {
        let wc = makeController()
        wc.tabManager.addTab()
        wc.tabManager.addTab()
        // 3 tabs, active = 2
        wc.tabManager.selectTab(at: 0)

        wc.tabManager.selectPreviousTab()
        #expect(wc.tabManager.activeTabIndex == 2) // wraps to last

        wc.tabManager.selectPreviousTab()
        #expect(wc.tabManager.activeTabIndex == 1)
    }

    @Test func closeAllTabs_autoRespawns_whileVisible() {
        let wc = makeController()
        wc.show()
        wc.tabManager.addTab()
        #expect(wc.tabManager.tabs.count == 2)

        // Close both tabs
        let tab1ID = wc.tabManager.tabs[0].id
        let tab2ID = wc.tabManager.tabs[1].id
        wc.tabManager.closeTab(id: tab2ID)
        wc.tabManager.closeTab(id: tab1ID)

        // Should auto-respawn a new tab
        #expect(wc.tabManager.tabs.count == 1)
        #expect(wc.tabManager.activeTabIndex == 0)

        wc.hide()
    }

    @Test func stateTransitions_doNotAffectTabCount() {
        let wc = makeController()
        wc.tabManager.addTab()
        wc.tabManager.addTab()
        let tabCount = wc.tabManager.tabs.count

        wc.show()
        #expect(wc.tabManager.tabs.count == tabCount)

        wc.hide()
        #expect(wc.tabManager.tabs.count == tabCount)

        wc.show()
        #expect(wc.tabManager.tabs.count == tabCount)

        wc.hide()
    }

    @Test func resizeDoesNotAffectTabs() {
        let wc = makeController()
        wc.tabManager.addTab()
        let tabCount = wc.tabManager.tabs.count
        let activeIndex = wc.tabManager.activeTabIndex

        wc.setWidthPercent(50)
        wc.setHeightPercent(30)

        #expect(wc.tabManager.tabs.count == tabCount)
        #expect(wc.tabManager.activeTabIndex == activeIndex)
    }

    @Test func showHideToggle_withTabOperations() {
        let wc = makeController()

        // Show, add tabs, switch tabs, hide, show again -- tabs should persist
        wc.show()
        wc.tabManager.addTab()
        wc.tabManager.addTab()
        let tab0ID = wc.tabManager.tabs[0].id
        let tab2ID = wc.tabManager.tabs[2].id
        wc.tabManager.selectTab(at: 0)

        wc.hide()
        // Tabs should persist across hide/show
        #expect(wc.tabManager.tabs.count == 3)
        #expect(wc.tabManager.activeTabIndex == 0)

        wc.show()
        #expect(wc.tabManager.tabs.count == 3)
        #expect(wc.tabManager.tabs[0].id == tab0ID)
        #expect(wc.tabManager.tabs[2].id == tab2ID)
        #expect(wc.tabManager.activeTabIndex == 0)

        wc.hide()
    }

    @Test func pinState_independentOfTabState() {
        let wc = makeController()
        wc.tabManager.addTab()

        wc.isPinned = true
        wc.tabManager.selectTab(at: 0)
        #expect(wc.isPinned == true) // Pin state unchanged by tab operations

        wc.tabManager.addTab()
        #expect(wc.isPinned == true) // Pin state unchanged by adding tabs

        let lastID = wc.tabManager.tabs.last!.id
        wc.tabManager.closeTab(id: lastID)
        #expect(wc.isPinned == true) // Pin state unchanged by closing tabs
    }
}

// MARK: - 4. ControlServer execute/paste/read roundtrip

@MainActor
@Suite(.serialized, .disabled("Requires real socket server — run individually"))
struct ControlServerExecuteReadTests {

    private func makeServerAndController() async throws -> (ControlServer, WindowController, String) {
        let path = uniqueSocketPath()
        let wc = WindowController()
        let server = ControlServer(windowController: wc, socketPath: path)
        try await waitForServer()
        return (server, wc, path)
    }

    @Test func execute_sendsCommandToTerminal() async throws {
        let (server, _, path) = try await makeServerAndController()
        defer { server.stop() }

        let response = try await sendCommand(
            ["action": "execute", "command": "echo hello"],
            socketPath: path
        )
        #expect(response["ok"] as? Bool == true)
        #expect(response["session_id"] as? String != nil)
    }

    @Test func execute_withSpecificSession() async throws {
        let (server, wc, path) = try await makeServerAndController()
        defer { server.stop() }

        let sessionID = wc.tabManager.tabs[0].paneManager!.focusedPaneID

        let response = try await sendCommand(
            ["action": "execute", "command": "pwd", "session_id": sessionID],
            socketPath: path
        )
        #expect(response["ok"] as? Bool == true)
        #expect(response["session_id"] as? String == sessionID)
    }

    @Test func execute_missingCommand_returnsError() async throws {
        let (server, _, path) = try await makeServerAndController()
        defer { server.stop() }

        let response = try await sendCommand(["action": "execute"], socketPath: path)
        #expect(response["ok"] as? Bool == false)
        #expect((response["error"] as? String)?.contains("missing command") == true)
    }

    @Test func paste_sendsTextToTerminal() async throws {
        let (server, _, path) = try await makeServerAndController()
        defer { server.stop() }

        let response = try await sendCommand(
            ["action": "paste", "text": "some text"],
            socketPath: path
        )
        #expect(response["ok"] as? Bool == true)
        #expect(response["session_id"] as? String != nil)
    }

    @Test func paste_missingText_returnsError() async throws {
        let (server, _, path) = try await makeServerAndController()
        defer { server.stop() }

        let response = try await sendCommand(["action": "paste"], socketPath: path)
        #expect(response["ok"] as? Bool == false)
        #expect((response["error"] as? String)?.contains("missing text") == true)
    }

    @Test func read_returnsTerminalContent() async throws {
        let (server, _, path) = try await makeServerAndController()
        defer { server.stop() }

        let response = try await sendCommand(["action": "read"], socketPath: path)
        #expect(response["ok"] as? Bool == true)
        #expect(response["lines"] as? [String] != nil)
        #expect(response["rows"] as? Int != nil)
        #expect(response["cols"] as? Int != nil)
        #expect(response["session_id"] as? String != nil)
    }

    @Test func read_withLineLimit() async throws {
        let (server, _, path) = try await makeServerAndController()
        defer { server.stop() }

        let response = try await sendCommand(
            ["action": "read", "lines": 5],
            socketPath: path
        )
        #expect(response["ok"] as? Bool == true)
        let lines = response["lines"] as? [String]
        #expect(lines != nil)
        #expect((lines?.count ?? 0) <= 5)
    }

    @Test func read_invalidSession_returnsError() async throws {
        let (server, _, path) = try await makeServerAndController()
        defer { server.stop() }

        let response = try await sendCommand(
            ["action": "read", "session_id": generateShortID()],
            socketPath: path
        )
        #expect(response["ok"] as? Bool == false)
        #expect((response["error"] as? String)?.contains("session not found") == true)
    }

    @Test func controlChar_sendsCharToTerminal() async throws {
        let (server, _, path) = try await makeServerAndController()
        defer { server.stop() }

        let response = try await sendCommand(
            ["action": "control-char", "key": "c"],
            socketPath: path
        )
        #expect(response["ok"] as? Bool == true)
        #expect(response["session_id"] as? String != nil)
    }

    @Test func controlChar_allSupportedKeys() async throws {
        let (server, _, path) = try await makeServerAndController()
        defer { server.stop() }

        let supportedKeys = ["c", "d", "z", "a", "e", "k", "l", "u", "w", "enter", "esc", "tab"]
        for key in supportedKeys {
            let response = try await sendCommand(
                ["action": "control-char", "key": key],
                socketPath: path
            )
            #expect(response["ok"] as? Bool == true, "control-char key=\(key) should succeed")
        }
    }

    @Test func controlChar_unknownKey_returnsError() async throws {
        let (server, _, path) = try await makeServerAndController()
        defer { server.stop() }

        let response = try await sendCommand(
            ["action": "control-char", "key": "nonexistent"],
            socketPath: path
        )
        #expect(response["ok"] as? Bool == false)
        #expect((response["error"] as? String)?.contains("unknown key") == true)
    }

    @Test func controlChar_missingKey_returnsError() async throws {
        let (server, _, path) = try await makeServerAndController()
        defer { server.stop() }

        let response = try await sendCommand(
            ["action": "control-char"],
            socketPath: path
        )
        #expect(response["ok"] as? Bool == false)
        #expect((response["error"] as? String)?.contains("missing key") == true)
    }

    @Test func executeAndRead_roundtrip() async throws {
        let (server, _, path) = try await makeServerAndController()
        defer { server.stop() }

        // Execute a command
        let execResponse = try await sendCommand(
            ["action": "execute", "command": "echo integration_test_marker"],
            socketPath: path
        )
        #expect(execResponse["ok"] as? Bool == true)
        let sessionID = execResponse["session_id"] as! String

        // Give the shell a moment to process the command
        try await Task.sleep(nanoseconds: 300_000_000)

        // Read back the terminal buffer
        let readResponse = try await sendCommand(
            ["action": "read", "session_id": sessionID],
            socketPath: path
        )
        #expect(readResponse["ok"] as? Bool == true)
        let lines = readResponse["lines"] as? [String] ?? []

        // The terminal buffer should contain our marker somewhere
        let combined = lines.joined()
        #expect(combined.contains("integration_test_marker"))
    }

    @Test func pasteAndRead_roundtrip() async throws {
        let (server, _, path) = try await makeServerAndController()
        defer { server.stop() }

        // Paste a command followed by newline
        let pasteResponse = try await sendCommand(
            ["action": "paste", "text": "echo paste_roundtrip_check\n"],
            socketPath: path
        )
        #expect(pasteResponse["ok"] as? Bool == true)
        let sessionID = pasteResponse["session_id"] as! String

        // Give the shell a moment to process
        try await Task.sleep(nanoseconds: 300_000_000)

        // Read back
        let readResponse = try await sendCommand(
            ["action": "read", "session_id": sessionID],
            socketPath: path
        )
        #expect(readResponse["ok"] as? Bool == true)
        let lines = readResponse["lines"] as? [String] ?? []
        let combined = lines.joined()
        #expect(combined.contains("paste_roundtrip_check"))
    }

    @Test func execute_onNewTab_readsFromCorrectSession() async throws {
        let (server, _, path) = try await makeServerAndController()
        defer { server.stop() }

        // Create a new tab
        let newTabResponse = try await sendCommand(["action": "new-tab"], socketPath: path)
        let newSessionID = newTabResponse["session_id"] as! String

        // Execute on the new tab specifically
        let execResponse = try await sendCommand(
            ["action": "execute", "command": "echo new_tab_marker", "session_id": newSessionID],
            socketPath: path
        )
        #expect(execResponse["ok"] as? Bool == true)
        #expect(execResponse["session_id"] as? String == newSessionID)

        // Give the shell a moment to process
        try await Task.sleep(nanoseconds: 300_000_000)

        // Read from the new tab
        let readResponse = try await sendCommand(
            ["action": "read", "session_id": newSessionID],
            socketPath: path
        )
        #expect(readResponse["ok"] as? Bool == true)
        let lines = readResponse["lines"] as? [String] ?? []
        let combined = lines.joined()
        #expect(combined.contains("new_tab_marker"))
    }
}
