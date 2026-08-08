import SwiftUI

/// Two sections that used to live in Settings and are not settings.
///
/// One is a diagnostic that reports on a file this app deliberately never writes; the
/// other is documentation for the four routes macOS makes you answer separately.
/// Neither has a control to change anything, and Settings is being reduced to the
/// toggles and pickers you can act on at a glance.

// MARK: - Open from elsewhere

/// macOS has no default-terminal setting, so being reachable means answering four
/// routes separately. This is the list of them.
struct OpenFromElsewhereSection: View {
    @State private var cliMessage: String?
    @State private var cliInstalledAt: String? = CommandLineInstaller.existingInstallation()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Open From Elsewhere")
                .font(.headline)

            Text("macOS has no system-wide default terminal, so \(AppIdentity.displayName) makes itself reachable several ways.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    Text("Finder").font(.caption).foregroundColor(.secondary)
                    Text("right click a folder › Services › \(AppIdentity.finderServiceTitle)")
                        .font(.caption)
                }
                // Both are macOS features rather than anything this app installs, which
                // is why they work without a Finder extension — and an extension is not
                // an option while the build is signed ad-hoc, because macOS will not
                // load one that is not properly signed.
                GridRow {
                    Text("Toolbar").font(.caption).foregroundColor(.secondary)
                    Text("⌘-drag \(AppIdentity.displayName).app onto the Finder toolbar, then click it in any folder")
                        .font(.caption)
                }
                GridRow {
                    Text("Shortcut").font(.caption).foregroundColor(.secondary)
                    Text("give that service a key in System Settings › Keyboard › Keyboard Shortcuts › Services")
                        .font(.caption)
                }
                GridRow {
                    Text("Anywhere").font(.caption).foregroundColor(.secondary)
                    Text(verbatim: "open -a \(AppIdentity.displayName) <folder>")
                        .font(.system(size: 11, design: .monospaced))
                }
                GridRow {
                    Text("URL").font(.caption).foregroundColor(.secondary)
                    Text(verbatim: "\(AppIdentity.slug)://<folder>")
                        .font(.system(size: 11, design: .monospaced))
                }
                GridRow {
                    Text("Editors").font(.caption).foregroundColor(.secondary)
                    Text(verbatim: "\"terminal.external.osxExec\": \"\(AppIdentity.displayName).app\"")
                        .font(.system(size: 11, design: .monospaced))
                }
            }

            HStack(spacing: 10) {
                Button(cliInstalledAt == nil ? "Install Command Line Tool" : "Reinstall Command Line Tool") {
                    installCLI()
                }
                .buttonStyle(.bordered)
                Spacer()
            }

            if let cliInstalledAt {
                Text(verbatim: "\(AppIdentity.slug) → \(cliInstalledAt)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            if let cliMessage {
                Text(cliMessage).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func installCLI() {
        switch CommandLineInstaller.install() {
        case .installed(let path, let onPath):
            cliInstalledAt = path
            let directory = (path as NSString).deletingLastPathComponent
            cliMessage = onPath
                ? "Installed. Run `\(AppIdentity.slug)` from any shell."
                : "Installed, but \(directory) may not be on your PATH — add it if the command is not found."
        case .alreadyInstalled(let path):
            cliInstalledAt = path
            cliMessage = "Already installed."
        case .failed(let reason):
            cliMessage = reason
        }
    }
}

// MARK: - Shell colour audit

/// Reads the user's shell config and reports colours that cannot follow a theme.
///
/// Reports only. The edit belongs to whoever owns the file, and the conversion is not
/// mechanical: colours meant to recede measure *worse* after being converted, because a
/// dim grey in a dark palette is a light grey in a light one.
struct ShellColourAuditSection: View {
    @State private var report: ShellColorAudit.Report?
    @State private var auditRan = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Shell Colour Compatibility")
                .font(.headline)

            Text("A colour written as a hex value in your shell config is frozen — the terminal cannot repaint it when the theme changes, so colours picked against a dark background stay put on a light one. Colours written as ANSI names follow the theme instead.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Check My Shell Config") {
                    report = ShellColorAudit.audit(forDarkAppearance: false)
                    auditRan = true
                }
                .buttonStyle(.bordered)
                Spacer()
            }

            if let report {
                // Audited against the light theme on purpose: that is the side where a
                // colour chosen for a dark background stops being legible.
                Text("Checked against \(report.themeName) (\(report.backgroundHex)) — your light theme, where the problem shows.")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if report.findings.isEmpty {
                    Label("No hardcoded colours found.", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if report.isClean {
                    Label("\(report.findings.count) hardcoded colours, all still legible.",
                          systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Label("\(report.unreadable.count) of \(report.findings.count) fall below 3:1 and are effectively invisible.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)

                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(report.unreadable.prefix(12).enumerated()), id: \.offset) { _, finding in
                                HStack(spacing: 6) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(nsColor: ShellColorAudit.colour(fromHex: finding.hex) ?? .gray))
                                        .frame(width: 12, height: 12)
                                    Text(verbatim: "\(finding.file):\(finding.line)")
                                        .foregroundColor(.secondary)
                                    Text(verbatim: finding.label.isEmpty ? "#\(finding.hex)" : finding.label)
                                    Spacer()
                                    Text(String(format: "%.1f:1", finding.contrast))
                                        .foregroundColor(.secondary)
                                        .monospacedDigit()
                                }
                                .font(.system(size: 10, design: .monospaced))
                            }
                        }
                    }
                    .frame(maxHeight: 140)

                    Text("Fix by replacing the hex value with an ANSI name — `a6e3a1` becomes `green`, `38;2;137;180;250` becomes `34`. Colours meant to recede, like comments and autosuggestions, are fine as they are.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else if auditRan {
                Text("Could not read the active theme.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text("Nothing here is modified — your shell config is yours.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
