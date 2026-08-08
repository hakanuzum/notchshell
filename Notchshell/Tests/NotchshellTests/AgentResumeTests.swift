import Testing
import Foundation
@testable import Notchshell

/// The resume table and the history store behind the dormant badge.
@MainActor
@Suite(.serialized)
struct AgentResumeTests {

    // MARK: - Resume command table

    /// Verified against `--help` on a machine with these installed. If one of these
    /// ever changes upstream, this is where it is caught rather than in a popover that
    /// silently runs a command the tool no longer understands.
    @Test func resumeCommands_matchTheVerifiedFour() {
        #expect(AgentKind.claude.resume?.cont == "claude --continue")
        #expect(AgentKind.claude.resume?.picker == "claude --resume")
        #expect(AgentKind.codex.resume?.cont == "codex resume --last")
        #expect(AgentKind.codex.resume?.picker == "codex resume")
        #expect(AgentKind.grok.resume?.cont == "grok --continue")
        #expect(AgentKind.copilot.resume?.cont == "copilot --continue")
    }

    /// Four tools deliberately have none: goose and droid need a session id this app
    /// does not keep, crush resumes only from inside its own UI, ollama has no
    /// sessions at all. A dormant badge for them would offer something it cannot do.
    @Test func resumeCommands_absentWhereTheyCannotWork() {
        #expect(AgentKind.goose.resume == nil)
        #expect(AgentKind.droid.resume == nil)
        #expect(AgentKind.crush.resume == nil)
        #expect(AgentKind.ollama.resume == nil)
    }

    /// A picker row is only drawn when the tool has one, so a tool without one must
    /// not claim it.
    @Test func resumeCommands_pickerOnlyWhereOneExists() {
        #expect(AgentKind.copilot.resume?.picker == nil)
        #expect(AgentKind.gemini.resume?.picker == nil)
        #expect(AgentKind.opencode.resume?.picker == nil)
        #expect(AgentKind.amp.resume?.picker == nil)
        #expect(AgentKind.aider.resume?.picker == nil)
    }

    @Test func everyResumeCommand_startsWithAKnownExecutable() throws {
        for agent in AgentKind.allCases {
            guard let resume = agent.resume else { continue }
            for command in [resume.cont, resume.picker].compactMap({ $0 }) {
                let executable = try #require(command.split(separator: " ").first)
                #expect(AgentKind.matching(executableName: String(executable)) == agent,
                        "\(command) does not start with an executable \(agent) is known by")
            }
        }
    }

    // MARK: - History store

    /// The store writes a file, so tests must be redirected or refused. This mirrors
    /// the `XDG_CONFIG_HOME` rule `ManagedConfig` carries: without a redirect, a test
    /// run would land in the developer's real `~/.local/share`.
    ///
    /// Asserted on *content*, not on the file's absence. The first version checked that
    /// no file existed, which passed only until the real app had ever run — the file it
    /// legitimately writes made the test fail for a reason that had nothing to do with
    /// the guard. What matters is that nothing this test recorded reaches the disk.
    @Test func historyStore_refusesToWriteFromATestWithoutRedirect() throws {
        guard ProcessInfo.processInfo.environment["XDG_DATA_HOME"] == nil else { return }
        let store = AgentHistoryStore.shared
        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchshell-guard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: marker, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: marker) }

        store.clear()
        store.record(agent: .claude, in: marker.path)

        if let data = try? Data(contentsOf: AgentHistoryStore.fileURL) {
            let written = String(decoding: data, as: UTF8.self)
            #expect(!written.contains(marker.lastPathComponent))
        }
        store.clear()
    }

    /// Recording is in-memory regardless of whether the write lands, so the badge is
    /// right for the rest of the session even when the file is refused.
    @Test func historyStore_recordsAndReadsBackInMemory() {
        let store = AgentHistoryStore.shared
        store.clear()
        let directory = FileManager.default.currentDirectoryPath

        store.record(agent: .claude, in: directory)
        let found = store.agents(in: directory)
        #expect(found.count == 1)
        #expect(found.first?.kind == .claude)
        store.clear()
    }

    /// A tool that cannot resume is not worth remembering — the badge it would produce
    /// opens a popover with nothing in it.
    @Test func historyStore_ignoresToolsThatCannotResume() {
        let store = AgentHistoryStore.shared
        store.clear()
        let directory = FileManager.default.currentDirectoryPath

        store.record(agent: .ollama, in: directory)
        #expect(store.agents(in: directory).isEmpty)
        store.clear()
    }

    /// A directory that no longer exists offers to resume work you cannot get back to.
    @Test func historyStore_dropsDirectoriesThatNoLongerExist() throws {
        let store = AgentHistoryStore.shared
        store.clear()

        let temporary = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("notchshell-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        store.record(agent: .claude, in: temporary.path)
        #expect(store.agents(in: temporary.path).count == 1)

        try FileManager.default.removeItem(at: temporary)
        // Pruning runs on the next write, so provoke one somewhere that does exist.
        store.record(agent: .codex, in: FileManager.default.currentDirectoryPath)
        #expect(store.agents(in: temporary.path).isEmpty)
        store.clear()
    }

    /// Trailing slashes make two names for one directory, and a tab standing in one of
    /// them would fail to recognise a record written under the other.
    @Test func historyStore_treatsEquivalentPathsAsOneDirectory() {
        let store = AgentHistoryStore.shared
        store.clear()
        let directory = FileManager.default.currentDirectoryPath

        store.record(agent: .claude, in: directory + "/")
        #expect(store.agents(in: directory).count == 1)
        store.clear()
    }

    @Test func historyStore_returnsNothingForAnUnknownDirectory() {
        let store = AgentHistoryStore.shared
        store.clear()
        #expect(store.agents(in: "/nonexistent-\(UUID().uuidString)").isEmpty)
    }
}
