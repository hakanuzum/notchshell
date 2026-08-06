import Testing
@testable import Notchshell

@Suite(.serialized)
struct PanelStateTests {

    @Test func panelState_equatable_sameValues() {
        #expect(PanelState.hidden == PanelState.hidden)
        #expect(PanelState.visible == PanelState.visible)
    }

    @Test func panelState_equatable_differentValues() {
        #expect(PanelState.hidden != PanelState.visible)
        #expect(PanelState.visible != PanelState.hidden)
    }

    @Test func panelState_allCases_areTwoDistinctStates() {
        let states: [PanelState] = [.hidden, .visible]
        #expect(states.count == 2)
        #expect(states[0] != states[1])
    }
}
