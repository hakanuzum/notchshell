import SwiftUI
import ServiceManagement
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleTerminal = Self("toggleTerminal", default: .init(.space, modifiers: .option))
    static let nextTab = Self("nextTab", default: .init(.rightBracket, modifiers: [.command, .shift]))
    static let previousTab = Self("previousTab", default: .init(.leftBracket, modifiers: [.command, .shift]))
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

            Picker("Cursor", selection: $cursorStyle) {
                ForEach(TerminalAppearanceSettings.cursorStyles, id: \.self) { style in
                    Text(style.capitalized).tag(style)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: cursorStyle) { apply(.cursorStyle, cursorStyle) }

            Picker("Blur", selection: $blurRadius) {
                ForEach(Self.blurChoices, id: \.value) { choice in
                    Text(choice.label).tag(choice.value)
                }
            }
            .pickerStyle(.segmented)
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
            Picker("Chrome", selection: Binding(
                get: { windowController.chromeStyle },
                set: { windowController.setChromeStyle($0) }
            )) {
                ForEach(PanelChromeStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)

            Picker("Width", selection: Binding(
                get: { Self.widthChoices.min(by: {
                    abs($0 - windowController.widthPercent) < abs($1 - windowController.widthPercent)
                }) ?? 100 },
                set: { windowController.setWidthPercent($0) }
            )) {
                ForEach(Self.widthChoices, id: \.self) { Text("\($0)%").tag($0) }
            }
            .pickerStyle(.segmented)

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
            Picker("Socket", selection: $apiAccess) {
                Text("Enabled").tag("enabled")
                Text("Ask first").tag("ask")
                Text("Disabled").tag("disabled")
            }
            .pickerStyle(.segmented)

            Picker("MCP", selection: $mcpAccess) {
                Text("Enabled").tag("enabled")
                Text("Ask first").tag("ask")
                Text("Disabled").tag("disabled")
            }
            .pickerStyle(.segmented)
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
            Button("Open Config") { GhosttyApp.shared.openConfig() }
            Button("Reload Config") { GhosttyApp.shared.reloadConfig() }
            Button("Check for Updates…") { SparkleUpdater.shared.checkForUpdates() }
                .disabled(!SparkleUpdater.shared.canCheckForUpdates)
            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit \(AppIdentity.displayName)", systemImage: "power")
            }
        } header: {
            Text("Advanced")
        } footer: {
            Text("Command line tool, Finder services and the shell colour check are in Help.")
                .fixedSize(horizontal: false, vertical: true)
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
