import Foundation
import Testing
@testable import Notchshell

/// The only tests that exercise `SysctlProcessTable` — the `KERN_PROC_UID` walk and the
/// `KERN_PROCARGS2` parse — against the real kernel.
///
/// Everything else in `AgentScannerTests` runs on a fabricated tree, which proves the
/// walk but not the syscalls. These build the shape the app actually produces:
///
///     test process  →  /bin/sh (stamped with NOTCHSHELL_TAB_ID)  →  claude
///
/// `claude` is a copy of `/bin/sleep` under that name, because `p_comm` is the last
/// component of the executed path — which is exactly the property being relied on.
@Suite("Agent scanner, live process tree")
struct AgentScannerLiveTests {
    /// `sh -c` execs a lone command in place, which would collapse the tree to a single
    /// level. The trailing `true` keeps the fork.
    private static func spawnTree(binary: String, tabID: String?) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "'\(binary)' 30; true"]
        var environment = ProcessInfo.processInfo.environment
        environment[AgentScanner.tabIDEnvVar] = tabID
        process.environment = environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    private static func makeFakeAgent(named name: String) throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchshell-agent-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: URL(fileURLWithPath: "/bin/sleep"), to: destination)
        return destination.path
    }

    /// The grandchild takes a moment to appear; the scan is only meaningful once it has.
    private static func scanUntilFound(timeout: TimeInterval = 5) async -> [String: AgentKind] {
        let scanner = AgentScanner(table: SysctlProcessTable())
        let deadline = Date().addingTimeInterval(timeout)
        var result: [String: AgentKind] = [:]
        repeat {
            result = await scanner.scan(rootPID: getpid())
            if !result.isEmpty { return result }
            try? await Task.sleep(nanoseconds: 100_000_000)
        } while Date() < deadline
        return result
    }

    @Test func findsARealAgentThroughTheKernel() async throws {
        let binary = try Self.makeFakeAgent(named: "claude")
        let process = try Self.spawnTree(binary: binary, tabID: "live-tab")
        defer {
            process.terminate()
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: binary).deletingLastPathComponent()
            )
        }

        #expect(await Self.scanUntilFound() == ["live-tab": .claude])
    }

    /// An untagged shell is somebody else's terminal. Real `KERN_PROCARGS2` output has
    /// to yield no tab id, not a wrong one.
    @Test func ignoresARealAgentUnderAnUntaggedShell() async throws {
        let binary = try Self.makeFakeAgent(named: "codex")
        let process = try Self.spawnTree(binary: binary, tabID: nil)
        defer {
            process.terminate()
            try? FileManager.default.removeItem(
                at: URL(fileURLWithPath: binary).deletingLastPathComponent()
            )
        }

        // Give the tree the same head start the positive test waits for.
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let scanner = AgentScanner(table: SysctlProcessTable())
        #expect(await scanner.scan(rootPID: getpid()).isEmpty)
    }

    @Test func readsArgumentsAndEnvironmentOfThisProcess() {
        let details = SysctlProcessTable().details(for: getpid())
        #expect(details != nil)
        #expect(details?.arguments.isEmpty == false)
        // PATH is set for every process macOS launches.
        #expect(details?.environment["PATH"]?.isEmpty == false)
    }
}
