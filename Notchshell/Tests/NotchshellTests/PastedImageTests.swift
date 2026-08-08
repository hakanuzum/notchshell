import Testing
import AppKit
@testable import Notchshell

/// ⌘V with pixels on the clipboard pastes a path, because that is what the programs
/// people run in a terminal can actually take.
@MainActor
@Suite(.serialized)
struct PastedImageTests {

    private func board(_ configure: (NSPasteboard) -> Void) -> NSPasteboard {
        let board = NSPasteboard(name: .init("notchshell.test.\(UUID().uuidString)"))
        board.clearContents()
        configure(board)
        return board
    }

    private var sampleImage: NSImage {
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 4, height: 4).fill()
        image.unlockFocus()
        return image
    }

    // MARK: - Text wins

    /// Copying from a web page puts an image *and* its text on the board. Someone
    /// pressing ⌘V there means the text, and hijacking it would break ordinary pasting
    /// to serve the rarer case.
    @Test func textOnTheClipboard_isLeftAlone() {
        let board = self.board {
            $0.writeObjects([sampleImage])
            $0.setString("hello", forType: .string)
        }
        #expect(PastedImage.pathToPaste(board) == nil)
    }

    @Test func emptyClipboard_isLeftAlone() {
        let board = self.board { _ in }
        #expect(PastedImage.pathToPaste(board) == nil)
    }

    // MARK: - Files

    /// A file copied in Finder is already a path. Writing a second copy of it would be
    /// answering a question nobody asked.
    @Test func fileOnTheClipboard_usesItsOwnPath() throws {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("notchshell-paste-\(UUID().uuidString).txt")
        try "x".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let board = self.board { $0.writeObjects([url as NSURL]) }
        #expect(PastedImage.pathToPaste(board) == url.path)
    }

    // MARK: - Quoting

    /// A path with a space in it is a path someone will forget to quote — and every
    /// screenshot tool on this platform puts spaces in filenames.
    @Test func pathsWithSpaces_areQuoted() {
        let quoted = PastedImage.shellQuoted("/tmp/CleanShot 2026-08-08 at 15.36.43@2x.png")
        #expect(quoted.hasPrefix("'") && quoted.hasSuffix("'"))
    }

    @Test func plainPaths_areLeftBare() {
        #expect(PastedImage.shellQuoted("/tmp/shot.png") == "/tmp/shot.png")
    }

    /// A quote inside the path must not end the quoting early.
    @Test func pathsWithQuotes_areEscaped() {
        let quoted = PastedImage.shellQuoted("/tmp/it's here.png")
        #expect(quoted == "'/tmp/it'\\''s here.png'")
    }
}
