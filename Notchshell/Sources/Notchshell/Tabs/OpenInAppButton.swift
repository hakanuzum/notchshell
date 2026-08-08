import SwiftUI
import AppKit

/// Hand the tab's folder to another app: Finder, or whichever editor you use.
///
/// The tab already knows where it is, and the alternative is typing `open -a "Visual
/// Studio Code" .` — a path the terminal is holding and you are retyping. This is the
/// return leg of the Finder extension: that one brings a folder here, this one takes it
/// back out.
struct OpenInAppButton: View {
    @ObservedObject var windowController: WindowController

    @State private var showList = false
    @State private var apps: [OpenTarget] = []
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: { showList.toggle() }) {
            // An app opening out of a box, which is the whole action. Not `folder`,
            // which reads as "make one", and not an app icon, which would be the only
            // colour in a row of monochrome glyphs.
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(FolderTabPalette.of(colorScheme).barIcon)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Open This Folder In…")
        .popover(isPresented: $showList, arrowEdge: .top) { list }
        .onChange(of: showList) { _, open in
            if open { apps = OpenTarget.available() }
            windowController.beginTransientInteraction(seconds: open ? 120 : 0.8)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(apps.enumerated()), id: \.element.id) { index, app in
                // Finder is the one everybody has and half the reason the button exists,
                // so it sits alone at the top rather than alphabetically among editors.
                if index > 0, apps[index - 1].isFinder {
                    Divider().padding(.vertical, 4)
                    Text("Editors & IDEs")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 4)
                }
                row(app)
            }
            if apps.isEmpty {
                Text("No apps found for this folder.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(10)
            }
        }
        .padding(.vertical, 6)
        .frame(width: 220)
    }

    private func row(_ app: OpenTarget) -> some View {
        Button(action: { open(app) }) {
            HStack(spacing: 8) {
                Image(nsImage: app.icon)
                    .resizable()
                    .frame(width: 16, height: 16)
                Text(app.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Open the folder, then get out of the way.
    ///
    /// The panel going down is part of the action, not tidiness afterwards: you asked to
    /// be taken somewhere, and a floating terminal left on top of the editor leaves no
    /// way to tell whether what you type next goes to the shell or to the app that just
    /// opened. The pin is left alone — it is a standing preference about auto-hide, not
    /// about this moment, and turning it off here would be a setting the user has to
    /// find and put back.
    private func open(_ app: OpenTarget) {
        showList = false
        guard let directory = currentDirectory else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let controller = windowController
        NSWorkspace.shared.open([directory], withApplicationAt: app.url,
                                configuration: configuration) { running, _ in
            // After the app is up, not before: hiding first would hand focus onward
            // while the editor is still launching, and the panel would go down over
            // whatever was behind it instead.
            Task { @MainActor in controller.hide(handingFocusTo: running) }
        }
    }

    /// The focused pane's directory, or nothing.
    ///
    /// Nothing rather than a guess: a pane that has not said where it is would otherwise
    /// send you to your home folder, which looks like the button misfired.
    private var currentDirectory: URL? {
        let path = windowController.tabManager.activeTab?.paneManager?.currentDirectory ?? ""
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }
}

/// An app this folder can be handed to.
struct OpenTarget: Identifiable {
    let url: URL
    let name: String
    let icon: NSImage
    var id: String { url.path }
    var isFinder: Bool { bundleID == "com.apple.finder" }
    let bundleID: String

    /// Finder first, then the editors that are actually installed.
    ///
    /// **LaunchServices alone is not the answer, measured.** Asked which apps can open a
    /// directory it returns Finder and a couple of editors, but also QuickTime Player,
    /// Archive Utility and Books — while omitting DataGrip and Xcode, which open folders
    /// every day. A folder is simply not a document type editors compete to claim. So
    /// the list is a curated one intersected with what is on this machine, and the
    /// LaunchServices answer is folded in afterwards for anything unforeseen, minus the
    /// handful that are noise.
    static func available() -> [OpenTarget] {
        var seen = Set<String>()
        var result: [OpenTarget] = []

        func add(_ bundleID: String) {
            guard !seen.contains(bundleID),
                  let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            else { return }
            seen.insert(bundleID)
            result.append(OpenTarget(
                url: url,
                name: FileManager.default.displayName(atPath: url.path)
                    .replacingOccurrences(of: ".app", with: ""),
                icon: NSWorkspace.shared.icon(forFile: url.path),
                bundleID: bundleID
            ))
        }

        add("com.apple.finder")
        for bundleID in editors { add(bundleID) }

        // Whatever else the system knows about, for the editor nobody thought of.
        if let directory = FileManager.default.urls(for: .userDirectory, in: .localDomainMask).first {
            for url in NSWorkspace.shared.urlsForApplications(toOpen: directory) {
                guard let bundleID = Bundle(url: url)?.bundleIdentifier,
                      !ignored.contains(bundleID),
                      bundleID != AppIdentity.bundleID
                else { continue }
                add(bundleID)
            }
        }
        return result
    }

    /// Editors and IDEs, in the order they are offered. Bundle identifiers rather than
    /// names: a name is localised and a path moves, an identifier is neither.
    private static let editors = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium",
        "com.todesktop.230313mzl4w4u92",            // Cursor
        "com.exafunction.windsurf",
        "dev.zed.Zed", "dev.zed.Zed-Preview",
        "com.sublimetext.4", "com.sublimetext.3",
        "com.apple.dt.Xcode",
        "com.jetbrains.intellij", "com.jetbrains.intellij.ce", "com.jetbrains.pycharm",
        "com.jetbrains.pycharm.ce", "com.jetbrains.WebStorm", "com.jetbrains.goland",
        "com.jetbrains.datagrip", "com.jetbrains.CLion", "com.jetbrains.rubymine",
        "com.jetbrains.PhpStorm", "com.jetbrains.rider", "com.jetbrains.fleet",
        "com.google.android.studio",
        "com.panic.Nova", "com.barebones.bbedit", "com.macromates.TextMate",
        "org.gnu.Emacs", "org.vim.MacVim", "com.neovide.neovide",
        "org.jkiss.dbeaver.core.product",
    ]

    /// Apps LaunchServices offers for a folder that nobody means: an archiver, a video
    /// player, and a book reader.
    private static let ignored: Set<String> = [
        "com.apple.QuickTimePlayerX", "com.apple.archiveutility", "com.apple.iBooksX",
    ]
}
