import Foundation

/// A coding-agent CLI that can be recognised in a tab's process tree.
///
/// The badge draws each tool's own logo, monochrome — see `AgentGlyphData`, generated
/// by `scripts/fetch-agent-icons.sh`. `mark` here is the fallback for tools with no
/// upstream icon.
///
/// Adding a tool is one case plus one line in `executables`.
enum AgentKind: String, CaseIterable, Sendable {
    case claude
    case codex
    case gemini
    case grok
    case copilot
    case cursor
    case aider
    case opencode
    case amp
    case goose
    case qwen
    case droid
    case crush
    case ollama

    /// Shown in the tooltip and the tab list.
    var label: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .gemini: return "Gemini CLI"
        case .grok: return "Grok CLI"
        case .copilot: return "GitHub Copilot CLI"
        case .cursor: return "Cursor Agent"
        case .aider: return "Aider"
        case .opencode: return "OpenCode"
        case .amp: return "Amp"
        case .goose: return "Goose"
        case .qwen: return "Qwen Code"
        case .droid: return "Droid"
        case .crush: return "Crush"
        case .ollama: return "Ollama"
        }
    }

    /// Fallback for a tool with no logo in `AgentGlyphData`. Two characters, because
    /// five of these tools begin with a C.
    var mark: String {
        switch self {
        case .claude: return "CL"
        case .codex: return "CX"
        case .gemini: return "GM"
        case .grok: return "GK"
        case .copilot: return "CP"
        case .cursor: return "CU"
        case .aider: return "AD"
        case .opencode: return "OC"
        case .amp: return "AM"
        case .goose: return "GS"
        case .qwen: return "QW"
        case .droid: return "DR"
        case .crush: return "CR"
        case .ollama: return "OL"
        }
    }

    /// Executable names, as they appear in `p_comm` or in `argv`.
    ///
    /// Lower-cased and compared exactly — a substring match would light the Claude
    /// badge for anything with `claude` in its path, which on this machine includes
    /// every shell that ever sourced a Claude Code snapshot.
    static let executables: [String: AgentKind] = [
        "claude": .claude,
        "claude-code": .claude,
        "codex": .codex,
        "gemini": .gemini,
        "grok": .grok,
        "copilot": .copilot,
        "gh-copilot": .copilot,
        "cursor-agent": .cursor,
        "aider": .aider,
        "opencode": .opencode,
        "amp": .amp,
        "goose": .goose,
        "qwen": .qwen,
        "qwen-code": .qwen,
        "droid": .droid,
        "crush": .crush,
        "ollama": .ollama,
    ]

    /// Match one executable name. Strips a `.js`/`.py` suffix, since an npm bin link
    /// is sometimes the script itself rather than a wrapper.
    static func matching(executableName name: String) -> AgentKind? {
        var stem = name.lowercased()
        for ext in [".js", ".mjs", ".cjs", ".py"] where stem.hasSuffix(ext) {
            stem.removeLast(ext.count)
            break
        }
        return executables[stem]
    }

}
