import Foundation
import AppKit
import SwiftUI
import GhosttyKit

/// Unix domain socket server for external control (sideshell-compatible API).
/// Listens on AppIdentity.controlSocketPath, accepts JSON requests, returns JSON responses.
/// Uses a serial queue to process requests one at a time, preventing race conditions.
final class ControlServer {
    let socketPath: String
    private var serverSocket: Int32 = -1
    private var readSource: DispatchSourceRead?
    private weak var windowController: WindowController?
    /// Serial queue ensures requests are processed one at a time.
    private let requestQueue = DispatchQueue(label: "\(AppIdentity.logSubsystem).api")

    /// API access: "ask" = prompt on first request, "enabled", "disabled"
    @MainActor static var accessState: String {
        get { UserDefaults.standard.string(forKey: "apiAccess") ?? "ask" }
        set { UserDefaults.standard.set(newValue, forKey: "apiAccess") }
    }

    init(windowController: WindowController, socketPath: String = AppIdentity.controlSocketPath, startImmediately: Bool = true) {
        self.socketPath = socketPath
        self.windowController = windowController
        if startImmediately { start() }
    }

    deinit {
        stop()
    }

    // MARK: - Socket lifecycle

    private func start() {
        unlink(socketPath)

        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard socketPath.utf8.count < pathLen else {
            print("ControlServer: socket path too long (\(socketPath.utf8.count) >= \(pathLen))")
            close(serverSocket)
            serverSocket = -1
            return
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            socketPath.withCString { cstr in
                let dest = UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: CChar.self)
                _ = strlcpy(dest, cstr, pathLen)
            }
        }

        let bindOK = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(serverSocket, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindOK == 0 else {
            close(serverSocket)
            serverSocket = -1
            return
        }

        // Owner-only access (sideshell runs as same user)
        chmod(socketPath, 0o700)

        listen(serverSocket, 5)
        _ = fcntl(serverSocket, F_SETFL, O_NONBLOCK)
        _ = fcntl(serverSocket, F_SETFD, FD_CLOEXEC)

        let source = DispatchSource.makeReadSource(fileDescriptor: serverSocket, queue: .global())
        source.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        source.setCancelHandler { [weak self] in
            if let fd = self?.serverSocket, fd >= 0 {
                close(fd)
            }
        }
        source.resume()
        readSource = source
    }

    func stop() {
        readSource?.cancel()
        readSource = nil
        unlink(socketPath)
    }

    // MARK: - Connection handling

    private func acceptConnection() {
        var clientAddr = sockaddr_un()
        var len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let clientFD = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                accept(serverSocket, sockPtr, &len)
            }
        }
        guard clientFD >= 0 else { return }

        // Serial queue: requests processed one at a time, no race conditions
        requestQueue.async { [weak self] in
            defer { close(clientFD) }

            var buffer = [UInt8](repeating: 0, count: 65536)
            let n = read(clientFD, &buffer, buffer.count)
            guard n > 0, let request = String(bytes: buffer[0..<n], encoding: .utf8) else { return }

            let semaphore = DispatchSemaphore(value: 0)
            var response = ""

            DispatchQueue.main.async {
                guard let self else {
                    response = jsonError("server gone")
                    semaphore.signal()
                    return
                }
                self.checkAccessThenHandle(request.trimmingCharacters(in: .whitespacesAndNewlines)) { result in
                    response = result
                    semaphore.signal()
                }
            }

            semaphore.wait()

            if let data = (response + "\n").data(using: .utf8) {
                data.withUnsafeBytes { ptr in
                    _ = write(clientFD, ptr.baseAddress!, data.count)
                }
            }
        }
    }

    // MARK: - Access control

    @MainActor
    private func checkAccessThenHandle(_ raw: String, completion: @escaping (String) -> Void) {
        let state = Self.accessState
        if state == "enabled" {
            completion(handleRequest(raw))
            return
        }
        if state == "disabled" {
            completion(jsonError("API access disabled"))
            return
        }
        // First time — ask user
        let alert = NSAlert()
        alert.messageText = "Allow API Access?"
        alert.informativeText = "An external process is trying to control \(AppIdentity.displayName) via the socket API. Allow this?"
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Deny")
        alert.alertStyle = .warning

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            Self.accessState = "enabled"
            completion(handleRequest(raw))
        } else {
            Self.accessState = "disabled"
            completion(jsonError("API access denied"))
        }
    }

    // MARK: - Request router

    @MainActor
    func handleRequest(_ raw: String) -> String {
        guard let data = raw.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let action = json["action"] as? String else {
            return jsonError("invalid JSON request")
        }

        guard let wc = windowController else {
            return jsonError("not ready")
        }

        switch action {
        case "list":          return handleList(wc, includePanes: json["include-panes"] as? Bool ?? false)
        case "state":         return handleState(wc)
        case "toggle":        wc.toggle(); return jsonOK()
        case "show":          wc.show(); return jsonOK()
        case "hide":          wc.hide(); return jsonOK()
        case "pin":           wc.isPinned = true; return jsonOK()
        case "unpin":         wc.isPinned = false; return jsonOK()
        case "new-tab":       return handleNewTab(json, wc)
        case "focus":         return handleFocus(json, wc)
        case "close-session": return handleClose(json, wc)
        case "execute":       return handleExecute(json, wc)
        case "read":          return handleRead(json, wc)
        case "paste":         return handlePaste(json, wc)
        case "control-char":  return handleControlChar(json, wc)
        case "clear":         return handleClear(json, wc)
        case "split":         return handleSplit(json, wc)
        case "resize-split":  return handleResizeSplit(json, wc)
        case "set-appearance": return handleSetAppearance(json, wc)
        default:              return jsonError("unknown action: \(action)")
        }
    }

    // MARK: - Handlers (iTerm2-style: session = pane, tab = container)

    @MainActor
    private func handleList(_ wc: WindowController, includePanes: Bool = false) -> String {
        var allSessions: [[String: Any]] = []
        let tabs = wc.tabManager.tabs.enumerated().map { (i, tab) -> [String: Any] in
            var info: [String: Any] = [
                "tab_id": tab.id,
                "index": i,
                "title": tab.displayTitle,
                "active": i == wc.tabManager.activeTabIndex,
            ]
            if let pm = tab.paneManager {
                let sessions = pm.rootPane.leafIDs.map { sid -> [String: Any] in
                    let inst = pm.instance(for: sid)
                    return [
                        "session_id": sid,
                        "focused": sid == pm.focusedPaneID,
                        "cwd": inst?.currentDirectory ?? ""
                    ]
                }
                info["sessions"] = sessions
                allSessions.append(contentsOf: sessions)
                if includePanes {
                    info["panes"] = serializePaneTree(pm.rootPane)
                }
            }
            return info
        }
        let activeSID = wc.tabManager.activeTab?.paneManager?.focusedPaneID ?? ""
        return jsonOK(["tabs": tabs, "tab_count": tabs.count, "session_count": allSessions.count, "active_session_id": activeSID])
    }

    @MainActor
    private func handleState(_ wc: WindowController) -> String {
        let activeSID = wc.tabManager.activeTab?.paneManager?.focusedPaneID ?? ""
        let data: [String: Any] = [
            "visible": wc.state == .visible,
            "pinned": wc.isPinned,
            "tab_count": wc.tabManager.tabs.count,
            "active_tab_index": wc.tabManager.activeTabIndex,
            "active_session_id": activeSID,
            "width_percent": wc.widthPercent,
            "height_percent": wc.heightPercent
        ]
        return jsonOK(data)
    }

    @MainActor
    private func handleNewTab(_ json: [String: Any], _ wc: WindowController) -> String {
        let dir = json["directory"] as? String
        wc.tabManager.addTab(in: dir)
        let tab = wc.tabManager.tabs.last!
        if let name = json["name"] as? String, !name.isEmpty {
            wc.tabManager.renameTab(id: tab.id, name: name)
        }
        let sid = tab.paneManager?.focusedPaneID ?? ""
        return jsonOK(["session_id": sid, "tab_id": tab.id])
    }

    @MainActor
    private func handleFocus(_ json: [String: Any], _ wc: WindowController) -> String {
        // Focus a session (pane) — auto-switches to its tab
        if let sid = json["session_id"] as? String {
            guard let (_, tab, pm) = findSession(sid, wc) else {
                return jsonError("session not found: \(sid)")
            }
            pm.focusedPaneID = sid
            let idx = wc.tabManager.tabs.firstIndex(where: { $0.id == tab.id })!
            wc.tabManager.selectTab(at: idx)
            wc.tabManager.focusTerminalInActiveTab()
            return jsonOK(["session_id": sid])
        }
        // Focus a tab by tab_id
        if let tabID = json["tab_id"] as? String {
            guard let idx = wc.tabManager.tabs.firstIndex(where: { $0.id == tabID }) else {
                return jsonError("tab not found: \(tabID)")
            }
            wc.tabManager.selectTab(at: idx)
            let sid = wc.tabManager.tabs[idx].paneManager?.focusedPaneID ?? ""
            return jsonOK(["session_id": sid])
        }
        // Focus by index
        if let index = json["index"] as? Int {
            wc.tabManager.selectTab(at: index)
            let sid = wc.tabManager.activeTab?.paneManager?.focusedPaneID ?? ""
            return jsonOK(["session_id": sid])
        }
        // Pane navigation by direction
        if let direction = json["direction"] as? String {
            guard direction == "prev" || direction == "next" else {
                return jsonError("direction must be \"prev\" or \"next\"")
            }
            guard let tab = wc.tabManager.activeTab, let pm = tab.paneManager else {
                return jsonError("no active terminal tab")
            }
            pm.moveFocus(direction == "prev" ? .previous : .next)
            wc.tabManager.focusTerminalInActiveTab()
            return jsonOK(["session_id": pm.focusedPaneID])
        }
        return jsonError("provide session_id, tab_id, index, or direction")
    }

    @MainActor
    private func handleClose(_ json: [String: Any], _ wc: WindowController) -> String {
        // Close a session (pane) — if last pane, closes the tab
        if let sid = json["session_id"] as? String {
            guard let (_, tab, pm) = findSession(sid, wc) else {
                return jsonError("session not found: \(sid)")
            }
            let wasLastPane = pm.rootPane.leafCount == 1
            pm.closePane(id: sid)
            if wasLastPane {
                // onLastPaneClosed fires closeTab; report 0 remaining
                return jsonOK(["pane_count": 0])
            }
            return jsonOK(["pane_count": pm.rootPane.leafIDs.count])
        }
        // Close a tab by tab_id
        if let tabID = json["tab_id"] as? String {
            guard wc.tabManager.tabs.contains(where: { $0.id == tabID }) else {
                return jsonError("tab not found: \(tabID)")
            }
            wc.tabManager.closeTab(id: tabID)
            return jsonOK()
        }
        // Close focused pane in active tab
        if let tab = wc.tabManager.activeTab, let pm = tab.paneManager {
            pm.closePane(id: pm.focusedPaneID)
            return jsonOK(["pane_count": pm.rootPane.leafIDs.count])
        }
        return jsonOK()
    }

    @MainActor
    private func handleExecute(_ json: [String: Any], _ wc: WindowController) -> String {
        guard let command = json["command"] as? String else {
            return jsonError("missing command")
        }
        guard let (instance, _, sessionID) = resolveSession(json, wc) else {
            return jsonError("session not found")
        }

        instance.backend.send(text: command)
        if let gb = instance.backend as? GhosttyBackend {
            gb.sendKeyPress(keyCode: 36, text: "\r")
        }
        return jsonOK(["session_id": sessionID])
    }

    @MainActor
    private func handleRead(_ json: [String: Any], _ wc: WindowController) -> String {
        guard let (instance, _, sessionID) = resolveSession(json, wc) else {
            return jsonError("session not found")
        }

        let lineCount = min(max(json["lines"] as? Int ?? 20, 1), 10000)
        let snapshot = instance.backend.readBuffer(lineCount: lineCount)

        return jsonOK([
            "session_id": sessionID,
            "lines": snapshot.lines,
            "rows": snapshot.rows,
            "cols": snapshot.cols
        ])
    }

    @MainActor
    private func handlePaste(_ json: [String: Any], _ wc: WindowController) -> String {
        guard let text = json["text"] as? String else {
            return jsonError("missing text")
        }
        guard let (instance, _, sessionID) = resolveSession(json, wc) else {
            return jsonError("session not found")
        }

        instance.backend.send(text: text)
        return jsonOK(["session_id": sessionID])
    }

    @MainActor
    private func handleControlChar(_ json: [String: Any], _ wc: WindowController) -> String {
        guard let key = json["key"] as? String else {
            return jsonError("missing key")
        }
        guard let (instance, _, sessionID) = resolveSession(json, wc) else {
            return jsonError("session not found")
        }

        guard let gb = instance.backend as? GhosttyBackend else {
            return jsonError("backend does not support key events")
        }
        switch key {
        case "c":     gb.sendKeyPress(keyCode: 8,  text: "\u{03}")
        case "d":     gb.sendKeyPress(keyCode: 2,  text: "\u{04}")
        case "z":     gb.sendKeyPress(keyCode: 6,  text: "\u{1A}")
        case "a":     gb.sendKeyPress(keyCode: 0,  text: "\u{01}")
        case "e":     gb.sendKeyPress(keyCode: 14, text: "\u{05}")
        case "k":     gb.sendKeyPress(keyCode: 40, text: "\u{0B}")
        case "l":     gb.sendKeyPress(keyCode: 37, text: "\u{0C}")
        case "u":     gb.sendKeyPress(keyCode: 32, text: "\u{15}")
        case "w":     gb.sendKeyPress(keyCode: 13, text: "\u{17}")
        case "enter": gb.sendKeyPress(keyCode: 36, text: "\r")
        case "esc":   gb.sendKeyPress(keyCode: 53, text: "\u{1B}")
        case "tab":   gb.sendKeyPress(keyCode: 48, text: "\t")
        default:      return jsonError("unknown key: \(key)")
        }
        return jsonOK(["session_id": sessionID])
    }

    @MainActor
    private func handleClear(_ json: [String: Any], _ wc: WindowController) -> String {
        guard let (instance, _, sessionID) = resolveSession(json, wc) else {
            return jsonError("session not found")
        }
        if let gb = instance.backend as? GhosttyBackend {
            gb.sendKeyPress(keyCode: 37, text: "\u{0C}")
        }
        return jsonOK(["session_id": sessionID])
    }

    @MainActor
    private func handleSplit(_ json: [String: Any], _ wc: WindowController) -> String {
        guard let direction = json["direction"] as? String,
              direction == "h" || direction == "v" else {
            return jsonError("provide direction: \"h\" or \"v\"")
        }

        let axis: Axis = direction == "h" ? .horizontal : .vertical
        let ratio = CGFloat(json["ratio"] as? Double ?? 0.5)

        // Split a specific session, or the focused pane in active tab
        if let sid = json["session_id"] as? String {
            guard let (_, _, pm) = findSession(sid, wc) else {
                return jsonError("session not found: \(sid)")
            }
            guard pm.splitPane(id: sid, axis: axis, ratio: ratio) else {
                return jsonError("split failed")
            }
            return jsonOK(["session_id": pm.focusedPaneID])
        }

        guard let tab = wc.tabManager.activeTab, let pm = tab.paneManager else {
            return jsonError("no active terminal tab")
        }
        guard pm.splitFocusedPane(axis: axis, ratio: ratio) else {
            return jsonError("split failed")
        }
        return jsonOK(["session_id": pm.focusedPaneID])
    }

    @MainActor
    private func handleResizeSplit(_ json: [String: Any], _ wc: WindowController) -> String {
        guard let tab = wc.tabManager.activeTab, let pm = tab.paneManager else {
            return jsonError("no active terminal tab")
        }

        // Option 1: Set absolute ratio
        if let ratio = json["ratio"] as? Double {
            let targetPaneID = json["session_id"] as? String ?? pm.focusedPaneID
            guard let splitID = parentSplitID(of: targetPaneID, in: pm.rootPane) else {
                return jsonError("pane is not in a split")
            }
            pm.updateSplitRatio(splitID: splitID, ratio: CGFloat(ratio))
            return jsonOK()
        }

        // Option 2: Equalize all splits
        if let equalize = json["equalize"] as? Bool, equalize {
            pm.equalizeSplits()
            return jsonOK()
        }

        // Option 3: Resize by delta (percentage points, e.g. 10 = +10%)
        if let delta = json["delta"] as? Double {
            let targetPaneID = json["session_id"] as? String ?? pm.focusedPaneID
            // Temporarily set focus to target pane for directional resize
            let originalFocus = pm.focusedPaneID
            pm.focusedPaneID = targetPaneID
            pm.resizeFocusedSplit(delta: CGFloat(delta) / 100.0)
            pm.focusedPaneID = originalFocus
            return jsonOK()
        }

        return jsonError("provide ratio (0.1-0.9), delta (-90 to 90), or equalize: true")
    }

    @MainActor
    private func serializePaneTree(_ node: PaneNode) -> [String: Any] {
        switch node {
        case .leaf(let id, _):
            return ["type": "leaf", "session_id": id]
        case .split(_, let axis, let first, let second, let ratio):
            return [
                "type": "split",
                "axis": axis == .horizontal ? "horizontal" : "vertical",
                "ratio": ratio,
                "first": serializePaneTree(first),
                "second": serializePaneTree(second)
            ]
        }
    }

    @MainActor
    private func handleSetAppearance(_ json: [String: Any], _ wc: WindowController) -> String {
        guard let title = json["title"] as? String else {
            return jsonError("provide title")
        }
        // Find tab by tab_id, or by session_id (find containing tab), or active tab
        if let tabID = json["tab_id"] as? String {
            guard wc.tabManager.tabs.contains(where: { $0.id == tabID }) else {
                return jsonError("tab not found: \(tabID)")
            }
            wc.tabManager.renameTab(id: tabID, name: title.isEmpty ? nil : title)
            return jsonOK(["tab_id": tabID])
        }
        if let sid = json["session_id"] as? String {
            guard let (_, tab, _) = findSession(sid, wc) else {
                return jsonError("session not found: \(sid)")
            }
            wc.tabManager.renameTab(id: tab.id, name: title.isEmpty ? nil : title)
            return jsonOK(["tab_id": tab.id])
        }
        guard let tab = wc.tabManager.activeTab else {
            return jsonError("no active tab")
        }
        wc.tabManager.renameTab(id: tab.id, name: title.isEmpty ? nil : title)
        return jsonOK(["tab_id": tab.id])
    }

    // MARK: - Helpers

    /// Find a session (pane) by its short ID, searching across all tabs.
    @MainActor
    private func findSession(_ sessionID: String, _ wc: WindowController) -> (TerminalInstance, Tab, PaneManager)? {
        for tab in wc.tabManager.tabs {
            guard let pm = tab.paneManager else { continue }
            if pm.rootPane.leafIDs.contains(sessionID) {
                guard let instance = pm.instance(for: sessionID) else { continue }
                return (instance, tab, pm)
            }
        }
        return nil
    }

    /// Resolve a session from JSON params, defaulting to focused pane in active tab.
    @MainActor
    private func resolveSession(_ json: [String: Any], _ wc: WindowController) -> (TerminalInstance, Tab, String)? {
        if let sid = json["session_id"] as? String {
            guard let (inst, tab, _) = findSession(sid, wc) else { return nil }
            return (inst, tab, sid)
        }
        // Default: focused pane in active tab
        guard let tab = wc.tabManager.activeTab, let pm = tab.paneManager else { return nil }
        let focusedID = pm.focusedPaneID
        guard let inst = pm.instance(for: focusedID) else { return nil }
        return (inst, tab, focusedID)
    }
}

// MARK: - JSON helpers

func jsonOK(_ data: [String: Any] = [:]) -> String {
    var result: [String: Any] = ["ok": true]
    for (k, v) in data { result[k] = v }
    guard let json = try? JSONSerialization.data(withJSONObject: result),
          let str = String(data: json, encoding: .utf8) else {
        return "{\"ok\":true}"
    }
    return str
}

func jsonError(_ message: String) -> String {
    let escaped = message.replacingOccurrences(of: "\"", with: "\\\"")
    return "{\"ok\":false,\"error\":\"\(escaped)\"}"
}
