import Testing
import Foundation
import AppKit
@testable import Notchshell

/// Tests for ControlServer request handling via handleRequest (no socket needed).
/// Tests JSON helpers, access control, request routing, and all 17 API handlers.
@MainActor
@Suite(.serialized)
struct ControlServerHandlerTests {

    // MARK: - Helpers

    private func makeServer() -> (ControlServer, WindowController) {
        let wc = WindowController()
        let server = ControlServer(windowController: wc, socketPath: "/dev/null", startImmediately: false)
        ControlServer.accessState = "enabled"
        return (server, wc)
    }

    private func json(_ dict: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return String(data: data, encoding: .utf8)!
    }

    private func parse(_ response: String) -> [String: Any]? {
        guard let data = response.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - JSON helpers

    @Test func jsonOK_empty_returnsOkTrue() {
        let result = jsonOK()
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == true)
    }

    @Test func jsonOK_withData_mergesCorrectly() {
        let result = jsonOK(["key": "value", "num": 42])
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == true)
        #expect(parsed?["key"] as? String == "value")
        #expect(parsed?["num"] as? Int == 42)
    }

    @Test func jsonError_returnsOkFalse() {
        let result = jsonError("test message")
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == false)
        #expect(parsed?["error"] as? String == "test message")
    }

    @Test func jsonError_escapesQuotes() {
        let result = jsonError("has \"quotes\" inside")
        #expect(result.contains("\\\"quotes\\\""))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == false)
    }

    @Test func jsonError_emptyMessage() {
        let result = jsonError("")
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == false)
        #expect(parsed?["error"] as? String == "")
    }

    // MARK: - Request routing

    @Test func invalidJSON_returnsError() {
        let (server, _) = makeServer()
        let result = server.handleRequest("not json at all")
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == false)
        #expect(parsed?["error"] as? String == "invalid JSON request")
    }

    @Test func validJSON_noAction_returnsError() {
        let (server, _) = makeServer()
        let result = server.handleRequest(json(["key": "value"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == false)
        #expect(parsed?["error"] as? String == "invalid JSON request")
    }

    @Test func unknownAction_returnsError() {
        let (server, _) = makeServer()
        let result = server.handleRequest(json(["action": "nonexistent"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == false)
        #expect((parsed?["error"] as? String)?.contains("unknown action") == true)
    }

    @Test func emptyString_returnsError() {
        let (server, _) = makeServer()
        let result = server.handleRequest("")
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == false)
    }

    // MARK: - state

    @Test func state_returnsAllFields() {
        let (server, wc) = makeServer()
        let result = server.handleRequest(json(["action": "state"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == true)
        #expect(parsed?["visible"] as? Bool == false) // starts hidden
        #expect(parsed?["pinned"] as? Bool == false)
        #expect(parsed?["tab_count"] as? Int == 1)
        #expect(parsed?["active_tab_index"] as? Int == 0)
        #expect(parsed?["width_percent"] != nil)
        #expect(parsed?["height_percent"] != nil)
        _ = wc // keep alive
    }

    // MARK: - list

    @Test func list_returnsTabsArray() {
        let (server, wc) = makeServer()
        let result = server.handleRequest(json(["action": "list"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == true)
        let tabs = parsed?["tabs"] as? [[String: Any]]
        #expect(tabs?.count == 1)
        #expect(tabs?[0]["index"] as? Int == 0)
        #expect(tabs?[0]["active"] as? Bool == true)
        #expect(tabs?[0]["session_id"] as? String != nil)
        _ = wc
    }

    @Test func list_multipleTabs_countCorrect() {
        let (server, wc) = makeServer()
        wc.tabManager.addTab()
        wc.tabManager.addTab()
        let result = server.handleRequest(json(["action": "list"]))
        let parsed = parse(result)
        let tabs = parsed?["tabs"] as? [[String: Any]]
        #expect(tabs?.count == 3)
        #expect(parsed?["count"] as? Int == 3)
    }

    // MARK: - toggle / show / hide

    @Test func toggle_changesState() {
        let (server, wc) = makeServer()
        #expect(wc.state == .hidden)
        _ = server.handleRequest(json(["action": "toggle"]))
        #expect(wc.state == .visible)
    }

    @Test func show_fromHidden_becomesVisible() {
        let (server, wc) = makeServer()
        _ = server.handleRequest(json(["action": "show"]))
        #expect(wc.state == .visible)
    }

    @Test func hide_fromVisible_becomesHidden() {
        let (server, wc) = makeServer()
        wc.show()
        _ = server.handleRequest(json(["action": "hide"]))
        #expect(wc.state == .hidden)
    }

    // MARK: - pin / unpin

    @Test func pin_setsIsPinned() {
        let (server, wc) = makeServer()
        _ = server.handleRequest(json(["action": "pin"]))
        #expect(wc.isPinned == true)
    }

    @Test func unpin_clearsIsPinned() {
        let (server, wc) = makeServer()
        wc.isPinned = true
        _ = server.handleRequest(json(["action": "unpin"]))
        #expect(wc.isPinned == false)
    }

    // MARK: - new-tab

    @Test func newTab_createsTab_returnsSessionID() {
        let (server, wc) = makeServer()
        let before = wc.tabManager.tabs.count
        let result = server.handleRequest(json(["action": "new-tab"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == true)
        #expect(parsed?["session_id"] as? String != nil)
        #expect(wc.tabManager.tabs.count == before + 1)
    }

    @Test func newTab_withDirectory_createsTab() {
        let (server, wc) = makeServer()
        let result = server.handleRequest(json(["action": "new-tab", "directory": "/tmp"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == true)
        #expect(wc.tabManager.tabs.count == 2)
    }

    @Test func newTab_withName_setsCustomTitle() {
        let (server, wc) = makeServer()
        let result = server.handleRequest(json(["action": "new-tab", "name": "Dev Server"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == true)
        #expect(wc.tabManager.tabs.last?.customTitle == "Dev Server")
        #expect(wc.tabManager.tabs.last?.displayTitle == "Dev Server")
    }

    @Test func newTab_withEmptyName_doesNotSetTitle() {
        let (server, wc) = makeServer()
        let result = server.handleRequest(json(["action": "new-tab", "name": ""]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == true)
        #expect(wc.tabManager.tabs.last?.customTitle == nil)
    }

    @Test func newTab_withNameAndDirectory_setsBoth() {
        let (server, wc) = makeServer()
        let result = server.handleRequest(json(["action": "new-tab", "name": "Logs", "directory": "/tmp"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == true)
        #expect(wc.tabManager.tabs.last?.customTitle == "Logs")
        #expect(wc.tabManager.tabs.count == 2)
    }

    // MARK: - focus

    @Test func focus_bySessionID_selectsTab() {
        let (server, wc) = makeServer()
        wc.tabManager.addTab()
        let firstPaneID = wc.tabManager.tabs[0].paneManager!.focusedPaneID
        wc.tabManager.selectTab(at: 1) // focus second tab

        let result = server.handleRequest(json(["action": "focus", "session_id": firstPaneID]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == true)
        #expect(wc.tabManager.activeTabIndex == 0)
    }

    @Test func focus_byIndex_selectsTab() {
        let (server, wc) = makeServer()
        wc.tabManager.addTab()
        let result = server.handleRequest(json(["action": "focus", "index": 0]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == true)
        #expect(wc.tabManager.activeTabIndex == 0)
    }

    @Test func focus_invalidSessionID_returnsError() {
        let (server, _) = makeServer()
        let result = server.handleRequest(json(["action": "focus", "session_id": "NONEXIST"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == false)
    }

    @Test func focus_noParams_returnsError() {
        let (server, _) = makeServer()
        let result = server.handleRequest(json(["action": "focus"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == false)
        #expect((parsed?["error"] as? String)?.contains("provide") == true)
    }

    // MARK: - close-session

    @Test func closeSession_byTabID_closesTab() {
        let (server, wc) = makeServer()
        wc.tabManager.addTab()
        #expect(wc.tabManager.tabs.count == 2)
        let tabID = wc.tabManager.tabs[0].id

        let result = server.handleRequest(json(["action": "close-session", "tab_id": tabID]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == true)
        // Tab closed but auto-created new one if needed
    }

    @Test func closeSession_noSessionID_closesActiveTab() {
        let (server, wc) = makeServer()
        wc.tabManager.addTab()
        let activeID = wc.tabManager.activeTab?.id
        let result = server.handleRequest(json(["action": "close-session"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == true)
        // The active tab was closed (new one auto-created)
        _ = activeID
    }

    @Test func closeSession_invalidID_returnsError() {
        let (server, _) = makeServer()
        let result = server.handleRequest(json(["action": "close-session", "session_id": "NONEXIST"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == false)
    }

    // MARK: - execute

    @Test func execute_missingCommand_returnsError() {
        let (server, _) = makeServer()
        let result = server.handleRequest(json(["action": "execute"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == false)
        #expect(parsed?["error"] as? String == "missing command")
    }

    @Test func execute_withCommand_returnsOK() {
        let (server, _) = makeServer()
        let result = server.handleRequest(json(["action": "execute", "command": "echo test"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == true)
        #expect(parsed?["session_id"] as? String != nil)
    }

    // MARK: - read

    @Test func read_returnsSnapshot() {
        let (server, _) = makeServer()
        let result = server.handleRequest(json(["action": "read"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == true)
        #expect(parsed?["lines"] != nil)
        #expect(parsed?["rows"] != nil)
        #expect(parsed?["cols"] != nil)
    }

    @Test func read_customLineCount() {
        let (server, _) = makeServer()
        let result = server.handleRequest(json(["action": "read", "lines": 5]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == true)
    }

    // MARK: - paste

    @Test func paste_missingText_returnsError() {
        let (server, _) = makeServer()
        let result = server.handleRequest(json(["action": "paste"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == false)
        #expect(parsed?["error"] as? String == "missing text")
    }

    @Test func paste_withText_returnsOK() {
        let (server, _) = makeServer()
        let result = server.handleRequest(json(["action": "paste", "text": "hello"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == true)
    }

    // MARK: - control-char

    @Test func controlChar_missingKey_returnsError() {
        let (server, _) = makeServer()
        let result = server.handleRequest(json(["action": "control-char"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == false)
        #expect(parsed?["error"] as? String == "missing key")
    }

    @Test func controlChar_unknownKey_returnsError() {
        let (server, _) = makeServer()
        let result = server.handleRequest(json(["action": "control-char", "key": "xyz"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == false)
        #expect((parsed?["error"] as? String)?.contains("unknown key") == true)
    }

    @Test func controlChar_validKeys_returnOK() {
        let (server, _) = makeServer()
        for key in ["c", "d", "z", "a", "e", "k", "l", "u", "w", "enter", "esc", "tab"] {
            let result = server.handleRequest(json(["action": "control-char", "key": key]))
            let parsed = parse(result)
            #expect(parsed?["ok"] as? Bool == true, "Key '\(key)' should return OK")
        }
    }

    // MARK: - clear

    @Test func clear_returnsOK() {
        let (server, _) = makeServer()
        let result = server.handleRequest(json(["action": "clear"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == true)
    }

    // MARK: - split

    @Test func split_missingDirection_returnsError() {
        let (server, _) = makeServer()
        let result = server.handleRequest(json(["action": "split"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == false)
        #expect((parsed?["error"] as? String)?.contains("direction") == true)
    }

    @Test func split_invalidDirection_returnsError() {
        let (server, _) = makeServer()
        let result = server.handleRequest(json(["action": "split", "direction": "x"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == false)
    }

    @Test func split_horizontal_returnsOK() {
        let (server, _) = makeServer()
        let result = server.handleRequest(json(["action": "split", "direction": "h"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == true)
    }

    @Test func split_vertical_returnsOK() {
        let (server, _) = makeServer()
        let result = server.handleRequest(json(["action": "split", "direction": "v"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == true)
    }

    // MARK: - set-appearance

    @Test func setAppearance_missingTitle_returnsError() {
        let (server, _) = makeServer()
        let result = server.handleRequest(json(["action": "set-appearance"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == false)
        #expect((parsed?["error"] as? String)?.contains("title") == true)
    }

    @Test func setAppearance_withTitle_renamesTab() {
        let (server, wc) = makeServer()
        let tabID = wc.tabManager.tabs[0].id
        let result = server.handleRequest(json(["action": "set-appearance", "title": "MyTab", "tab_id": tabID]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == true)
        #expect(wc.tabManager.tabs[0].customTitle == "MyTab")
    }

    @Test func setAppearance_emptyTitle_clearsCustomName() {
        let (server, wc) = makeServer()
        let tabID = wc.tabManager.tabs[0].id
        wc.tabManager.renameTab(id: wc.tabManager.tabs[0].id, name: "Custom")
        #expect(wc.tabManager.tabs[0].customTitle == "Custom")

        let result = server.handleRequest(json(["action": "set-appearance", "title": "", "tab_id": tabID]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == true)
        #expect(wc.tabManager.tabs[0].customTitle == nil)
    }

    @Test func setAppearance_invalidSession_returnsError() {
        let (server, _) = makeServer()
        let result = server.handleRequest(json(["action": "set-appearance", "title": "Test", "session_id": "00000000-0000-0000-0000-000000000000"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == false)
    }
}

// MARK: - Access state management tests

@MainActor
@Suite(.serialized)
struct ControlServerAccessControlTests {

    // Note: handleRequest() doesn't check accessState — that's done by
    // checkAccessThenHandle() which wraps it at the socket layer.
    // We test the accessState property itself and that handleRequest
    // works correctly when called (i.e., after access is granted).

    private func json(_ dict: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: dict)
        return String(data: data, encoding: .utf8)!
    }

    private func parse(_ response: String) -> [String: Any]? {
        guard let data = response.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    @Test func accessState_defaultIsUnset() {
        UserDefaults.standard.removeObject(forKey: "apiAccess")
        #expect(ControlServer.accessState == "unset")
    }

    @Test func accessState_enabledPersists() {
        ControlServer.accessState = "enabled"
        #expect(ControlServer.accessState == "enabled")
        #expect(UserDefaults.standard.string(forKey: "apiAccess") == "enabled")
        UserDefaults.standard.removeObject(forKey: "apiAccess")
    }

    @Test func accessState_disabledPersists() {
        ControlServer.accessState = "disabled"
        #expect(ControlServer.accessState == "disabled")
        #expect(UserDefaults.standard.string(forKey: "apiAccess") == "disabled")
        UserDefaults.standard.removeObject(forKey: "apiAccess")
    }

    @Test func accessState_roundTrips() {
        ControlServer.accessState = "enabled"
        #expect(ControlServer.accessState == "enabled")
        ControlServer.accessState = "disabled"
        #expect(ControlServer.accessState == "disabled")
        ControlServer.accessState = "enabled"
        #expect(ControlServer.accessState == "enabled")
        UserDefaults.standard.removeObject(forKey: "apiAccess")
    }

    @Test func handleRequest_worksWhenAccessGranted() {
        let wc = WindowController()
        let server = ControlServer(windowController: wc, socketPath: "/dev/null", startImmediately: false)
        ControlServer.accessState = "enabled"
        let result = server.handleRequest(json(["action": "state"]))
        let parsed = parse(result)
        #expect(parsed?["ok"] as? Bool == true)
    }
}
