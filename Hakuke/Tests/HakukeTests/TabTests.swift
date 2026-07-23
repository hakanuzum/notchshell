import Testing
import Foundation
@testable import Hakuke

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
