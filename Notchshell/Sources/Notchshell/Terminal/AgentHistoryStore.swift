import Foundation
import os.log

/// Remembers that an agent CLI once ran in a directory, so a tab opened there again can
/// offer to pick the conversation back up.
///
/// The record is deliberately thin: a directory, which tools ran in it, and when each
/// was last seen. No session ids, no transcripts, nothing read out of an agent's own
/// files. Resuming is the tool's job — Notchshell only knows there is something to
/// resume. Anything richer would mean parsing formats this app does not own, and those
/// change without notice.
///
/// A visible file rather than `UserDefaults`, because it is a list of the directories
/// you work in: you should be able to read it, and delete it, without a debugger.
@MainActor
final class AgentHistoryStore {
    static let shared = AgentHistoryStore()

    /// Enough to cover the projects anyone moves between; past that, the oldest goes.
    static let maxDirectories = 50

    struct Entry: Codable, Equatable {
        var agent: String
        var lastSeen: Date

        var kind: AgentKind? { AgentKind(rawValue: agent) }
    }

    private struct Record: Codable, Equatable {
        var directory: String
        var entries: [Entry]
        var lastSeen: Date
    }

    private var records: [Record] = []
    private var loaded = false

    static var fileURL: URL {
        URL(fileURLWithPath: AppIdentity.dataDirectory)
            .appendingPathComponent("agent-history.json")
    }

    /// Off unless explicitly on — the toggle exists so the list of directories you work
    /// in is yours to refuse.
    private var enabled: Bool {
        let defaults = UserDefaults.standard
        return defaults.object(forKey: "rememberAgentHistory") == nil
            || defaults.bool(forKey: "rememberAgentHistory")
    }

    // MARK: - Reading

    /// Agents last seen in this directory, most recent first. Empty when the directory
    /// is unknown, when history is off, or when nothing there can resume anyway.
    func agents(in directory: String) -> [Entry] {
        guard enabled else { return [] }
        load()
        let key = Self.normalize(directory)
        guard !key.isEmpty,
              let record = records.first(where: { $0.directory == key }) else { return [] }
        return record.entries
            .filter { $0.kind?.resume != nil }
            .sorted { $0.lastSeen > $1.lastSeen }
    }

    // MARK: - Writing

    func record(agent: AgentKind, in directory: String) {
        guard enabled, agent.resume != nil else { return }
        let key = Self.normalize(directory)
        guard !key.isEmpty else { return }
        load()

        let now = Date()
        if let index = records.firstIndex(where: { $0.directory == key }) {
            records[index].lastSeen = now
            if let e = records[index].entries.firstIndex(where: { $0.agent == agent.rawValue }) {
                // Nothing changed but the clock; skip the write and the disk churn that
                // a 2-second scan would otherwise cause all day.
                guard now.timeIntervalSince(records[index].entries[e].lastSeen) > 60 else { return }
                records[index].entries[e].lastSeen = now
            } else {
                records[index].entries.append(Entry(agent: agent.rawValue, lastSeen: now))
            }
        } else {
            records.append(Record(directory: key,
                                  entries: [Entry(agent: agent.rawValue, lastSeen: now)],
                                  lastSeen: now))
        }

        prune()
        save()
    }

    func clear() {
        records = []
        loaded = true
        guard Self.canWrite else { return }
        try? FileManager.default.removeItem(at: Self.fileURL)
    }

    // MARK: - Storage

    /// Trailing slashes and `..` make two names for one directory, and two names would
    /// mean a tab failing to recognise the very directory it is standing in.
    private static func normalize(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "~" else { return "" }
        return (trimmed as NSString).standardizingPath
    }

    /// Drop directories that no longer exist, then the oldest beyond the cap. A stale
    /// entry is worse than no entry: it offers to resume work in a folder you deleted.
    private func prune() {
        let fm = FileManager.default
        records.removeAll { !fm.fileExists(atPath: $0.directory) }
        guard records.count > Self.maxDirectories else { return }
        records.sort { $0.lastSeen > $1.lastSeen }
        records.removeLast(records.count - Self.maxDirectories)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: Self.fileURL) else { return }
        records = (try? JSONDecoder().decode([Record].self, from: data)) ?? []
    }

    /// The same guard `ManagedConfig` carries, for the same reason: a test that forgets
    /// to redirect writes into the developer's real home and still passes.
    private static var canWrite: Bool {
        guard AppIdentity.isTestEnvironment else { return true }
        if ProcessInfo.processInfo.environment["XDG_DATA_HOME"] != nil { return true }
        os_log(.error, "Refusing to write agent history from a test — redirect XDG_DATA_HOME first")
        return false
    }

    private func save() {
        guard Self.canWrite else { return }
        let url = Self.fileURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(records)
            try data.write(to: url, options: .atomic)
        } catch {
            os_log(.error, "Could not write agent history: %{public}@",
                   error.localizedDescription)
        }
    }
}
