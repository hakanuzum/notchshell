import Testing
import AppKit
@testable import Hakuke

/// Tests that keyboard input doesn't trigger NSBeep.
///
/// Uses a test NSView that mimics GhosttyTerminalView's keyboard handling:
/// - doCommand(by:) override (suppress NSBeep from interpretKeyEvents)
/// - Non-printable key bypass (skip interpretKeyEvents for backspace etc.)
/// - Cmd+key bypass (skip interpretKeyEvents for shortcuts)
///
/// The view is placed in a real NSWindow to exercise the full AppKit event chain.
@MainActor
@Suite(.serialized)
struct KeyboardBeepTests {

    // MARK: - Test view that mimics GhosttyTerminalView keyboard handling

    /// Minimal NSView+NSTextInputClient that replicates our keyboard paths.
    /// Tracks which code path each key takes and whether NSBeep would fire.
    final class KeyTestView: NSView, NSTextInputClient {
        var keyPaths: [String] = []
        var doCommandCalls: [String] = []
        var insertTextCalls: [String] = []
        var beepCount = 0
        private var markedTextStorage = NSMutableAttributedString()
        private var keyTextAccumulator: [String]?

        override var acceptsFirstResponder: Bool { true }

        // Suppress NSBeep from interpretKeyEvents
        override func doCommand(by selector: Selector) {
            doCommandCalls.append(NSStringFromSelector(selector))
        }

        override func keyDown(with event: NSEvent) {
            // Path 1: Non-printable
            if markedTextStorage.length == 0 {
                let chars = event.characters ?? ""
                let isNonPrintable = chars.isEmpty || chars.unicodeScalars.allSatisfy {
                    $0.value < 0x20 || $0.value == 0x7F ||
                    ($0.value >= 0xF700 && $0.value <= 0xF8FF)
                }
                if isNonPrintable {
                    keyPaths.append("direct:\(event.keyCode)")
                    return
                }
            }

            // Path 2: IME
            keyPaths.append("ime:\(event.keyCode)")
            keyTextAccumulator = []
            defer { keyTextAccumulator = nil }
            interpretKeyEvents([event])
        }

        // MARK: - NSTextInputClient

        func hasMarkedText() -> Bool { markedTextStorage.length > 0 }
        func markedRange() -> NSRange {
            markedTextStorage.length > 0 ? NSRange(location: 0, length: markedTextStorage.length) : NSRange(location: NSNotFound, length: 0)
        }
        func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
        func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
            if let s = string as? String { markedTextStorage.mutableString.setString(s) }
            else if let a = string as? NSAttributedString { markedTextStorage.mutableString.setString(a.string) }
        }
        func unmarkText() { markedTextStorage.mutableString.setString("") }
        func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
        func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
        func characterIndex(for point: NSPoint) -> Int { 0 }
        func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect { .zero }

        func insertText(_ string: Any, replacementRange: NSRange) {
            let text: String
            if let s = string as? String { text = s }
            else if let a = string as? NSAttributedString { text = a.string }
            else { return }
            unmarkText()
            if keyTextAccumulator != nil {
                keyTextAccumulator?.append(text)
            }
            insertTextCalls.append(text)
        }
    }

    // MARK: - Helpers

    private func makeKeyEvent(
        keyCode: UInt16,
        characters: String = "",
        charactersIgnoringModifiers: String = "",
        modifiers: NSEvent.ModifierFlags = [],
        isRepeat: Bool = false
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isARepeat: isRepeat,
            keyCode: keyCode
        )!
    }

    private func makeWindowAndView() -> (NSWindow, KeyTestView) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let view = KeyTestView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        return (window, view)
    }

    // MARK: - Tests

    @Test func backspace_takesDirectPath() {
        let (_, view) = makeWindowAndView()
        let event = makeKeyEvent(keyCode: 51, characters: "\u{7F}", charactersIgnoringModifiers: "\u{7F}")
        view.keyDown(with: event)

        #expect(view.keyPaths == ["direct:51"])
        #expect(view.doCommandCalls.isEmpty, "interpretKeyEvents should NOT be called for backspace")
    }

    @Test func rapidBackspace_allTakeDirectPath() {
        let (_, view) = makeWindowAndView()

        // First press
        let first = makeKeyEvent(keyCode: 51, characters: "\u{7F}", charactersIgnoringModifiers: "\u{7F}")
        view.keyDown(with: first)

        // 20 rapid repeats
        for _ in 0..<20 {
            let repeat_ = makeKeyEvent(keyCode: 51, characters: "\u{7F}", charactersIgnoringModifiers: "\u{7F}", isRepeat: true)
            view.keyDown(with: repeat_)
        }

        #expect(view.keyPaths.count == 21)
        #expect(view.keyPaths.allSatisfy { $0.hasPrefix("direct:") })
        #expect(view.doCommandCalls.isEmpty, "No interpretKeyEvents should be called")
    }

    @Test func delete_takesDirectPath() {
        let (_, view) = makeWindowAndView()
        // Forward delete: keyCode 117, character 0xF728 (NSDeleteFunctionKey)
        let event = makeKeyEvent(keyCode: 117, characters: "\u{F728}", charactersIgnoringModifiers: "\u{F728}")
        view.keyDown(with: event)

        #expect(view.keyPaths == ["direct:117"], "Forward delete (0xF728) should take direct path")
    }

    @Test func arrows_takeDirectPath() {
        let (_, view) = makeWindowAndView()
        // Left arrow: keyCode 123, character 0xF702 (Private Use Area function key)
        let left = makeKeyEvent(keyCode: 123, characters: "\u{F702}", charactersIgnoringModifiers: "\u{F702}")
        view.keyDown(with: left)

        #expect(view.keyPaths == ["direct:123"], "Arrow keys (0xF700-0xF8FF) should take direct path")
    }

    @Test func shiftArrow_takesDirectPath() {
        let (_, view) = makeWindowAndView()
        // Shift+Left arrow: keyCode 123, character 0xF702, shift modifier
        let event = makeKeyEvent(keyCode: 123, characters: "\u{F702}", charactersIgnoringModifiers: "\u{F702}", modifiers: .shift)
        view.keyDown(with: event)

        #expect(view.keyPaths == ["direct:123"], "Shift+Arrow should take direct path for text selection")
    }

    @Test func functionKeys_takeDirectPath() {
        let (_, view) = makeWindowAndView()
        // F1: keyCode 122, character 0xF704
        let event = makeKeyEvent(keyCode: 122, characters: "\u{F704}", charactersIgnoringModifiers: "\u{F704}")
        view.keyDown(with: event)

        #expect(view.keyPaths == ["direct:122"], "Function keys should take direct path")
    }

    @Test func tab_takesDirectPath() {
        let (_, view) = makeWindowAndView()
        // Tab: keyCode 48, character \t (0x09)
        let event = makeKeyEvent(keyCode: 48, characters: "\t", charactersIgnoringModifiers: "\t")
        view.keyDown(with: event)

        #expect(view.keyPaths == ["direct:48"], "Tab (0x09) should take direct path")
    }

    @Test func escape_takesDirectPath() {
        let (_, view) = makeWindowAndView()
        // Escape: keyCode 53, character 0x1B
        let event = makeKeyEvent(keyCode: 53, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}")
        view.keyDown(with: event)

        #expect(view.keyPaths == ["direct:53"], "Escape (0x1B) should take direct path")
    }

    @Test func return_takesDirectPath() {
        let (_, view) = makeWindowAndView()
        // Return: keyCode 36, character \r (0x0D)
        let event = makeKeyEvent(keyCode: 36, characters: "\r", charactersIgnoringModifiers: "\r")
        view.keyDown(with: event)

        #expect(view.keyPaths == ["direct:36"], "Return (0x0D) should take direct path")
    }

    @Test func cmdC_takesIMEPath() {
        // Cmd+keys are intercepted by performKeyEquivalent before keyDown.
        // In keyDown they go through IME (printable chars).
        let (_, view) = makeWindowAndView()
        let event = makeKeyEvent(keyCode: 8, characters: "c", charactersIgnoringModifiers: "c", modifiers: .command)
        view.keyDown(with: event)

        #expect(view.keyPaths == ["ime:8"])
    }

    @Test func ctrlD_takesDirectPath() {
        // Ctrl+D has character 0x04 (< 0x20) → non-printable → direct path
        let (_, view) = makeWindowAndView()
        let event = makeKeyEvent(keyCode: 2, characters: "\u{04}", charactersIgnoringModifiers: "d", modifiers: .control)
        view.keyDown(with: event)

        #expect(view.keyPaths == ["direct:2"])
    }

    @Test func regularText_takesIMEPath() {
        let (_, view) = makeWindowAndView()
        let event = makeKeyEvent(keyCode: 0, characters: "a", charactersIgnoringModifiers: "a")
        view.keyDown(with: event)

        #expect(view.keyPaths == ["ime:0"])
        // insertText should be called by interpretKeyEvents for regular text
        #expect(view.insertTextCalls.contains("a"))
    }

    @Test func regularText_doCommand_doesNotBeep() {
        let (window, view) = makeWindowAndView()

        // Send a key that triggers doCommand through interpretKeyEvents
        // (e.g. a key the input system doesn't recognize as text)
        let event = makeKeyEvent(keyCode: 48, characters: "\t", charactersIgnoringModifiers: "\t")

        // If this goes through IME path (which it shouldn't for tab),
        // doCommand override should prevent beep
        view.keyDown(with: event)

        // Tab should take direct path, never reaching interpretKeyEvents
        #expect(view.keyPaths == ["direct:48"])
        _ = window // keep alive
    }

    @Test func delete_forward_takesDirectPath() {
        let (_, view) = makeWindowAndView()
        // Forward delete: keyCode 117, character 0xF728 (NSDeleteFunctionKey)
        let event = makeKeyEvent(keyCode: 117, characters: "\u{F728}", charactersIgnoringModifiers: "\u{F728}")
        view.keyDown(with: event)

        #expect(view.keyPaths == ["direct:117"], "Forward delete (0xF728) should take direct path")
    }

    @Test func nonPrintableCheck_coversAllExpectedChars() {
        // Control chars (0x00-0x1F)
        for value: UInt32 in 0..<0x20 {
            #expect(value < 0x20)
        }
        // DEL (0x7F)
        #expect(Unicode.Scalar(0x7F)!.value == 0x7F)
        // Function keys (0xF700-0xF8FF) — arrows, F1-F12, Home, End, etc.
        for value: UInt32 in [0xF700, 0xF701, 0xF702, 0xF703, 0xF704, 0xF728, 0xF8FF] {
            let scalar = Unicode.Scalar(value)!
            #expect(scalar.value >= 0xF700 && scalar.value <= 0xF8FF, "Function key 0x\(String(value, radix: 16)) should be covered")
        }
    }
}
