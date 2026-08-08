import Testing
import Foundation
import AppKit
@testable import Notchshell

/// Opening a folder from outside shows the tab already in it rather than making another
/// — and Clone Tab is how you ask for a second one anyway.
@MainActor
@Suite(.serialized)
struct TabReuseTests {

    /// Fresh tabs have no directory until a shell reports one, so these exercise the
    /// matching rule directly rather than relying on a live shell.
    private func makeManager() -> TabManager {
        UserDefaults.standard.removeObject(forKey: "restoreTabsOnLaunch")
        UserDefaults.standard.removeObject(forKey: "savedTabs")
        UserDefaults.standard.removeObject(forKey: "savedTabDirectories")
        return TabManager()
    }

    @Test func focusTab_withNoMatch_reportsSo() {
        let tm = makeManager()
        #expect(!tm.focusTab(in: "/nonexistent-\(UUID().uuidString)"))
    }

    /// An empty directory must never match. Every fresh tab has one, so a loose
    /// comparison would send the first folder you opened to whichever tab was newest.
    @Test func focusTab_ignoresTabsWithNoDirectoryYet() {
        let tm = makeManager()
        tm.addTab()
        #expect(!tm.focusTab(in: ""))
        #expect(!tm.focusTab(in: "/tmp"))
    }

    /// Clone takes the active tab's directory, which is the whole point — `⌘T` opens at
    /// home and cannot stand in for it.
    @Test func cloneActiveTab_addsATab() {
        let tm = makeManager()
        let before = tm.tabs.count
        tm.cloneActiveTab()
        #expect(tm.tabs.count == before + 1)
        #expect(tm.activeTabIndex == tm.tabs.count - 1)
    }

    /// Settings and Help are not terminals; cloning one would open a shell you never
    /// asked for.
    @Test func cloneActiveTab_doesNothingOnASpecialTab() {
        let tm = makeManager()
        tm.openSettings()
        let before = tm.tabs.count
        tm.cloneActiveTab()
        #expect(tm.tabs.count == before)
    }

    // MARK: - The shortcut

    @Test func cloneTab_isInTheRegistryWithItsOwnKey() throws {
        let actions = ActionRegistry.actions(for: WindowController())
        let clone = try #require(actions.first { $0.id == "tab.clone" })
        #expect(clone.title == "Clone Tab")
        #expect(clone.shortcut?.display == "⌥⌘T")
    }

    /// ⌘T and ⌥⌘T are different requests and must not answer for each other.
    @Test func cloneTab_doesNotCollideWithNewTab() throws {
        let actions = ActionRegistry.actions(for: WindowController())
        func event(option: Bool) -> NSEvent {
            var flags: NSEvent.ModifierFlags = [.command]
            if option { flags.insert(.option) }
            return NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: KeyCode.t
            )!
        }
        #expect(ActionRegistry.action(matching: event(option: false), in: actions)?.id == "tab.new")
        #expect(ActionRegistry.action(matching: event(option: true), in: actions)?.id == "tab.clone")
    }
}
