import Testing
import AppKit
import GhosttyKit
@testable import Notchshell

/// Tests for reading theme colors through libghostty.
///
/// These exercise the real C API, so `ghostty_init` must run first. It is safe to
/// call from the test process — `GhosttyConfigProbeTests` established that — and is
/// independent of `GhosttyApp.initialize()`, which deliberately no-ops under tests.
@MainActor
@Suite(.serialized)
struct GhosttyThemeCatalogTests {

    /// `ghostty_init` is process-global; run it once for the whole suite.
    private static let ghosttyReady: Bool = {
        ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS
    }()

    /// A theme that sets every color the app reads, in the format Ghostty ships.
    private static let fullTheme = """
    palette = 0=#191919
    palette = 1=#aa342e
    palette = 7=#bebebe
    palette = 15=#f7f7f7
    background = #102040
    foreground = #dddddd
    cursor-color = #007acc
    selection-background = #bfdbfe
    """

    /// A theme with no cursor/selection keys — the common case in the catalog.
    private static let minimalTheme = """
    palette = 0=#000000
    palette = 15=#ffffff
    background = #101010
    foreground = #e0e0e0
    """

    private func withThemeFile(_ contents: String, _ body: (String) throws -> Void) throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("notchshell-theme-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("TestTheme")
        try contents.write(to: file, atomically: true, encoding: .utf8)
        try body(file.path)
    }

    private func hex(_ color: NSColor) -> String {
        let c = color.usingColorSpace(.deviceRGB) ?? color
        return String(format: "#%02x%02x%02x",
                      Int((c.redComponent * 255).rounded()),
                      Int((c.greenComponent * 255).rounded()),
                      Int((c.blueComponent * 255).rounded()))
    }

    // MARK: - Palette comes from libghostty

    @Test func fullTheme_readsPaletteAndMetaColors() throws {
        #expect(Self.ghosttyReady)
        try withThemeFile(Self.fullTheme) { path in
            let theme = try #require(GhosttyThemeCatalog.terminalTheme(atPath: path))
            #expect(theme.ansiColors.count == 16)
            #expect(hex(theme.ansiColors[0]) == "#191919")
            #expect(hex(theme.ansiColors[1]) == "#aa342e")
            #expect(hex(theme.ansiColors[7]) == "#bebebe")
            #expect(hex(theme.ansiColors[15]) == "#f7f7f7")
            #expect(hex(theme.background) == "#102040")
            #expect(hex(theme.foreground) == "#dddddd")
        }
    }

    /// The old hand-rolled parser filled unset palette slots from a fixed stand-in
    /// palette. Ghostty generates them instead, so slots the theme omits must still
    /// be real colors rather than borrowed ones.
    @Test func unsetPaletteSlots_areFilledByGhostty() throws {
        #expect(Self.ghosttyReady)
        try withThemeFile(Self.fullTheme) { path in
            let theme = try #require(GhosttyThemeCatalog.terminalTheme(atPath: path))
            // Slots 2-6 and 8-14 are not in the fixture; Ghostty supplies defaults.
            #expect(theme.ansiColors.count == 16)
            #expect(hex(theme.ansiColors[2]) != hex(theme.ansiColors[1]))
        }
    }

    // MARK: - Optional colors

    @Test func fullTheme_readsCursorAndSelection() throws {
        #expect(Self.ghosttyReady)
        try withThemeFile(Self.fullTheme) { path in
            let theme = try #require(GhosttyThemeCatalog.terminalTheme(atPath: path))
            #expect(hex(theme.cursor) == "#007acc")
            #expect(hex(theme.selectionBackground) == "#bfdbfe")
        }
    }

    /// When a theme omits cursor/selection, they must be derived from the theme's own
    /// foreground — not from an unrelated fixed palette.
    @Test func minimalTheme_derivesCursorFromForeground() throws {
        #expect(Self.ghosttyReady)
        try withThemeFile(Self.minimalTheme) { path in
            let theme = try #require(GhosttyThemeCatalog.terminalTheme(atPath: path))
            #expect(hex(theme.cursor) == hex(theme.foreground))
            #expect(hex(theme.selectionBackground) == hex(theme.foreground))
            #expect(theme.selectionBackground.alphaComponent < 1.0)
        }
    }

    // MARK: - Failure is reported, never substituted

    @Test func missingFile_returnsNil() {
        #expect(Self.ghosttyReady)
        let path = NSTemporaryDirectory() + "/notchshell-does-not-exist-\(UUID().uuidString)"
        #expect(GhosttyThemeCatalog.terminalTheme(atPath: path) == nil)
    }

    @Test func unknownThemeName_returnsNil() {
        #expect(GhosttyThemeCatalog.parseTerminalTheme(named: "No Such Theme \(UUID().uuidString)") == nil)
    }

    /// A malformed theme must not silently resolve to Ghostty's built-in defaults —
    /// that would paint a confidently wrong palette.
    @Test func malformedTheme_returnsNil() throws {
        #expect(Self.ghosttyReady)
        try withThemeFile("this is not = a valid ghostty key\n") { path in
            #expect(GhosttyThemeCatalog.terminalTheme(atPath: path) == nil)
        }
    }

    // MARK: - The catalog we ship

    /// `bundledResourcesRoot` resolves against `Bundle.main`, which under tests is the
    /// test runner — so read the vendored catalog straight off disk instead. What this
    /// guards is the part that can actually rot: that every theme we ship is still
    /// readable by the libghostty-backed reader.
    private static var vendoredThemesDirectory: URL {
        URL(fileURLWithPath: #filePath)          // …/Notchshell/Tests/NotchshellTests/<this file>
            .deletingLastPathComponent()          // NotchshellTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // Notchshell
            .deletingLastPathComponent()          // repo root
            .appendingPathComponent("vendor/themes/themes")
    }

    @Test func vendoredCatalog_isPresent() throws {
        let names = try FileManager.default
            .contentsOfDirectory(atPath: Self.vendoredThemesDirectory.path)
            .filter { !$0.hasPrefix(".") }
        #expect(names.count > 400, "vendor/themes looks empty — run scripts/fetch-themes.sh")
    }

    @Test func vendoredCatalog_everyThemeParses() throws {
        #expect(Self.ghosttyReady)
        let dir = Self.vendoredThemesDirectory
        let names = try FileManager.default
            .contentsOfDirectory(atPath: dir.path)
            .filter { !$0.hasPrefix(".") }
            .sorted()

        var unreadable: [String] = []
        for name in names {
            let path = dir.appendingPathComponent(name).path
            guard let theme = GhosttyThemeCatalog.terminalTheme(atPath: path),
                  theme.ansiColors.count == 16 else {
                unreadable.append(name)
                continue
            }
        }
        #expect(unreadable.isEmpty, "unreadable themes: \(unreadable.prefix(10))")
    }
}
