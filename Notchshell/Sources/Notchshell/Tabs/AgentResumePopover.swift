import SwiftUI

/// The list behind a dormant agent badge: which tools have worked in this directory,
/// and one click back into each.
///
/// Two rows per tool at most. The first runs the tool's "carry on" command, because
/// carrying on is what you almost always want; the second opens the tool's own session
/// picker, for the times you want an older one. Tools with no picker of their own get
/// only the first row rather than a disabled second — a row that cannot be clicked
/// teaches nothing.
struct AgentResumePopover: View {
    let agents: [AgentKind]
    let onResume: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Ran in this folder")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 2)

            ForEach(agents, id: \.self) { agent in
                if let resume = agent.resume {
                    row(agent.label, command: resume.cont, agent: agent)
                    if let picker = resume.picker {
                        row("All sessions…", command: picker, agent: nil)
                    }
                }
            }
        }
        .padding(.bottom, 6)
        .frame(minWidth: 190)
    }

    private func row(_ title: String, command: String, agent: AgentKind?) -> some View {
        Button {
            onResume(command)
        } label: {
            HStack(spacing: 7) {
                if let agent {
                    AgentBadge(agent: agent, size: 12)
                } else {
                    // Indent to the width the badge occupies, so the secondary row
                    // reads as belonging to the tool above it.
                    Color.clear.frame(width: 12, height: 12)
                }
                Text(title)
                    .font(.system(size: 11, weight: agent == nil ? .regular : .medium))
                    .foregroundStyle(agent == nil ? .secondary : .primary)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
