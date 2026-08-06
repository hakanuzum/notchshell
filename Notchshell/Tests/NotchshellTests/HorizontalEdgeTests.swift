import Testing
@testable import Notchshell

@Suite(.serialized)
struct HorizontalEdgeTests {

    @Test func horizontalEdge_hasTwoCases() {
        let left = HorizontalEdge.left
        let right = HorizontalEdge.right

        // Verify both cases exist and are distinct
        // Using a switch to confirm exhaustiveness
        switch left {
        case .left: break
        case .right: Issue.record("Expected .left")
        }

        switch right {
        case .right: break
        case .left: Issue.record("Expected .right")
        }
    }
}
