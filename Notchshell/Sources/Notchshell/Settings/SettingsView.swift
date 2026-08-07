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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings").font(.title2.bold())

                general
                terminal
                shell
                panel
                keyboard
                api
                advanced

                Divider().padding(.top, 8)

                Text("\(AppIdentity.displayName) v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                acknowledgements
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PanelChrome.contentBackground(style: windowController.chromeStyle))
        .preferredColorScheme(PanelChrome.colorScheme(style: windowController.chromeStyle))
    }

    // MARK: - General

    private var general: some View {
        GroupBox("General") {
            VStack(alignment: .leading, spacing: 8) {
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    // MARK: - Terminal

    private var terminal: some View {
        GroupBox("Terminal") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Font:", selection: $fontFamily) {
                    Text("Ghostty default").tag("")
                    Divider()
                    ForEach(TerminalAppearanceSettings.monospacedFontFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                .onChange(of: fontFamily) {
                    apply(.fontFamily, fontFamily.isEmpty ? nil : fontFamily)
                }

                Picker("Cursor:", selection: $cursorStyle) {
                    ForEach(TerminalAppearanceSettings.cursorStyles, id: \.self) { style in
                        Text(style.capitalized).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: cursorStyle) { apply(.cursorStyle, cursorStyle) }

                Picker("Blur:", selection: $blurRadius) {
                    ForEach(Self.blurChoices, id: \.value) { choice in
                        Text(choice.label).tag(choice.value)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: blurRadius) {
                    apply(.backgroundBlurRadius, blurRadius == 0 ? nil : String(blurRadius))
                }

                Divider()

                // The palette button sets one theme. Only a pair needs this.
                Toggle("Separate light and dark themes", isOn: $followsAppearance)
                    .onChange(of: followsAppearance) { applyThemeSelection() }

                if followsAppearance {
                    Picker("Light:", selection: $lightTheme) {
                        ForEach(themeCatalog.themeNames, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: lightTheme) { applyThemeSelection() }

                    Picker("Dark:", selection: $darkTheme) {
                        ForEach(themeCatalog.themeNames, id: \.self) { Text($0).tag($0) }
                    }
                    .onChange(of: darkTheme) { applyThemeSelection() }
                } else {
                    Text("Pick the single theme from the palette button on the tab bar.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("Written to \(ManagedConfig.overridesPath). Your own Ghostty config is included ahead of it and never modified.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
            .task {
                await themeCatalog.load()
                if let selection = GhosttyThemeCatalog.currentSelection() {
                    followsAppearance = selection.followsSystemAppearance
                    lightTheme = selection.lightTheme
                    darkTheme = selection.darkTheme
                }
            }
        }
    }

    // MARK: - Shell

    private var shell: some View {
        GroupBox("Shell") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Shell:", selection: Binding(
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
                    .textFieldStyle(.roundedBorder)
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

                Text("Changes apply to new tabs only.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
            .onAppear {
                let current = shellPath
                if !current.isEmpty && current != "auto" && !availableShells.contains(current) {
                    isCustomShell = true
                    customShellPath = current
                }
            }
        }
    }

    // MARK: - Panel

    private var panel: some View {
        GroupBox("Panel") {
            VStack(alignment: .leading, spacing: 10) {
                Picker("Chrome:", selection: Binding(
                    get: { windowController.chromeStyle },
                    set: { windowController.setChromeStyle($0) }
                )) {
                    ForEach(PanelChromeStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Width:", selection: Binding(
                    get: { Self.widthChoices.min(by: {
                        abs($0 - windowController.widthPercent) < abs($1 - windowController.widthPercent)
                    }) ?? 100 },
                    set: { windowController.setWidthPercent($0) }
                )) {
                    ForEach(Self.widthChoices, id: \.self) { Text("\($0)%").tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Screen:", selection: Binding(
                    get: { windowController.displayID },
                    set: { windowController.setDisplayID($0) }
                )) {
                    Text("Auto (follow cursor)").tag(0 as Int)
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        Text(screen.localizedName).tag(screenID(for: screen))
                    }
                }

                Text("Height is set by dragging the handle on the panel's bottom edge.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(8)
        }
    }

    // MARK: - Keyboard

    private var keyboard: some View {
        GroupBox("Keyboard") {
            VStack(alignment: .leading, spacing: 8) {
                KeyboardShortcuts.Recorder("Toggle Terminal:", name: .toggleTerminal)
                KeyboardShortcuts.Recorder("Next Tab:", name: .nextTab)
                KeyboardShortcuts.Recorder("Previous Tab:", name: .previousTab)
                Text("Ctrl+Tab and ⌘1-9 are always available.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    // MARK: - API

    private var api: some View {
        GroupBox("API") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Socket:", selection: $apiAccess) {
                    Text("Enabled").tag("enabled")
                    Text("Ask first").tag("ask")
                    Text("Disabled").tag("disabled")
                }
                .pickerStyle(.segmented)

                Picker("MCP:", selection: $mcpAccess) {
                    Text("Enabled").tag("enabled")
                    Text("Ask first").tag("ask")
                    Text("Disabled").tag("disabled")
                }
                .pickerStyle(.segmented)

                Text(verbatim: "\(AppIdentity.controlSocketPath) · MCP on port \(MCPHTTPServer.defaultPort), takes effect after restart.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(8)
        }
    }

    // MARK: - Advanced

    private var advanced: some View {
        GroupBox("Advanced") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button("Open Config") { GhosttyApp.shared.openConfig() }
                    Button("Reload Config") { GhosttyApp.shared.reloadConfig() }
                    Button("Check for Updates…") { SparkleUpdater.shared.checkForUpdates() }
                        .disabled(!SparkleUpdater.shared.canCheckForUpdates)
                    Spacer()
                }
                .buttonStyle(.bordered)

                Text("Command line tool, Finder services and the shell colour check are in Help.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Label("Quit \(AppIdentity.displayName)", systemImage: "power")
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
        }
    }

    private var acknowledgements: some View {
        DisclosureGroup("Acknowledgements") {
            VStack(alignment: .leading, spacing: 8) {
                Text("GhosttyKit").font(.caption.bold())
                Text("Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                Text("MIT License — Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files, to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, subject to the above copyright notice and this permission notice being included in all copies or substantial portions of the Software.")
                    .font(.system(size: 10)).foregroundColor(.secondary)

                Divider()

                Text("KeyboardShortcuts").font(.caption.bold())
                Text("Copyright (c) Sindre Sorhus")
                    .font(.system(size: 10)).foregroundColor(.secondary)
                Text("MIT License")
                    .font(.system(size: 10)).foregroundColor(.secondary)
            }
            .padding(8)
        }
        .font(.system(size: 11))
        .foregroundColor(.secondary)
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
