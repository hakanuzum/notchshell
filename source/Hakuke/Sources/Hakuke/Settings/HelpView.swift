import SwiftUI

struct HelpView: View {
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    private let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // MARK: - Header

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("hakuke \(version)")
                            .font(.title2.bold())
                        Text("Build \(build) · Powered by Ghostty")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 8) {
                        linkButton("Website", systemImage: "globe", url: "https://hakuke.com")
                        linkButton("GitHub", systemImage: "chevron.left.forwardslash.chevron.right", url: "https://github.com/hakanuzum/hakuke")
                        linkButton("Report Bug", systemImage: "ladybug", url: "https://github.com/hakanuzum/hakuke/issues")
                    }
                }

                Divider()

                // MARK: - Keyboard shortcuts

                VStack(alignment: .leading, spacing: 12) {
                    helpSection("Terminal") {
                        shortcutRow("Toggle terminal", "⌥ Space")
                        shortcutRow("Hide on click outside", "auto (unpin to enable)")
                        shortcutRow("Pin / Unpin", "⌘ ⇧ P")
                    }

                    helpSection("Tabs") {
                        shortcutRow("New tab", "⌘ T")
                        shortcutRow("Close tab", "⌘ W")
                        shortcutRow("Reopen closed tab", "⌘ ⇧ T")
                        shortcutRow("Next / Previous tab", "⌘ ⇧ ]  /  ⌘ ⇧ [  (configurable in Settings)")
                        shortcutRow("Go to tab 1–9", "⌘ 1 – ⌘ 9")
                        shortcutRow("Rename tab", "Double-click title")
                    }

                    helpSection("Split Panes") {
                        shortcutRow("Split horizontal", "⌘ D")
                        shortcutRow("Split vertical", "⌘ ⇧ D")
                        shortcutRow("Next / Previous pane", "⌘ ]  /  ⌘ [")
                        shortcutRow("Close pane", "⌘ W")
                    }

                    helpSection("Editing") {
                        shortcutRow("Copy / Paste", "⌘ C  /  ⌘ V")
                        shortcutRow("Clear screen", "⌘ K")
                        shortcutRow("Find", "⌘ F")
                    }
                }

                Divider()

                // MARK: - Ghostty config

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Ghostty Config")
                            .font(.headline)
                        Spacer()
                        Button("Open Config") {
                            GhosttyApp.shared.openConfig()
                        }
                        .font(.system(size: 11))
                    }

                    Text("Fonts, colors, keybindings, themes — all configured via Ghostty config.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }

                DisclosureGroup("Recommended Settings") {
                    VStack(alignment: .leading, spacing: 8) {
                        ZStack(alignment: .topTrailing) {
                            Text(Self.ghosttyConfigSnippet)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.primary)
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.3))
                                .cornerRadius(6)

                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(Self.ghosttyConfigSnippet, forType: .string)
                            }) {
                                Image(systemName: "doc.on.doc")
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                                    .padding(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, 4)
                    .padding(.top, 4)
                }

                Divider()

                // MARK: - API & MCP

                VStack(alignment: .leading, spacing: 8) {
                    Text("API & MCP")
                        .font(.headline)

                    Text("Socket API and MCP server for AI tools. Disabled by default — enable in Settings → API.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Link("Setup guide →", destination: URL(string: "https://hakuke.com#faq")!)
                        .font(.system(size: 12))
                }

                Divider()

                // MARK: - Troubleshooting

                DisclosureGroup("Troubleshooting") {
                    VStack(alignment: .leading, spacing: 10) {
                        troubleshootRow(
                            "Hotkey not working",
                            "Check System Settings → Privacy → Accessibility. Also check for conflicts with other apps (Raycast, Alfred, etc.)."
                        )
                        troubleshootRow(
                            "Wrong monitor",
                            "hakuke drops on the display where your cursor is. To pin to a specific monitor, use Settings → Display."
                        )
                        troubleshootRow(
                            "Themes/fonts not loading",
                            "Themes and fonts are configured in your Ghostty config file. Check that font names are correct and installed. Run 'ghostty +list-themes' to see available themes."
                        )
                        troubleshootRow(
                            "Reset all preferences",
                            "Run: defaults delete com.hakuke.terminal"
                        )
                    }
                    .padding(.leading, 4)
                    .padding(.top, 4)
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .preferredColorScheme(.dark)
    }

    private static let ghosttyConfigSnippet = """
    # Option key works as Alt/Meta (for Alt+B, Alt+F word navigation)
    macos-option-as-alt = true

    # Auto-copy selected text to system clipboard
    copy-on-select = clipboard

    # Shell integration (terminal title, working directory tracking)
    shell-integration = detect

    # Large scrollback for Claude Code output
    scrollback-limit = 100000

    # Font (install: brew install font-jetbrains-mono-nerd-font)
    font-family = JetBrainsMono Nerd Font
    font-size = 14
    font-thicken = true

    # Theme and colors
    theme = deep
    window-colorspace = display-p3

    # Shift+Arrow text selection in terminal viewport
    keybind = performable:shift+arrow_left=adjust_selection:left
    keybind = performable:shift+arrow_right=adjust_selection:right
    keybind = performable:shift+arrow_up=adjust_selection:up
    keybind = performable:shift+arrow_down=adjust_selection:down
    keybind = performable:shift+home=adjust_selection:home
    keybind = performable:shift+end=adjust_selection:end
    """

    // MARK: - View helpers

    private func helpSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
                .padding(.bottom, 2)
            content()
        }
    }

    private func shortcutRow(_ label: String, _ shortcut: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.primary)
            Spacer()
            Text(shortcut)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }

    private func troubleshootRow(_ title: String, _ fix: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
            Text(fix)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func linkButton(_ label: String, systemImage: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            Label(label, systemImage: systemImage)
                .font(.system(size: 11))
        }
    }
}
