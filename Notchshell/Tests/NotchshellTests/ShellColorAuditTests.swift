import Testing
import AppKit
@testable import Notchshell

/// The audit reports shell colours that cannot follow a theme change. It reads and
/// never writes, so the risk is not damage — it is being wrong: a false alarm about a
/// git SHA, or missing the truecolor escapes that cause most of the trouble.
@Suite(.serialized)
struct ShellColorAuditTests {

    private let latteBackground = ShellColorAudit.colour(fromHex: "eff1f5")!   // Catppuccin Latte
    private let mochaBackground = ShellColorAudit.colour(fromHex: "1e1e2e")!   // Catppuccin Mocha

    private func withFixture(_ contents: String, name: String = "config.fish",
                             _ body: (String) throws -> Void) throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("notchshell-audit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent(name)
        try contents.write(to: file, atomically: true, encoding: .utf8)
        try body(file.path)
    }

    // MARK: - What it finds

    @Test func findsHexColoursAndNamesTheSetting() throws {
        try withFixture("set fish_color_command a6e3a1\n") { path in
            let findings = ShellColorAudit.scan(path, against: latteBackground)
            #expect(findings.count == 1)
            #expect(findings.first?.hex == "a6e3a1")
            #expect(findings.first?.label == "fish_color_command")
            #expect(findings.first?.line == 1)
        }
    }

    /// Truecolor escapes are where most of the damage lives — LS_COLORS and
    /// EZA_COLORS are usually long strings of them, and they look nothing like a hex
    /// literal.
    @Test func findsTruecolorEscapes() throws {
        try withFixture("set -gx LS_COLORS \"di=1;38;2;137;180;250:ex=1;38;2;166;227;161\"\n") { path in
            let findings = ShellColorAudit.scan(path, against: latteBackground)
            #expect(findings.count == 2)
            #expect(findings.map(\.hex).sorted() == ["89b4fa", "a6e3a1"])
            #expect(findings.allSatisfy { $0.label == "LS_COLORS" })
        }
    }

    @Test func acceptsAHashPrefix() throws {
        try withFixture("color = \"#d20f39\"\n", name: "starship.toml") { path in
            #expect(ShellColorAudit.scan(path, against: latteBackground).map(\.hex) == ["d20f39"])
        }
    }

    // MARK: - What it must not flag

    @Test func ignoresCommentedLines() throws {
        try withFixture("# set fish_color_command a6e3a1\n") { path in
            #expect(ShellColorAudit.scan(path, against: latteBackground).isEmpty)
        }
    }

    /// Six hex digits appear in plenty of things that are not colours. Flagging a
    /// commit hash as an unreadable colour would make the whole report untrustworthy.
    @Test func ignoresLongerHexRuns() throws {
        try withFixture("set sha 8bde9699ec7e190de05dbbf7952a2cac5c2b5fd7\n") { path in
            #expect(ShellColorAudit.scan(path, against: latteBackground).isEmpty)
        }
    }

    @Test func ignoresHexEmbeddedInAWord() throws {
        try withFixture("set path /tmp/abcdef123456xyz/thing\n") { path in
            #expect(ShellColorAudit.scan(path, against: latteBackground).isEmpty)
        }
    }

    @Test func ignoresOutOfRangeTruecolor() throws {
        try withFixture("set x \"38;2;999;180;250\"\n") { path in
            #expect(ShellColorAudit.scan(path, against: latteBackground).isEmpty)
        }
    }

    // MARK: - Contrast

    /// The whole point: the same colour is fine on the dark theme it was chosen for
    /// and unreadable on the light one.
    @Test func sameColourScoresDifferentlyPerBackground() throws {
        try withFixture("set fish_color_command a6e3a1\n") { path in
            let onLight = ShellColorAudit.scan(path, against: latteBackground)[0].contrast
            let onDark = ShellColorAudit.scan(path, against: mochaBackground)[0].contrast
            #expect(onLight < 3.0, "Catppuccin green on Latte is unreadable")
            #expect(onDark > 8.0, "the same green on Mocha is fine")
        }
    }

    @Test func contrastRatio_matchesKnownValues() {
        let black = ShellColorAudit.colour(fromHex: "000000")!
        let white = ShellColorAudit.colour(fromHex: "ffffff")!
        #expect(abs(ShellColorAudit.contrastRatio(black, white) - 21.0) < 0.01)
        #expect(abs(ShellColorAudit.contrastRatio(white, white) - 1.0) < 0.01)
    }

    @Test func report_countsOnlyTheUnreadableOnes() throws {
        // Catppuccin green (unreadable on Latte) and near-black (fine on Latte).
        try withFixture("set fish_color_command a6e3a1\nset fish_color_error 111111\n") { path in
            let findings = ShellColorAudit.scan(path, against: latteBackground)
            let report = ShellColorAudit.Report(findings: findings,
                                                themeName: "Catppuccin Latte",
                                                backgroundHex: "#eff1f5")
            #expect(report.findings.count == 2)
            #expect(report.unreadable.count == 1)
            #expect(report.unreadable.first?.hex == "a6e3a1")
            #expect(!report.isClean)
        }
    }

    /// Not an assertion — a printout of what the audit says about whatever shell
    /// config is on this machine, so the shipped implementation can be compared with
    /// the analysis it was built from.
    @Test func report_realConfigSummary() {
        let latte = ShellColorAudit.colour(fromHex: "eff1f5")!
        for path in ShellColorAudit.candidateFiles {
            let findings = ShellColorAudit.scan(path, against: latte)
            guard !findings.isEmpty else { continue }
            let unreadable = findings.filter { $0.contrast < 3.0 }
            print("  \((path as NSString).lastPathComponent): \(findings.count) colours, \(unreadable.count) below 3:1")
        }
    }

    @Test func missingFile_yieldsNothing() {
        let path = NSTemporaryDirectory() + "/notchshell-absent-\(UUID().uuidString)"
        #expect(ShellColorAudit.scan(path, against: latteBackground).isEmpty)
    }
}
