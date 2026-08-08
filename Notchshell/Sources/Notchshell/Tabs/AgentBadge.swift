import SwiftUI

/// The mark shown to the left of a tab's name when an agent CLI is running in it.
///
/// The tool's own logo, monochrome, drawn in whatever foreground colour the tab is
/// already using — so it reads as part of the chrome rather than as a sticker, and it
/// follows the light and dark tab states for free. The paths come from simple-icons
/// (see `scripts/fetch-agent-icons.sh`); a mark identifies the program running in the
/// tab, which is the whole reason it is there.
///
/// Tools with no upstream icon fall back to a letter mark. Inventing a logo for them
/// would produce something recognisably wrong, which is worse than a plain `AD`.
struct AgentBadge: View {
    let agent: AgentKind
    var size: CGFloat = 13
    /// Nothing is running; this tool merely worked in the tab's directory before. Drawn
    /// faded, so a badge you can act on never looks the same as one reporting a fact.
    var isDormant: Bool = false

    var body: some View {
        Group {
            if let pathData = AgentGlyphData.paths[agent] {
                AgentGlyphShape(pathData: pathData)
                    .frame(width: size, height: size)
            } else {
                Text(agent.mark)
                    .font(.system(size: size * 0.62, weight: .bold, design: .rounded))
                    .kerning(-0.3)
                    .frame(width: size * 1.35, height: size)
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                            .strokeBorder(lineWidth: 1)
                            .opacity(0.55)
                    )
            }
        }
        .opacity(isDormant ? 0.45 : 1)
        .help(isDormant ? "\(agent.label) ran here — click to resume" : agent.label)
        .accessibilityLabel(agent.label)
    }
}
