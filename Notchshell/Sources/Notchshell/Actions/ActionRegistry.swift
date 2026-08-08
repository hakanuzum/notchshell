import AppKit
import SwiftUI
import KeyboardShortcuts

/// Every action this app has, in one list.
///
/// The key monitor resolves through this, so the list cannot be wrong about what a
/// shortcut does — there is nowhere else for a shortcut to be defined. Everything that
/// wants to show the user what the app can do reads the same list.
@MainActor
enum ActionRegistry {

    /// `unowned` throughout: the actions are stored on the controller they act upon, so
    /// a strong capture would be a cycle, and they cannot outlive it.
    static func actions(for wc: WindowController) -> [AppAction] {
        var actions: [AppAction] = []

        // MARK: Tabs

        actions.append(AppAction(
            id: "tab.new", title: "New Tab", group: .tabs,
            shortcut: ActionShortcut(keyCode: KeyCode.t)
        ) { [unowned wc] in wc.tabManager.addTab() })

        actions.append(AppAction(
            id: "tab.reopen", title: "Reopen Closed Tab", group: .tabs,
            shortcut: ActionShortcut(keyCode: KeyCode.t, shift: true),
            isEnabled: { [unowned wc] in wc.tabManager.canReopenClosedTab }
        ) { [unowned wc] in wc.tabManager.reopenClosedTab() })

        // ⌥⌘T, next to ⌘T. Opening a folder from outside now lands on the tab already
        // there, so this is how you ask for a second shell in the same place — ⌘T opens
        // at home and would make you type the path back.
        actions.append(AppAction(
            id: "tab.clone", title: "Clone Tab", group: .tabs,
            shortcut: ActionShortcut(keyCode: KeyCode.t, option: true),
            isEnabled: { [unowned wc] in wc.tabManager.activeTab?.kind == .terminal }
        ) { [unowned wc] in wc.tabManager.cloneActiveTab() })

        // One key, two outcomes, because that is what ⌘W has always done here: it takes
        // the pane if there is more than one, and the tab otherwise.
        actions.append(AppAction(
            id: "tab.close", title: "Close Pane or Tab", group: .tabs,
            shortcut: ActionShortcut(keyCode: KeyCode.w)
        ) { [unowned wc] in
            let tm = wc.tabManager
            if let tab = tm.activeTab, tab.kind == .terminal,
               let pm = tab.paneManager, pm.rootPane.leafCount > 1 {
                tm.closeActivePane()
            } else if let tab = tm.activeTab {
                tm.closeTab(id: tab.id)
            }
        })

        actions.append(AppAction(
            id: "tab.next", title: "Next Tab", group: .tabs,
            shortcut: ActionShortcut(keyCode: KeyCode.tab, command: false, control: true),
            isRebindable: false,
            isEnabled: { [unowned wc] in wc.tabManager.tabs.count > 1 }
        ) { [unowned wc] in wc.tabManager.selectNextTab() })

        actions.append(AppAction(
            id: "tab.previous", title: "Previous Tab", group: .tabs,
            shortcut: ActionShortcut(keyCode: KeyCode.tab, command: false,
                                     shift: true, control: true),
            isRebindable: false,
            isEnabled: { [unowned wc] in wc.tabManager.tabs.count > 1 }
        ) { [unowned wc] in wc.tabManager.selectPreviousTab() })

        // ⌘1–8 select by position; ⌘9 is the last tab, whatever its number — the
        // convention every browser uses.
        for (keyCode, digit) in KeyCode.digits.sorted(by: { $0.value < $1.value }) {
            let isLast = digit == 9
            actions.append(AppAction(
                id: "tab.select.\(digit)",
                title: isLast ? "Go to Last Tab" : "Go to Tab \(digit)",
                group: .tabs,
                shortcut: ActionShortcut(keyCode: keyCode),
                isRebindable: false,
                isEnabled: { [unowned wc] in isLast || wc.tabManager.tabs.count >= digit }
            ) { [unowned wc] in
                let tm = wc.tabManager
                tm.selectTab(at: isLast ? tm.tabs.count - 1 : digit - 1)
            })
        }

        // MARK: Panes

        actions.append(AppAction(
            id: "pane.split.horizontal", title: "Split Right", group: .panes,
            shortcut: ActionShortcut(keyCode: KeyCode.d)
        ) { [unowned wc] in wc.tabManager.splitActivePane(axis: .horizontal) })

        actions.append(AppAction(
            id: "pane.split.vertical", title: "Split Down", group: .panes,
            shortcut: ActionShortcut(keyCode: KeyCode.d, shift: true)
        ) { [unowned wc] in wc.tabManager.splitActivePane(axis: .vertical) })

        actions.append(AppAction(
            id: "pane.zoom", title: "Zoom Pane", group: .panes,
            shortcut: ActionShortcut(keyCode: KeyCode.return, shift: true),
            isEnabled: { [unowned wc] in
                (wc.tabManager.activeTab?.paneManager?.rootPane.leafCount ?? 1) > 1
            }
        ) { [unowned wc] in wc.tabManager.toggleZoomInActiveTab() })

        actions.append(AppAction(
            id: "pane.next", title: "Next Pane", group: .panes,
            shortcut: ActionShortcut(keyCode: KeyCode.rightBracket),
            isEnabled: { [unowned wc] in
                (wc.tabManager.activeTab?.paneManager?.rootPane.leafCount ?? 1) > 1
            }
        ) { [unowned wc] in wc.tabManager.moveFocusInActiveTab(.next) })

        actions.append(AppAction(
            id: "pane.previous", title: "Previous Pane", group: .panes,
            shortcut: ActionShortcut(keyCode: KeyCode.leftBracket),
            isEnabled: { [unowned wc] in
                (wc.tabManager.activeTab?.paneManager?.rootPane.leafCount ?? 1) > 1
            }
        ) { [unowned wc] in wc.tabManager.moveFocusInActiveTab(.previous) })

        // MARK: View

        actions.append(AppAction(
            id: "view.find", title: "Find", group: .view,
            shortcut: ActionShortcut(keyCode: KeyCode.f)
        ) { [unowned wc] in wc.tabManager.activeTab?.instance?.backend.showFindBar() })

        actions.append(AppAction(
            id: "view.findNext", title: "Find Next", group: .view,
            shortcut: ActionShortcut(keyCode: KeyCode.g)
        ) { [unowned wc] in wc.tabManager.activeTab?.instance?.backend.findNext() })

        actions.append(AppAction(
            id: "view.findPrevious", title: "Find Previous", group: .view,
            shortcut: ActionShortcut(keyCode: KeyCode.g, shift: true)
        ) { [unowned wc] in wc.tabManager.activeTab?.instance?.backend.findPrevious() })

        // MARK: App

        actions.append(AppAction(
            id: "app.pin", title: "Pin / Unpin Panel", group: .app,
            shortcut: ActionShortcut(keyCode: KeyCode.p, shift: true)
        ) { [unowned wc] in wc.isPinned.toggle() })

        actions.append(AppAction(
            id: "app.settings", title: "Settings", group: .app,
            shortcut: ActionShortcut(keyCode: KeyCode.comma)
        ) { [unowned wc] in wc.openSettings() })

        // ⌘/ reaches this through the menu bar rather than the key monitor
        // (`NotchshellApp`), so it is listed for its name and its shortcut, not to be
        // dispatched from here.
        actions.append(AppAction(
            id: "app.help", title: "Help", group: .app,
            shortcut: ActionShortcut(keyCode: KeyCode.slash),
            isRebindable: false
        ) { [unowned wc] in wc.openHelp() })

        return actions
    }

    /// The action a key event asks for, if any.
    ///
    /// A rebinding always wins over the built-in key — otherwise the default would keep
    /// answering after you moved it, and the action would respond to two keys at once.
    /// Modifiers are matched exactly, so a bare keystroke can never be mistaken for a
    /// bound one and swallowed on its way to the shell.
    static func action(matching event: NSEvent, in actions: [AppAction]) -> AppAction? {
        actions.first { action in
            // Help is the menu bar's to dispatch; matching it here would take the event
            // away from the menu without telling it.
            guard action.id != "app.help" else { return false }

            if let name = action.shortcutName,
               let recorded = KeyboardShortcuts.getShortcut(for: name) {
                return matches(event, recorded)
            }
            guard let shortcut = action.shortcut else { return false }
            return shortcut.matches(event)
        }
    }

    /// The recorder's own comparison, spelled out the same way `WindowController` has
    /// always compared its two configurable shortcuts.
    private static func matches(_ event: NSEvent, _ shortcut: KeyboardShortcuts.Shortcut) -> Bool {
        event.keyCode == UInt16(shortcut.carbonKeyCode)
            && event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                .subtracting(.numericPad)
                .subtracting(.function)
                == shortcut.modifiers.intersection(.deviceIndependentFlagsMask)
    }
}
