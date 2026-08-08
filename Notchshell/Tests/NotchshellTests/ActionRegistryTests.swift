import Testing
import AppKit
@testable import Notchshell

/// The registry's whole reason for existing is that the action list is now a thing that
/// can be checked. These are the checks.
@MainActor
@Suite(.serialized)
struct ActionRegistryTests {

    private func makeActions() -> [AppAction] {
        ActionRegistry.actions(for: WindowController())
    }

    private func keyEvent(_ keyCode: UInt16,
                          command: Bool = true,
                          shift: Bool = false,
                          control: Bool = false) -> NSEvent {
        var flags: NSEvent.ModifierFlags = []
        if command { flags.insert(.command) }
        if shift { flags.insert(.shift) }
        if control { flags.insert(.control) }
        return NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
            isARepeat: false, keyCode: keyCode
        )!
    }

    // MARK: - The invariants a scattered switch could not have

    @Test func actionIDs_areUnique() {
        let ids = makeActions().map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// Two actions on one key means one of them is unreachable. Spread across a switch
    /// this was invisible — the second `case` simply never ran, silently.
    @Test func shortcuts_doNotCollide() {
        var seen: [String: String] = [:]
        for action in makeActions() {
            guard let shortcut = action.shortcut else { continue }
            let key = shortcut.display
            #expect(seen[key] == nil,
                    "\(key) is claimed by both \(seen[key] ?? "") and \(action.id)")
            seen[key] = action.id
        }
    }

    /// The list has to still contain everything the old key switch dispatched.
    @Test func registry_coversTheOriginalBindings() {
        let ids = Set(makeActions().map(\.id))
        for expected in ["tab.new", "tab.reopen", "tab.close", "tab.next", "tab.previous",
                         "pane.split.horizontal", "pane.split.vertical", "pane.zoom",
                         "pane.next", "pane.previous",
                         "view.find", "view.findNext", "view.findPrevious",
                         "app.pin", "app.settings"] {
            #expect(ids.contains(expected), "missing \(expected)")
        }
        // ⌘1–9, all nine.
        for digit in 1...9 {
            #expect(ids.contains("tab.select.\(digit)"))
        }
    }

    // MARK: - Matching

    @Test func matching_findsTheBoundAction() throws {
        let actions = makeActions()
        let found = ActionRegistry.action(matching: keyEvent(KeyCode.t), in: actions)
        #expect(found?.id == "tab.new")

        let shifted = ActionRegistry.action(matching: keyEvent(KeyCode.t, shift: true),
                                            in: actions)
        #expect(shifted?.id == "tab.reopen")
    }

    /// The monitor sees every keystroke, including the ones meant for the shell. An
    /// unmodified key must never resolve to an action, or it would be swallowed on its
    /// way to the terminal.
    @Test func matching_ignoresUnmodifiedKeys() {
        let actions = makeActions()
        for keyCode in [KeyCode.t, KeyCode.w, KeyCode.d, KeyCode.f, KeyCode.g] {
            #expect(ActionRegistry.action(matching: keyEvent(keyCode, command: false),
                                          in: actions) == nil)
        }
    }

    /// Modifiers are matched exactly: ⌘⇧D is a different action from ⌘D, and neither
    /// may answer for the other.
    @Test func matching_isExactAboutModifiers() {
        let actions = makeActions()
        #expect(ActionRegistry.action(matching: keyEvent(KeyCode.d), in: actions)?.id
                == "pane.split.horizontal")
        #expect(ActionRegistry.action(matching: keyEvent(KeyCode.d, shift: true), in: actions)?.id
                == "pane.split.vertical")
        // ⌘⌃D is neither.
        #expect(ActionRegistry.action(matching: keyEvent(KeyCode.d, control: true),
                                      in: actions) == nil)
    }

    /// Ctrl+Tab carries no command key, so it has to be expressible without one.
    @Test func matching_handlesControlOnlyShortcuts() {
        let actions = makeActions()
        #expect(ActionRegistry.action(matching: keyEvent(KeyCode.tab, command: false, control: true),
                                      in: actions)?.id == "tab.next")
        #expect(ActionRegistry.action(matching: keyEvent(KeyCode.tab, command: false,
                                                         shift: true, control: true),
                                      in: actions)?.id == "tab.previous")
    }

    /// ⌘/ belongs to the menu bar. Claiming it here would take the event away from the
    /// menu, which is where Help is actually wired up.
    @Test func matching_leavesHelpToTheMenuBar() {
        let actions = makeActions()
        #expect(actions.contains { $0.id == "app.help" })
        #expect(ActionRegistry.action(matching: keyEvent(KeyCode.slash), in: actions) == nil)
    }

    // MARK: - Display

    /// macOS prints modifiers ⌃⌥⇧⌘, command last — "⇧⌘D", the way Finder writes New
    /// Folder. Not the "⌘ ⇧ D" order this project's README and Help use in prose; a
    /// menu-like surface should read like a menu.
    @Test func shortcutDisplay_printsModifiersInSystemOrder() {
        #expect(ActionShortcut(keyCode: KeyCode.t).display == "⌘T")
        #expect(ActionShortcut(keyCode: KeyCode.d, shift: true).display == "⇧⌘D")
        #expect(ActionShortcut(keyCode: KeyCode.tab, command: false,
                               shift: true, control: true).display == "⌃⇧⇥")
        #expect(ActionShortcut(keyCode: KeyCode.return, shift: true).display == "⇧⌘↩")
    }

    @Test func keyCodeSymbols_coverEveryBoundKey() {
        for action in makeActions() {
            guard let shortcut = action.shortcut else { continue }
            #expect(KeyCode.symbol(for: shortcut.keyCode) != "?",
                    "\(action.id) prints as an unknown key")
        }
    }
}
