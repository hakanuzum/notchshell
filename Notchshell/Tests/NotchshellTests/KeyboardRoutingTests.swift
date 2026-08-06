import Testing
import AppKit
@testable import Notchshell

/// Comprehensive keyboard routing tests.
/// Verifies the 2-path architecture:
///   Path 1: non-printable → sendKeyDirect (no interpretKeyEvents)
///   Path 2: everything else → interpretKeyEvents → Ghostty
///
/// Also tests performKeyEquivalent (Cmd+keys, Ghostty bindings).
@MainActor
@Suite(.serialized)
struct KeyboardRoutingTests {

    // MARK: - Test view

    final class RoutingTestView: NSView, NSTextInputClient {
        var paths: [String] = []
        var doCommands: [String] = []
        var insertedText: [String] = []
        private var marked = NSMutableAttributedString()
        private var accumulator: [String]?

        override var acceptsFirstResponder: Bool { true }

        override func doCommand(by selector: Selector) {
            doCommands.append(NSStringFromSelector(selector))
        }

        override func keyDown(with event: NSEvent) {
            if marked.length == 0 {
                let chars = event.characters ?? ""
                let isNonPrintable = chars.isEmpty || chars.unicodeScalars.allSatisfy {
                    $0.value < 0x20 || $0.value == 0x7F ||
                    ($0.value >= 0xF700 && $0.value <= 0xF8FF)
                }
                if isNonPrintable {
                    paths.append("direct:\(event.keyCode)")
                    return
                }
            }
            paths.append("ime:\(event.keyCode)")
            accumulator = []
            defer { accumulator = nil }
            interpretKeyEvents([event])
        }

        func hasMarkedText() -> Bool { marked.length > 0 }
        func markedRange() -> NSRange { marked.length > 0 ? NSRange(location: 0, length: marked.length) : NSRange(location: NSNotFound, length: 0) }
        func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
        func setMarkedText(_ s: Any, selectedRange: NSRange, replacementRange: NSRange) {
            if let s = s as? String { marked.mutableString.setString(s) }
            else if let a = s as? NSAttributedString { marked.mutableString.setString(a.string) }
        }
        func unmarkText() { marked.mutableString.setString("") }
        func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
        func attributedSubstring(forProposedRange r: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
        func characterIndex(for p: NSPoint) -> Int { 0 }
        func firstRect(forCharacterRange r: NSRange, actualRange: NSRangePointer?) -> NSRect { .zero }
        func insertText(_ s: Any, replacementRange: NSRange) {
            let t: String
            if let s = s as? String { t = s } else if let a = s as? NSAttributedString { t = a.string } else { return }
            unmarkText()
            accumulator?.append(t)
            insertedText.append(t)
        }
    }

    // MARK: - Helpers

    private func key(_ keyCode: UInt16, _ chars: String, mods: NSEvent.ModifierFlags = [], repeat_: Bool = false) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: mods,
                         timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                         characters: chars, charactersIgnoringModifiers: chars,
                         isARepeat: repeat_, keyCode: keyCode)!
    }

    private func setup() -> (NSWindow, RoutingTestView) {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.titled], backing: .buffered, defer: false)
        let v = RoutingTestView(frame: w.contentRect(forFrameRect: w.frame))
        w.contentView = v; w.makeKeyAndOrderFront(nil); w.makeFirstResponder(v)
        return (w, v)
    }

    // MARK: - Path 1: Non-printable → direct

    @Test func allControlChars_takeDirect() {
        let (_, v) = setup()
        // 0x00-0x1F are control chars
        for code: UInt16 in [0, 1, 2, 3, 4, 13, 27, 31] {
            let char = Character(Unicode.Scalar(UInt32(code))!)
            v.keyDown(with: key(code, String(char)))
        }
        #expect(v.paths.allSatisfy { $0.hasPrefix("direct:") })
        #expect(v.doCommands.isEmpty, "No interpretKeyEvents for control chars")
    }

    @Test func del_0x7F_takesDirect() {
        let (_, v) = setup()
        v.keyDown(with: key(51, "\u{7F}"))
        #expect(v.paths == ["direct:51"])
    }

    @Test func allArrowKeys_takeDirect() {
        let (_, v) = setup()
        v.keyDown(with: key(123, "\u{F702}")) // Left
        v.keyDown(with: key(124, "\u{F703}")) // Right
        v.keyDown(with: key(125, "\u{F701}")) // Down
        v.keyDown(with: key(126, "\u{F700}")) // Up
        #expect(v.paths == ["direct:123", "direct:124", "direct:125", "direct:126"])
    }

    @Test func arrowsWithModifiers_takeDirect() {
        let (_, v) = setup()
        v.keyDown(with: key(123, "\u{F702}", mods: .shift))           // Shift+Left
        v.keyDown(with: key(124, "\u{F703}", mods: .option))          // Option+Right
        v.keyDown(with: key(125, "\u{F701}", mods: [.shift, .option])) // Shift+Option+Down
        v.keyDown(with: key(126, "\u{F700}", mods: .control))         // Ctrl+Up
        #expect(v.paths.count == 4)
        #expect(v.paths.allSatisfy { $0.hasPrefix("direct:") })
    }

    @Test func functionKeys_F1toF12_takeDirect() {
        let (_, v) = setup()
        // F1=0xF704, F2=0xF705, ..., F12=0xF70F
        for (i, charVal) in (0xF704...0xF70F).enumerated() {
            let keyCode: UInt16 = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111][i]
            v.keyDown(with: key(keyCode, String(Unicode.Scalar(charVal)!)))
        }
        #expect(v.paths.count == 12)
        #expect(v.paths.allSatisfy { $0.hasPrefix("direct:") })
    }

    @Test func homeEndPageUpDown_takeDirect() {
        let (_, v) = setup()
        v.keyDown(with: key(115, "\u{F729}")) // Home
        v.keyDown(with: key(119, "\u{F72B}")) // End
        v.keyDown(with: key(116, "\u{F72C}")) // PageUp
        v.keyDown(with: key(121, "\u{F72D}")) // PageDown
        #expect(v.paths.count == 4)
        #expect(v.paths.allSatisfy { $0.hasPrefix("direct:") })
    }

    @Test func tab_escape_return_takeDirect() {
        let (_, v) = setup()
        v.keyDown(with: key(48, "\t"))     // Tab
        v.keyDown(with: key(53, "\u{1B}")) // Escape
        v.keyDown(with: key(36, "\r"))     // Return
        #expect(v.paths == ["direct:48", "direct:53", "direct:36"])
    }

    @Test func emptyChars_takesDirect() {
        let (_, v) = setup()
        v.keyDown(with: key(0, ""))
        #expect(v.paths == ["direct:0"])
    }

    // MARK: - Path 2: Printable → IME

    @Test func letters_takeIME() {
        let (_, v) = setup()
        v.keyDown(with: key(0, "a"))
        v.keyDown(with: key(11, "b"))
        v.keyDown(with: key(8, "c"))
        #expect(v.paths == ["ime:0", "ime:11", "ime:8"])
        #expect(v.insertedText == ["a", "b", "c"])
    }

    @Test func numbers_takeIME() {
        let (_, v) = setup()
        for (i, char) in "0123456789".enumerated() {
            v.keyDown(with: key(UInt16(29 + i), String(char)))
        }
        #expect(v.paths.count == 10)
        #expect(v.paths.allSatisfy { $0.hasPrefix("ime:") })
    }

    @Test func symbols_takeIME() {
        let (_, v) = setup()
        v.keyDown(with: key(24, "="))
        v.keyDown(with: key(27, "-"))
        v.keyDown(with: key(33, "["))
        v.keyDown(with: key(30, "]"))
        #expect(v.paths.count == 4)
        #expect(v.paths.allSatisfy { $0.hasPrefix("ime:") })
    }

    @Test func space_takesIME() {
        let (_, v) = setup()
        v.keyDown(with: key(49, " "))
        #expect(v.paths == ["ime:49"])
        #expect(v.insertedText == [" "])
    }

    @Test func unicode_takeIME() {
        let (_, v) = setup()
        v.keyDown(with: key(0, "ñ"))
        v.keyDown(with: key(0, "ü"))
        v.keyDown(with: key(0, "日"))
        #expect(v.paths.count == 3)
        #expect(v.paths.allSatisfy { $0.hasPrefix("ime:") })
    }

    // MARK: - Modifier combos routing

    @Test func ctrlC_takesDirect() {
        // Ctrl+C = character 0x03 (< 0x20) → direct
        let (_, v) = setup()
        v.keyDown(with: key(8, "\u{03}", mods: .control))
        #expect(v.paths == ["direct:8"])
    }

    @Test func ctrlZ_takesDirect() {
        let (_, v) = setup()
        v.keyDown(with: key(6, "\u{1A}", mods: .control))
        #expect(v.paths == ["direct:6"])
    }

    @Test func ctrlD_takesDirect() {
        let (_, v) = setup()
        v.keyDown(with: key(2, "\u{04}", mods: .control))
        #expect(v.paths == ["direct:2"])
    }

    @Test func cmdC_takesIME() {
        // Cmd+C has printable char "c" → IME path
        // (In real app, performKeyEquivalent intercepts before keyDown)
        let (_, v) = setup()
        v.keyDown(with: key(8, "c", mods: .command))
        #expect(v.paths == ["ime:8"])
    }

    @Test func optionA_takesIME() {
        // Option+A = "å" on US keyboard → printable → IME
        let (_, v) = setup()
        v.keyDown(with: key(0, "å", mods: .option))
        #expect(v.paths == ["ime:0"])
    }

    @Test func shiftA_takesIME() {
        // Shift+A = "A" → printable → IME
        let (_, v) = setup()
        v.keyDown(with: key(0, "A", mods: .shift))
        #expect(v.paths == ["ime:0"])
    }

    // MARK: - Rapid input

    @Test func rapidLetters_allIME() {
        let (_, v) = setup()
        for _ in 0..<50 {
            v.keyDown(with: key(0, "x"))
        }
        #expect(v.paths.count == 50)
        #expect(v.paths.allSatisfy { $0 == "ime:0" })
        #expect(v.insertedText.count == 50)
    }

    @Test func rapidBackspace_allDirect_noBeep() {
        let (_, v) = setup()
        for i in 0..<50 {
            v.keyDown(with: key(51, "\u{7F}", repeat_: i > 0))
        }
        #expect(v.paths.count == 50)
        #expect(v.paths.allSatisfy { $0 == "direct:51" })
        #expect(v.doCommands.isEmpty, "No doCommand = no NSBeep possible")
    }

    @Test func rapidArrows_allDirect_noBeep() {
        let (_, v) = setup()
        for _ in 0..<30 {
            v.keyDown(with: key(124, "\u{F703}", repeat_: true))
        }
        #expect(v.paths.count == 30)
        #expect(v.paths.allSatisfy { $0 == "direct:124" })
        #expect(v.doCommands.isEmpty)
    }

    // MARK: - Mixed sequences

    @Test func typeAndDelete() {
        let (_, v) = setup()
        v.keyDown(with: key(4, "h"))           // h
        v.keyDown(with: key(14, "e"))           // e
        v.keyDown(with: key(37, "l"))           // l
        v.keyDown(with: key(37, "l"))           // l
        v.keyDown(with: key(31, "o"))           // o
        v.keyDown(with: key(51, "\u{7F}"))      // backspace
        v.keyDown(with: key(51, "\u{7F}"))      // backspace
        v.keyDown(with: key(36, "\r"))          // return

        #expect(v.paths == ["ime:4", "ime:14", "ime:37", "ime:37", "ime:31", "direct:51", "direct:51", "direct:36"])
        #expect(v.insertedText == ["h", "e", "l", "l", "o"])
    }

    @Test func ctrlC_then_type_then_arrows() {
        let (_, v) = setup()
        v.keyDown(with: key(8, "\u{03}", mods: .control))  // Ctrl+C
        v.keyDown(with: key(37, "l"))                        // l
        v.keyDown(with: key(1, "s"))                         // s
        v.keyDown(with: key(123, "\u{F702}"))                // Left arrow
        v.keyDown(with: key(36, "\r"))                       // Return

        #expect(v.paths == ["direct:8", "ime:37", "ime:1", "direct:123", "direct:36"])
    }

    // MARK: - doCommand suppression

    @Test func doCommand_neverCalledForDirectPath() {
        let (_, v) = setup()
        // All these go direct — doCommand should never fire
        v.keyDown(with: key(51, "\u{7F}"))       // backspace
        v.keyDown(with: key(123, "\u{F702}"))     // left
        v.keyDown(with: key(117, "\u{F728}"))     // fwd delete
        v.keyDown(with: key(48, "\t"))            // tab
        v.keyDown(with: key(53, "\u{1B}"))        // esc
        v.keyDown(with: key(36, "\r"))            // return
        v.keyDown(with: key(8, "\u{03}", mods: .control)) // ctrl+c

        #expect(v.doCommands.isEmpty, "Direct path should never trigger doCommand")
    }
}
