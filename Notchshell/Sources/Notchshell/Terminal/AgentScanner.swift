import Foundation

/// One row of the kernel process table, reduced to what the scan needs.
struct ProcessRow: Sendable, Equatable {
    let pid: Int32
    let parentPID: Int32
    /// `p_comm`, truncated by the kernel to 16 characters.
    let command: String
    /// `p_starttime.tv_sec`, used only to notice that a pid has been recycled.
    let startTime: Int64
}

/// A process's `argv` and environment, read together because the kernel returns both
/// from a single `KERN_PROCARGS2` call.
struct ProcessDetails: Sendable {
    let arguments: [String]
    let environment: [String: String]
}

/// The kernel-facing half of the scan, behind a protocol so `AgentScanner` can be
/// tested against a fabricated process tree.
protocol ProcessTable: Sendable {
    /// Every process owned by this user, in one call.
    func rows() -> [ProcessRow]
    /// `argv` + environment for one pid. Costs a syscall and a 1 MB copy, so the
    /// scanner caches the answer for the life of the process.
    func details(for pid: Int32) -> ProcessDetails?
}

/// Which agent CLI, if any, is running in each tab.
///
/// The mapping is exact rather than guessed. Every surface is spawned with
/// `NOTCHSHELL_TAB_ID` in its environment (`ghostty_surface_config_s.env_vars`), so a
/// pane's shell can be attributed to its tab by reading that shell's environment —
/// no window-title sniffing, no matching on working directory, and no patch to
/// libghostty, which exposes no pid for a surface.
///
/// The stamp is not looked for on our direct children: on macOS Ghostty runs the shell
/// under `/usr/bin/login`, which stays in the tree and whose own environment the kernel
/// will not disclose because it is setuid. The search takes the shallowest *readable*
/// stamped process on each branch instead, which in practice is the shell.
///
/// From each of those the walk goes *down*: the shallowest descendant whose executable is
/// in `AgentKind.executables` wins. Asking "what is in the foreground process group"
/// instead would flicker every time Claude Code shells out to `bash`; asking "is an
/// agent anywhere under this pane" does not, and is the question the badge answers.
actor AgentScanner {
    /// Environment variable carrying the tab a surface belongs to. Inherited by every
    /// descendant, which is what makes the attribution work at any depth.
    static let tabIDEnvVar = "NOTCHSHELL_TAB_ID"

    private let table: ProcessTable
    /// Keyed by pid, validated against start time so a recycled pid cannot inherit a
    /// dead process's answer.
    private var agentCache: [Int32: (startTime: Int64, agent: AgentKind?)] = [:]
    private var tabIDCache: [Int32: (startTime: Int64, tabID: String?)] = [:]

    init(table: ProcessTable = SysctlProcessTable()) {
        self.table = table
    }

    /// Tab id → agent, for every tab that currently has one.
    func scan(rootPID: Int32) -> [String: AgentKind] {
        let rows = table.rows()
        var byPID: [Int32: ProcessRow] = [:]
        var childrenOf: [Int32: [Int32]] = [:]
        for row in rows {
            byPID[row.pid] = row
            childrenOf[row.parentPID, default: []].append(row.pid)
        }

        var result: [String: AgentKind] = [:]
        for root in tabRoots(from: rootPID, byPID: byPID, childrenOf: childrenOf) {
            guard result[root.tabID] == nil,
                  let agent = firstAgent(under: root.process, byPID: byPID, childrenOf: childrenOf)
            else { continue }
            result[root.tabID] = agent
        }

        prune(keeping: Set(rows.map(\.pid)))
        return result
    }

    /// How far below our own process to go looking for a stamped process before giving
    /// up on a branch.
    ///
    /// Two is the number actually needed, measured against the running app. Ghostty
    /// spawns `/usr/bin/login -flp <user> /bin/bash -c "exec -l <shell>"` on macOS, so
    /// the shell is a grandchild — and `login` is setuid root, which makes
    /// `KERN_PROCARGS2` decline to hand over its arguments at all. The stamp is
    /// therefore never read from `login`; it is read from the shell one level below,
    /// which inherited it through `login -p`. Three leaves a layer of slack.
    private static let tabRootSearchDepth = 3

    /// The shallowest stamped process on each branch, with the tab it belongs to.
    ///
    /// Descent stops at a stamped process: everything below it is that tab's, so there
    /// is nothing to gain by reading the environment of every command an agent runs —
    /// and a great deal to lose, since each read is a syscall with a 1 MB buffer.
    private func tabRoots(
        from rootPID: Int32,
        byPID: [Int32: ProcessRow],
        childrenOf: [Int32: [Int32]]
    ) -> [(process: ProcessRow, tabID: String)] {
        var found: [(ProcessRow, String)] = []
        var frontier = childrenOf[rootPID] ?? []
        var depth = 1
        while !frontier.isEmpty, depth <= Self.tabRootSearchDepth {
            var next: [Int32] = []
            for pid in frontier {
                guard let row = byPID[pid] else { continue }
                if let tabID = tabID(of: row) {
                    found.append((row, tabID))
                } else {
                    next.append(contentsOf: childrenOf[pid] ?? [])
                }
            }
            frontier = next
            depth += 1
        }
        return found
    }

    // MARK: - Walk

    /// How far below the shell a process's arguments are worth a syscall.
    ///
    /// Agents are launched from the prompt, so they sit directly under the shell; one
    /// level of slack covers a wrapper like `npx` or `sudo`. Beyond that, only the free
    /// `p_comm` match applies — otherwise every `rg` and `bash` an agent spawns would
    /// cost a 1 MB `KERN_PROCARGS2` read. The search returns at the first match anyway,
    /// so a tab that *has* an agent never walks past it.
    private static let argumentProbeDepth = 2

    /// Breadth-first, so a pane running `claude` that has momentarily spawned a `bash`
    /// keeps its Claude badge rather than trading it for whatever the tool is running.
    private func firstAgent(
        under shell: ProcessRow,
        byPID: [Int32: ProcessRow],
        childrenOf: [Int32: [Int32]]
    ) -> AgentKind? {
        var queue: [(pid: Int32, depth: Int)] = (childrenOf[shell.pid] ?? []).map { ($0, 1) }
        var index = 0
        var visited: Set<Int32> = [shell.pid]
        while index < queue.count {
            let (pid, depth) = queue[index]
            index += 1
            guard visited.insert(pid).inserted, let row = byPID[pid] else { continue }
            if let agent = agent(of: row, depth: depth) { return agent }
            queue.append(contentsOf: (childrenOf[pid] ?? []).map { ($0, depth + 1) })
        }
        return nil
    }

    // MARK: - Per-process resolution

    private func agent(of row: ProcessRow, depth: Int) -> AgentKind? {
        if let hit = agentCache[row.pid], hit.startTime == row.startTime { return hit.agent }

        var resolved = AgentKind.matching(executableName: row.command)
        if resolved == nil, depth <= Self.argumentProbeDepth,
           let details = table.details(for: row.pid) {
            resolved = Self.agent(inArguments: details.arguments)
        }

        agentCache[row.pid] = (row.startTime, resolved)
        return resolved
    }

    /// `["claude"]` → `.claude`, `["node", "/opt/homebrew/bin/gemini"]` → `.gemini`.
    ///
    /// `argv[0]` has to be consulted, not just `p_comm`. The kernel takes `p_comm` from
    /// the last component of the *executable path*, and two of the tools that matter
    /// most exec a versioned binary: Claude Code reports `2.1.224` and Grok reports
    /// `grok-1.0.0-macos`, while both set `argv[0]` to their own name. Measured on the
    /// running app — matching on `p_comm` alone badged Codex and nothing else.
    ///
    /// The first non-flag argument after that covers a `#!/usr/bin/env node` tool, whose
    /// `argv[0]` is the interpreter.
    static func agent(inArguments arguments: [String]) -> AgentKind? {
        guard let first = arguments.first else { return nil }
        if let hit = AgentKind.matching(executableName: basename(first)) { return hit }
        for argument in arguments.dropFirst() {
            if argument.hasPrefix("-") { continue }
            return AgentKind.matching(executableName: basename(argument))
        }
        return nil
    }

    private func tabID(of row: ProcessRow) -> String? {
        if let hit = tabIDCache[row.pid], hit.startTime == row.startTime { return hit.tabID }
        let value = table.details(for: row.pid)?.environment[Self.tabIDEnvVar]
        let tabID = (value?.isEmpty ?? true) ? nil : value
        tabIDCache[row.pid] = (row.startTime, tabID)
        return tabID
    }

    private func prune(keeping live: Set<Int32>) {
        agentCache = agentCache.filter { live.contains($0.key) }
        tabIDCache = tabIDCache.filter { live.contains($0.key) }
    }

    static func basename(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return path }
        return String(path[path.index(after: slash)...])
    }
}

// MARK: - Kernel process table

/// `sysctl` implementation. One call returns the whole table; on a machine with ~500
/// processes that measured well under a millisecond, which is what makes a 2-second
/// poll defensible at all.
///
/// `KERN_PROC_ALL`, not `KERN_PROC_UID`: that filter matches on *effective* uid, and
/// `/usr/bin/login` — the process Ghostty puts between this app and the shell — is
/// setuid root. Asking for our own uid returns a table with a hole exactly where the
/// tree needs to be joined, so nothing below any tab is ever reachable. That cost a
/// while to find; the badges simply never appeared.
struct SysctlProcessTable: ProcessTable {
    func rows() -> [ProcessRow] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }

        let stride = MemoryLayout<kinfo_proc>.stride
        // Head-room: processes can appear between the sizing call and the read.
        var buffer = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 64)
        size = buffer.count * stride
        guard sysctl(&mib, 4, &buffer, &size, nil, 0) == 0 else { return [] }

        return buffer.prefix(size / stride).map { proc in
            var copy = proc
            let command = withUnsafePointer(to: &copy.kp_proc.p_comm) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) {
                    String(cString: $0)
                }
            }
            return ProcessRow(
                pid: proc.kp_proc.p_pid,
                parentPID: proc.kp_eproc.e_ppid,
                command: command,
                startTime: Int64(proc.kp_proc.p_un.__p_starttime.tv_sec)
            )
        }
    }

    func details(for pid: Int32) -> ProcessDetails? {
        var argmax: Int32 = 0
        var argmaxSize = MemoryLayout<Int32>.size
        var argmaxMIB: [Int32] = [CTL_KERN, KERN_ARGMAX]
        guard sysctl(&argmaxMIB, 2, &argmax, &argmaxSize, nil, 0) == 0, argmax > 0 else { return nil }

        var buffer = [CChar](repeating: 0, count: Int(argmax))
        var size = Int(argmax)
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else {
            return nil
        }
        return Self.parseProcArgs2(buffer, length: size)
    }

    /// `KERN_PROCARGS2` layout: `argc`, the executable path, some NUL padding, then
    /// `argc` argument strings, then the environment, all NUL-separated.
    static func parseProcArgs2(_ buffer: [CChar], length: Int) -> ProcessDetails? {
        var argc: Int32 = 0
        withUnsafeMutableBytes(of: &argc) { destination in
            buffer.withUnsafeBytes { source in
                destination.copyMemory(from: UnsafeRawBufferPointer(rebasing: source[0..<4]))
            }
        }
        guard argc > 0 else { return nil }

        var index = MemoryLayout<Int32>.size
        while index < length, buffer[index] != 0 { index += 1 }   // executable path
        while index < length, buffer[index] == 0 { index += 1 }   // its padding

        var strings: [String] = []
        var current: [UInt8] = []
        while index < length {
            let byte = UInt8(bitPattern: buffer[index])
            if byte == 0 {
                strings.append(String(decoding: current, as: UTF8.self))
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(byte)
            }
            index += 1
        }

        let count = min(Int(argc), strings.count)
        var environment: [String: String] = [:]
        for entry in strings.dropFirst(count) {
            guard let equals = entry.firstIndex(of: "=") else { continue }
            environment[String(entry[entry.startIndex..<equals])] = String(entry[entry.index(after: equals)...])
        }
        return ProcessDetails(arguments: Array(strings.prefix(count)), environment: environment)
    }
}
