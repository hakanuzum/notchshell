import Testing
import Foundation
@testable import Notchshell

@Suite(.serialized)
struct TabTests {

    @Test func tab_init_generatesUniqueID() {
        let tab1 = Tab()
        let tab2 = Tab()
        #expect(tab1.id != tab2.id)
    }

    @Test func tab_init_defaultTitleIsZsh() {
        let tab = Tab()
        #expect(tab.title == "zsh")
    }

    @Test func tab_init_createsTerminalInstance() {
        let tab = Tab()
        // instance should be non-nil (it's a let, so it's always set)
        #expect(tab.instance?.currentTitle == "zsh")
    }

    @Test func tab_titleIsMutable() {
        var tab = Tab()
        tab.title = "Custom Title"
        #expect(tab.title == "Custom Title")
    }

    @Test func tab_identifiable_conformance() {
        let tab = Tab()
        // Tab conforms to Identifiable through its `id` property
        let id: String = tab.id
        #expect(id == tab.id)
    }
}

@Suite(.serialized)
struct TabDirectoryNameTests {

    @Test func directoryName_isTheLastComponent() {
        #expect(Tab.name(forDirectory: "/usr/local") == "local")
        #expect(Tab.name(forDirectory: "/Users/someone/src/project") == "project")
    }

    @Test func directoryName_collapsesHomeToTilde() {
        #expect(Tab.name(forDirectory: NSHomeDirectory()) == "~")
    }

    @Test func directoryName_ignoresTrailingSlash() {
        #expect(Tab.name(forDirectory: "/usr/local/") == "local")
    }

    @Test func directoryName_keepsRoot() {
        #expect(Tab.name(forDirectory: "/") == "/")
    }

    @Test func directoryName_isNilForEmpty() {
        #expect(Tab.name(forDirectory: "") == nil)
    }

    /// The directory wins over whatever the shell last announced over OSC. A prompt
    /// that writes its own title reports an abbreviated path once and then goes quiet,
    /// so a tab named from `title` alone stops following `cd`.
    @Test func displayTitle_prefersDirectoryOverShellTitle() {
        var tab = Tab()
        tab.title = "~/D/W/P/notchshell"
        tab.directoryTitle = "bilake"
        #expect(tab.displayTitle == "bilake")
    }

    @Test func displayTitle_fallsBackToShellTitleBeforeAnyDirectory() {
        var tab = Tab()
        tab.title = "vim"
        tab.directoryTitle = nil
        #expect(tab.displayTitle == "vim")
    }

    @Test func displayTitle_customNameStillWins() {
        var tab = Tab()
        tab.title = "vim"
        tab.directoryTitle = "bilake"
        tab.customTitle = "build"
        #expect(tab.displayTitle == "build")
    }
}
