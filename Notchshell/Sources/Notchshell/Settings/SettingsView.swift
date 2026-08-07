import SwiftUI
import ServiceManagement
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleTerminal = Self("toggleTerminal", default: .init(.space, modifiers: .option))
    static let nextTab = Self("nextTab", default: .init(.rightBracket, modifiers: [.command, .shift]))
    static let previousTab = Self("previousTab", default: .init(.leftBracket, modifiers: [.command, .shift]))
}

/// Collects the widest measured label width among a set of sibling buttons, so they can
/// all adopt it. See `SettingsView.advancedButton`.
private struct ButtonWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// A segmented control whose segments stretch to fill the width it is given.
///
/// SwiftUI's `.pickerStyle(.segmented)` sizes to its option labels and cannot be made to
/// fill — a fixed frame is ignored and `maxWidth: .infinity` only centres it — so two
/// controls with different option counts never share an edge. `NSSegmentedControl` with
/// `segmentDistribution = .fillEqually` does fill, and low hugging lets SwiftUI's frame
/// drive its width, so a column of these all reach the same right edge.
private struct FillingSegmentedControl<Tag: Hashable>: NSViewRepresentable {
    let options: [(label: String, tag: Tag)]
    @Binding var selection: Tag

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: options.map(\.label),
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.selectionChanged(_:)))
        control.segmentStyle = .rounded
        control.segmentDistribution = .fillEqually
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        if let index = options.firstIndex(where: { $0.tag == selection }) {
            control.selectedSegment = index
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: FillingSegmentedControl
        init(_ parent: FillingSegmentedControl) { self.parent = parent }
        @objc func selectionChanged(_ sender: NSSegmentedControl) {
            let index = sender.selectedSegment
            guard parent.options.indices.contains(index) else { return }
            parent.selection = parent.options[index].tag
        }
    }
}

/// Everything you can change at a glance: toggles and pickers, nothing that needs
/// reading first.
///
/// Three kinds of thing were taken out. Font size, opacity, panel height and the theme
/// list now have a control on the tab bar that is faster than opening this at all —
/// keeping a second copy meant two places to change one value and two chances to
/// disagree. The shell-colour audit and the "open from elsewhere" routes moved to Help,
/// because a diagnostic and a list of URL schemes are things you read, not things you
/// set. And the sliders that remained became pickers, since nobody wants a continuum of
/// blur radii — they want one of about four.
///
/// The one theme control still here is the light/dark *pair*. The palette button cannot
/// express it, and a pair is the whole reason `ghostty_surface_set_color_scheme` is fed
/// the real system appearance rather than a constant.
struct SettingsView: View {
    @ObservedObject var windowController: WindowController

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @AppStorage("apiAccess") private var apiAccess: String = "ask"
    @AppStorage("mcpAccess") private var mcpAccess: String = "ask"
    @AppStorage("confirmOnQuit") private var confirmOnQuit: Bool = false
    @AppStorage("restoreTabsOnLaunch") private var restoreTabsOnLaunch: Bool = true
    @AppStorage("disableAnimation") private var disableAnimation: Bool = false
    @AppStorage("shellPath") private var shellPath: String = ""

    @State private var customShellPath: String = ""
    @State private var isCustomShell: Bool = false
    @State private var customShellProblem: String?
    @FocusState private var shellFieldFocused: Bool

    /// Width of the widest Advanced button label, so they all match it. See advancedButton.
    @State private var advancedButtonWidth: CGFloat = 0

    @StateObject private var themeCatalog = ThemeCatalogStore()
    @State private var followsAppearance: Bool =
        GhosttyThemeCatalog.currentSelection()?.followsSystemAppearance ?? false
    @State private var lightTheme: String =
        GhosttyThemeCatalog.currentSelection()?.lightTheme ?? "Catppuccin Latte"
    @State private var darkTheme: String =
        GhosttyThemeCatalog.currentSelection()?.darkTheme ?? "Catppuccin Mocha"

    @State private var fontFamily: String = TerminalAppearanceSettings.string(.fontFamily) ?? ""
    @State private var cursorStyle: String = TerminalAppearanceSettings.string(.cursorStyle) ?? "block"
    @State private var blurRadius: Int = TerminalAppearanceSettings.int(.backgroundBlurRadius) ?? 0

    private static let knownShells = [
        "/bin/zsh", "/bin/bash", "/bin/sh",
        "/usr/local/bin/fish", "/opt/homebrew/bin/fish",
        "/usr/local/bin/zsh", "/opt/homebrew/bin/zsh",
        "/usr/local/bin/bash", "/opt/homebrew/bin/bash",
    ]

    private var availableShells: [String] {
        Self.knownShells.filter { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Blur is a continuum in Ghostty and a choice of about four to everyone else.
    private static let blurChoices: [(label: String, value: Int)] = [
        ("Off", 0), ("Light", 10), ("Medium", 20), ("Strong", 35),
    ]

    private static let widthChoices = [50, 75, 100]

    var body: some View {
        // A grouped Form is the native macOS Settings composition: titled sections with
        // consistent insets, labels aligned down a column, and controls to their
        // trailing edge. No "Settings" heading — the sidebar it lives in is the label.
        // The sub-views below are Sections, not GroupBoxes; the Form owns the spacing.
        Form {
            general
            terminal
            shell
            panel
            keyboard
            api
            advanced
            about
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PanelChrome.contentBackground(style: windowController.chromeStyle))
        .preferredColorScheme(PanelChrome.colorScheme(style: windowController.chromeStyle))
    }

    // MARK: - General

    private var general: some View {
        Section("General") {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) {
                    do {
                        if launchAtLogin {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Toggle("Confirm before quitting", isOn: $confirmOnQuit)
            Toggle("Restore tabs on launch", isOn: $restoreTabsOnLaunch)
            Toggle("Disable animation", isOn: $disableAnimation)
            Toggle("Check for updates automatically", isOn: Binding(
                get: { SparkleUpdater.shared.automaticallyChecksForUpdates },
                set: { SparkleUpdater.shared.automaticallyChecksForUpdates = $0 }
            ))
        }
    }

    // MARK: - Terminal

    private var terminal: some View {
        Section {
            Picker("Font", selection: $fontFamily) {
                Text("Ghostty default").tag("")
                Divider()
                ForEach(TerminalAppearanceSettings.monospacedFontFamilies, id: \.self) { family in
                    Text(family).tag(family)
                }
            }
            .onChange(of: fontFamily) {
                apply(.fontFamily, fontFamily.isEmpty ? nil : fontFamily)
            }

            segmentedRow("Cursor", selection: $cursorStyle,
                         TerminalAppearanceSettings.cursorStyles.map { ($0.capitalized, $0) })
                .onChange(of: cursorStyle) { apply(.cursorStyle, cursorStyle) }

            segmentedRow("Blur", selection: $blurRadius,
                         Self.blurChoices.map { ($0.label, $0.value) })
                .onChange(of: blurRadius) {
                    apply(.backgroundBlurRadius, blurRadius == 0 ? nil : String(blurRadius))
                }

            // The palette button sets one theme. Only a pair needs this.
            Toggle("Separate light and dark themes", isOn: $followsAppearance)
                .onChange(of: followsAppearance) { applyThemeSelection() }

            if followsAppearance {
                Picker("Light", selection: $lightTheme) {
                    ForEach(themeCatalog.themeNames, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: lightTheme) { applyThemeSelection() }

                Picker("Dark", selection: $darkTheme) {
                    ForEach(themeCatalog.themeNames, id: \.self) { Text($0).tag($0) }
                }
                .onChange(of: darkTheme) { applyThemeSelection() }
            }
        } header: {
            Text("Terminal")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if !followsAppearance {
                    Text("Pick the single theme from the palette button on the tab bar.")
                }
                Text("Written to \(ManagedConfig.overridesPath). Your own Ghostty config is included ahead of it and never modified.")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .task {
            await themeCatalog.load()
            if let selection = GhosttyThemeCatalog.currentSelection() {
                followsAppearance = selection.followsSystemAppearance
                lightTheme = selection.lightTheme
                darkTheme = selection.darkTheme
            }
        }
    }

    // MARK: - Shell

    private var shell: some View {
        Section {
            Picker("Shell", selection: Binding(
                get: {
                    if isCustomShell { return "__custom__" }
                    let current = shellPath.isEmpty ? "auto" : shellPath
                    if current == "auto" { return "auto" }
                    return availableShells.contains(current) ? current : "__custom__"
                },
                set: { newValue in
                    customShellProblem = nil
                    switch newValue {
                    case "__custom__":
                        isCustomShell = true
                        customShellPath = shellPath
                    case "auto":
                        isCustomShell = false
                        shellPath = ""
                    default:
                        isCustomShell = false
                        shellPath = newValue
                    }
                }
            )) {
                Text("Auto ($SHELL)").tag("auto")
                ForEach(availableShells, id: \.self) { Text($0).tag($0) }
                Divider()
                Text("Custom…").tag("__custom__")
            }

            if isCustomShell {
                // No Test button: the path is checked when the field is committed,
                // which is the only moment the answer could have changed.
                TextField("Path to shell or command", text: Binding(
                    get: { customShellPath },
                    set: { customShellPath = $0; customShellProblem = nil }
                ))
                .focused($shellFieldFocused)
                .onSubmit { testAndApplyShell() }
                .onChange(of: shellFieldFocused) {
                    if !shellFieldFocused && !customShellPath.isEmpty { testAndApplyShell() }
                }

                if let customShellProblem {
                    Label(customShellProblem, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        } header: {
            Text("Shell")
        } footer: {
            Text("Changes apply to new tabs only.")
        }
        .onAppear {
            let current = shellPath
            if !current.isEmpty && current != "auto" && !availableShells.contains(current) {
                isCustomShell = true
                customShellPath = current
            }
        }
    }

    // MARK: - Panel

    private var panel: some View {
        Section {
            segmentedRow("Chrome", selection: Binding(
                get: { windowController.chromeStyle },
                set: { windowController.setChromeStyle($0) }
            ), PanelChromeStyle.allCases.map { ($0.displayName, $0) })

            segmentedRow("Width", selection: Binding(
                get: { Self.widthChoices.min(by: {
                    abs($0 - windowController.widthPercent) < abs($1 - windowController.widthPercent)
                }) ?? 100 },
                set: { windowController.setWidthPercent($0) }
            ), Self.widthChoices.map { ("\($0)%", $0) })

            Picker("Screen", selection: Binding(
                get: { windowController.displayID },
                set: { windowController.setDisplayID($0) }
            )) {
                Text("Auto (follow cursor)").tag(0 as Int)
                ForEach(NSScreen.screens, id: \.self) { screen in
                    Text(screen.localizedName).tag(screenID(for: screen))
                }
            }
        } header: {
            Text("Panel")
        } footer: {
            Text("Height is set by dragging the handle on the panel's bottom edge.")
        }
    }

    // MARK: - Keyboard

    private var keyboard: some View {
        Section {
            KeyboardShortcuts.Recorder("Toggle Terminal", name: .toggleTerminal)
            KeyboardShortcuts.Recorder("Next Tab", name: .nextTab)
            KeyboardShortcuts.Recorder("Previous Tab", name: .previousTab)
        } header: {
            Text("Keyboard")
        } footer: {
            Text("Ctrl+Tab and ⌘1-9 are always available.")
        }
    }

    // MARK: - API

    private var api: some View {
        Section {
            segmentedRow("Socket", selection: $apiAccess,
                         [("Enabled", "enabled"), ("Ask first", "ask"), ("Disabled", "disabled")])

            segmentedRow("MCP", selection: $mcpAccess,
                         [("Enabled", "enabled"), ("Ask first", "ask"), ("Disabled", "disabled")])
        } header: {
            Text("API")
        } footer: {
            Text(verbatim: "\(AppIdentity.controlSocketPath) · MCP on port \(MCPHTTPServer.defaultPort), takes effect after restart.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Advanced

    private var advanced: some View {
        Section {
            // Left-aligned, and every button as wide as the widest so they form a tidy
            // column — not stretched full width, which centres the label and looks off,
            // and not each at its own width, which reads as ragged. The width is measured
            // from the longest label (see advancedButton / ButtonWidthKey) rather than
            // guessed, so it stays right if the text changes.
            VStack(alignment: .leading, spacing: 8) {
                advancedButton("Open Config") { GhosttyApp.shared.openConfig() }
                advancedButton("Reload Config") { GhosttyApp.shared.reloadConfig() }
                advancedButton("Check for Updates…") { SparkleUpdater.shared.checkForUpdates() }
                    .disabled(!SparkleUpdater.shared.canCheckForUpdates)
                advancedButton("Quit \(AppIdentity.displayName)",
                               role: .destructive, systemImage: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .onPreferenceChange(ButtonWidthKey.self) { advancedButtonWidth = $0 }
        } header: {
            Text("Advanced")
        } footer: {
            Text("Command line tool, Finder services and the shell colour check are in Help.")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A button in the Advanced column, sized to the widest sibling. Each measures its
    /// own label's natural width through a hidden copy and publishes it up ButtonWidthKey;
    /// the section takes the maximum and hands it back as `advancedButtonWidth`, which
    /// every button then adopts. Measuring a hidden `.fixedSize()` copy rather than the
    /// framed label keeps the constraint from feeding back into the measurement.
    private func advancedButton(_ title: String,
                                role: ButtonRole? = nil,
                                systemImage: String? = nil,
                                action: @escaping () -> Void) -> some View {
        Button(role: role, action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
                Spacer(minLength: 0)
            }
            .frame(width: advancedButtonWidth > 0 ? advancedButtonWidth : nil, alignment: .leading)
            .background(
                HStack(spacing: 6) {
                    if let systemImage { Image(systemName: systemImage) }
                    Text(title)
                }
                .fixedSize()
                .hidden()
                .background(GeometryReader { geo in
                    Color.clear.preference(key: ButtonWidthKey.self, value: geo.size.width)
                })
            )
        }
    }

    private var about: some View {
        Section {
            DisclosureGroup("Acknowledgements") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("GhosttyKit").font(.caption.bold())
                    Text("Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                    Text("MIT License. Ghostty and its contributors, used under the terms of the MIT License.")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                    Divider()
                    Text("KeyboardShortcuts").font(.caption.bold())
                    Text("Copyright (c) Sindre Sorhus — MIT License")
                        .font(.system(size: 10)).foregroundColor(.secondary)
                }
            }
        } footer: {
            Text("\(AppIdentity.displayName) v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
        }
    }

    // MARK: - Row builders

    /// A titled segmented control that fills the row width, its segments stretched
    /// equally. Label above, control below at full width — so Cursor, Blur, Chrome,
    /// Width and the rest all reach the same right edge instead of each ending wherever
    /// its options happen to. Backed by FillingSegmentedControl because the SwiftUI
    /// segmented style cannot be made to fill.
    private func segmentedRow<Tag: Hashable>(_ title: String,
                                             selection: Binding<Tag>,
                                             _ options: [(label: String, tag: Tag)]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            FillingSegmentedControl(options: options, selection: selection)
                .frame(maxWidth: .infinity)
                .frame(height: 22)
        }
    }

    // MARK: - Actions

    /// Write a setting and reload, so the change is visible immediately rather than at
    /// the next launch.
    private func apply(_ setting: TerminalSetting, _ value: String?) {
        GhosttyApp.shared.apply(setting, to: value)
    }

    private func applyThemeSelection() {
        let selection: ThemeSelection = followsAppearance
            ? .pair(light: lightTheme, dark: darkTheme)
            : .single(lightTheme)
        windowController.applyGhosttyTheme(selection)
    }

    private func testAndApplyShell() {
        let path = customShellPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let fm = FileManager.default
        if path.isEmpty {
            customShellProblem = "Enter a path."
        } else if !fm.fileExists(atPath: path) {
            customShellProblem = "File not found."
        } else if !fm.isExecutableFile(atPath: path) {
            customShellProblem = "Not executable."
        } else {
            customShellProblem = nil
            shellPath = path
        }
    }

    private func screenID(for screen: NSScreen) -> Int {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0
    }
}
