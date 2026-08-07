import Testing
@testable import Notchshell

/// A fabricated process tree, so the walk can be exercised without spawning anything.
private struct FakeProcessTable: ProcessTable {
    var processes: [ProcessRow]
    var detailsByPID: [Int32: ProcessDetails] = [:]

    func rows() -> [ProcessRow] { processes }
    func details(for pid: Int32) -> ProcessDetails? { detailsByPID[pid] }
}

private func row(_ pid: Int32, _ ppid: Int32, _ command: String) -> ProcessRow {
    ProcessRow(pid: pid, parentPID: ppid, command: command, startTime: 1000)
}

private func shellDetails(tabID: String?) -> ProcessDetails {
    var environment = ["TERM": "xterm-ghostty"]
    if let tabID { environment[AgentScanner.tabIDEnvVar] = tabID }
    return ProcessDetails(arguments: ["-zsh"], environment: environment)
}

@Suite("Agent name matching")
struct AgentKindMatchingTests {
    @Test func matchesExactExecutableNames() {
        #expect(AgentKind.matching(executableName: "claude") == .claude)
        #expect(AgentKind.matching(executableName: "cursor-agent") == .cursor)
        #expect(AgentKind.matching(executableName: "CODEX") == .codex)
    }

    /// A substring match would badge every shell that ever sourced a Claude Code
    /// snapshot — which, on a machine with Claude Code installed, is all of them.
    @Test func doesNotMatchSubstrings() {
        #expect(AgentKind.matching(executableName: "claude-usage") == nil)
        #expect(AgentKind.matching(executableName: "zsh") == nil)
        #expect(AgentKind.matching(executableName: "not-claude") == nil)
    }

    @Test func stripsScriptExtensions() {
        #expect(AgentKind.matching(executableName: "gemini.js") == .gemini)
        #expect(AgentKind.matching(executableName: "aider.py") == .aider)
    }

    /// The shapes measured on the running app. Claude Code and Grok both exec a
    /// versioned binary, so `p_comm` is a version string and only `argv[0]` names them.
    @Test func readsToolNameFromArguments() {
        #expect(AgentScanner.agent(inArguments: ["claude"]) == .claude)
        #expect(AgentScanner.agent(inArguments: ["grok"]) == .grok)
        #expect(AgentScanner.agent(inArguments: ["node", "/opt/homebrew/bin/gemini"]) == .gemini)
        #expect(AgentScanner.agent(inArguments: ["python3", "-u", "/usr/local/bin/aider"]) == .aider)
        #expect(AgentScanner.agent(inArguments: ["opencode", ""]) == .opencode)
        #expect(AgentScanner.agent(inArguments: ["node", "/usr/local/bin/tsc"]) == nil)
    }
}

@Suite("Agent scanner")
struct AgentScannerTests {
    /// app → shell (tagged with its tab) → claude
    @Test func findsAgentUnderTaggedShell() async {
        let table = FakeProcessTable(
            processes: [
                row(100, 1, "Notchshell"),
                row(200, 100, "zsh"),
                row(300, 200, "claude"),
            ],
            detailsByPID: [200: shellDetails(tabID: "tab-a")]
        )
        let scanner = AgentScanner(table: table)
        #expect(await scanner.scan(rootPID: 100) == ["tab-a": .claude])
    }

    /// The shell alone is not an agent, and a tab with nothing running gets no entry.
    @Test func reportsNothingForABareShell() async {
        let table = FakeProcessTable(
            processes: [row(100, 1, "Notchshell"), row(200, 100, "zsh")],
            detailsByPID: [200: shellDetails(tabID: "tab-a")]
        )
        let scanner = AgentScanner(table: table)
        #expect(await scanner.scan(rootPID: 100).isEmpty)
    }

    /// Without the environment stamp there is no way back to a tab, so the process is
    /// ignored rather than guessed at.
    @Test func ignoresShellsWithoutATabID() async {
        let table = FakeProcessTable(
            processes: [
                row(100, 1, "Notchshell"),
                row(200, 100, "zsh"),
                row(300, 200, "claude"),
            ],
            detailsByPID: [200: shellDetails(tabID: nil)]
        )
        let scanner = AgentScanner(table: table)
        #expect(await scanner.scan(rootPID: 100).isEmpty)
    }

    /// This is the flicker case. Claude Code shells out constantly; a foreground-process
    /// reading would swap the badge for `bash` and back twice a second.
    @Test func keepsTheAgentWhileItRunsASubprocess() async {
        let table = FakeProcessTable(
            processes: [
                row(100, 1, "Notchshell"),
                row(200, 100, "zsh"),
                row(300, 200, "claude"),
                row(400, 300, "bash"),
                row(500, 400, "rg"),
            ],
            detailsByPID: [200: shellDetails(tabID: "tab-a")]
        )
        let scanner = AgentScanner(table: table)
        #expect(await scanner.scan(rootPID: 100) == ["tab-a": .claude])
    }

    /// Claude Code execs `~/.local/share/claude/versions/<version>`, so the kernel calls
    /// the process `2.1.224`. Matching on `p_comm` alone missed it entirely; `argv[0]`
    /// is what names the tool.
    @Test func resolvesAVersionedBinaryByItsArguments() async {
        let table = FakeProcessTable(
            processes: [
                row(100, 1, "Notchshell"),
                row(150, 100, "login"),
                row(200, 150, "fish"),
                row(300, 200, "2.1.224"),
            ],
            detailsByPID: [
                200: shellDetails(tabID: "tab-a"),
                300: ProcessDetails(arguments: ["claude"], environment: [:]),
            ]
        )
        let scanner = AgentScanner(table: table)
        #expect(await scanner.scan(rootPID: 100) == ["tab-a": .claude])
    }

    /// Arguments are only read near the shell. An agent's own subprocesses sit deeper,
    /// and reading each one would be a 1 MB syscall several times a second.
    @Test func doesNotReadArgumentsDeepUnderTheShell() async {
        let table = FakeProcessTable(
            processes: [
                row(100, 1, "Notchshell"),
                row(200, 100, "zsh"),
                row(300, 200, "make"),
                row(400, 300, "sh"),
                row(500, 400, "1.2.3"),
            ],
            detailsByPID: [
                200: shellDetails(tabID: "tab-a"),
                // Depth 3 below the shell: never probed, so this never becomes a badge.
                500: ProcessDetails(arguments: ["claude"], environment: [:]),
            ]
        )
        let scanner = AgentScanner(table: table)
        #expect(await scanner.scan(rootPID: 100).isEmpty)
    }

    /// A shebang tool: the kernel reports the interpreter, the argument carries the name.
    @Test func resolvesAnInterpretedTool() async {
        let table = FakeProcessTable(
            processes: [
                row(100, 1, "Notchshell"),
                row(200, 100, "fish"),
                row(300, 200, "node"),
            ],
            detailsByPID: [
                200: shellDetails(tabID: "tab-b"),
                300: ProcessDetails(
                    arguments: ["node", "/opt/homebrew/bin/gemini"], environment: [:]
                ),
            ]
        )
        let scanner = AgentScanner(table: table)
        #expect(await scanner.scan(rootPID: 100) == ["tab-b": .gemini])
    }

    /// The shape the app actually produces. Ghostty spawns `/usr/bin/login -flp …` on
    /// macOS and `login` stays in the tree, so the shell is a grandchild. `login` is
    /// setuid root, so `KERN_PROCARGS2` declines to hand over its environment — hence no
    /// details for pid 150 here. The stamp is read from the shell, which inherited it.
    @Test func findsAgentThroughTheSetuidLoginWrapper() async {
        let table = FakeProcessTable(
            processes: [
                row(100, 1, "Notchshell"),
                row(150, 100, "login"),
                row(200, 150, "fish"),
                row(300, 200, "codex"),
            ],
            detailsByPID: [200: shellDetails(tabID: "tab-a")]
        )
        let scanner = AgentScanner(table: table)
        #expect(await scanner.scan(rootPID: 100) == ["tab-a": .codex])
    }

    /// Descent stops at a stamped process. Reading the environment of everything an
    /// agent runs would be a syscall per subprocess, several times a second.
    @Test func doesNotProbeBelowAStampedProcess() async {
        let table = FakeProcessTable(
            processes: [
                row(100, 1, "Notchshell"),
                row(150, 100, "login"),
                row(200, 150, "fish"),
                row(300, 200, "claude"),
                row(400, 300, "bash"),
            ],
            detailsByPID: [
                150: shellDetails(tabID: "tab-a"),
                // Never read: 150 is stamped, so the walk below it looks for an agent,
                // not for another tab.
                400: shellDetails(tabID: "wrong-tab"),
            ]
        )
        let scanner = AgentScanner(table: table)
        #expect(await scanner.scan(rootPID: 100) == ["tab-a": .claude])
    }

    /// Splits share their tab's id. One pane running an agent badges the tab.
    @Test func anyPaneOfATabBadgesIt() async {
        let table = FakeProcessTable(
            processes: [
                row(100, 1, "Notchshell"),
                row(200, 100, "zsh"),
                row(210, 100, "zsh"),
                row(310, 210, "codex"),
            ],
            detailsByPID: [
                200: shellDetails(tabID: "tab-c"),
                210: shellDetails(tabID: "tab-c"),
            ]
        )
        let scanner = AgentScanner(table: table)
        #expect(await scanner.scan(rootPID: 100) == ["tab-c": .codex])
    }

    @Test func separatesTabs() async {
        let table = FakeProcessTable(
            processes: [
                row(100, 1, "Notchshell"),
                row(200, 100, "zsh"),
                row(300, 200, "claude"),
                row(210, 100, "zsh"),
                row(310, 210, "codex"),
            ],
            detailsByPID: [
                200: shellDetails(tabID: "tab-a"),
                210: shellDetails(tabID: "tab-b"),
            ]
        )
        let scanner = AgentScanner(table: table)
        #expect(await scanner.scan(rootPID: 100) == ["tab-a": .claude, "tab-b": .codex])
    }

    /// Another terminal's `claude` is not ours: the walk starts at our own pid.
    @Test func ignoresProcessesOutsideOurTree() async {
        let table = FakeProcessTable(
            processes: [
                row(100, 1, "Notchshell"),
                row(900, 1, "iTerm2"),
                row(910, 900, "zsh"),
                row(920, 910, "claude"),
            ],
            detailsByPID: [910: shellDetails(tabID: "tab-a")]
        )
        let scanner = AgentScanner(table: table)
        #expect(await scanner.scan(rootPID: 100).isEmpty)
    }
}

@Suite("Pane environment")
struct PaneEnvironmentTests {
    @Test func stampsTheTabID() {
        #expect(PaneManager.environment(tabID: "abc") == [AgentScanner.tabIDEnvVar: "abc"])
    }

    @Test func stampsNothingWithoutATab() {
        #expect(PaneManager.environment(tabID: nil).isEmpty)
        #expect(PaneManager.environment(tabID: "").isEmpty)
    }
}
