import Testing
import AppKit
@testable import Hakuke

@MainActor
@Suite(.serialized)
struct MouseDownNSViewTests {

    // MARK: - Single click

    @Test func singleClick_callsAction() {
        var actionCalled = false
        let view = MouseDownNSView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        view.action = { actionCalled = true }
        view.doubleAction = nil

        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!
        view.mouseDown(with: event)

        #expect(actionCalled)
    }

    @Test func singleClick_doesNotCallDoubleAction() {
        var doubleActionCalled = false
        let view = MouseDownNSView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        view.action = {}
        view.doubleAction = { doubleActionCalled = true }

        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!
        view.mouseDown(with: event)

        #expect(!doubleActionCalled)
    }

    // MARK: - Double click

    @Test func doubleClick_callsDoubleAction() {
        var doubleActionCalled = false
        let view = MouseDownNSView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        view.action = {}
        view.doubleAction = { doubleActionCalled = true }

        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 2,
            pressure: 1.0
        )!
        view.mouseDown(with: event)

        #expect(doubleActionCalled)
    }

    @Test func doubleClick_doesNotCallSingleAction() {
        var actionCalled = false
        let view = MouseDownNSView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        view.action = { actionCalled = true }
        view.doubleAction = {}

        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 2,
            pressure: 1.0
        )!
        view.mouseDown(with: event)

        #expect(!actionCalled)
    }

    // MARK: - No double action set

    @Test func doubleClick_noDoubleAction_callsSingleAction() {
        var actionCalled = false
        let view = MouseDownNSView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        view.action = { actionCalled = true }
        view.doubleAction = nil

        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 2,
            pressure: 1.0
        )!
        view.mouseDown(with: event)

        // No doubleAction set, so single action should fire
        #expect(actionCalled)
    }

    // MARK: - acceptsFirstMouse

    @Test func acceptsFirstMouse_returnsTrue() {
        let view = MouseDownNSView(frame: NSRect(x: 0, y: 0, width: 100, height: 30))
        #expect(view.acceptsFirstMouse(for: nil) == true)
    }

    // MARK: - Empty area double-click scenario

    @Test func emptyAreaOverlay_doubleClick_addsTab() {
        // Simulates the "empty area" MouseDownOverlay behavior:
        // action is noop, doubleAction creates a tab
        var tabCreated = false
        let view = MouseDownNSView(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        view.action = {}  // noop for single click
        view.doubleAction = { tabCreated = true }

        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 2,
            pressure: 1.0
        )!
        view.mouseDown(with: event)

        #expect(tabCreated)
    }

    @Test func emptyAreaOverlay_singleClick_doesNotAddTab() {
        var tabCreated = false
        let view = MouseDownNSView(frame: NSRect(x: 0, y: 0, width: 200, height: 30))
        view.action = {}
        view.doubleAction = { tabCreated = true }

        let event = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1.0
        )!
        view.mouseDown(with: event)

        #expect(!tabCreated)
    }
}
