import SwiftUI
import ServiceManagement
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let toggleTerminal = Self("toggleTerminal", default: .init(.space, modifiers: .option))
    static let nextTab = Self("nextTab", default: .init(.rightBracket, modifiers: [.command, .shift]))
    static let previousTab = Self("previousTab", default: .init(.leftBracket, modifiers: [.command, .shift]))
}

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
    @State private var shellTestResult: ShellTestResult?
    @StateObject private var themeCatalog = ThemeCatalogStore()
    /// Seeded from the stored selection. `currentThemeName()` returns the raw config
    /// value, which may be a `light:A,dark:B` pair, so it is parsed rather than used
    /// as a picker tag directly.
    @State private var followsAppearance: Bool =
        GhosttyThemeCatalog.currentSelection()?.followsSystemAppearance ?? false
    @State private var lightTheme: String =
        GhosttyThemeCatalog.currentSelection()?.lightTheme ?? "Catppuccin Latte"
    @State private var darkTheme: String =
        GhosttyThemeCatalog.currentSelection()?.darkTheme ?? "Catppuccin Mocha"
    @State private var themeFilter: String = ""
    @State private var fontFamily: String = TerminalAppearanceSettings.string(.fontFamily) ?? ""
    @State private var fontSize: Double = TerminalAppearanceSettings.double(.fontSize) ?? 13
    @State private var backgroundOpacity: Double = TerminalAppearanceSettings.double(.backgroundOpacity) ?? 1
    @State private var blurRadius: Double = TerminalAppearanceSettings.double(.backgroundBlurRadius) ?? 0
    @State private var cursorStyle: String = TerminalAppearanceSettings.string(.cursorStyle) ?? "block"
    @State private var themeApplyMessage: String?
    @FocusState private var shellFieldFocused: Bool

    private enum ShellTestResult {
        case ok, notFound, notExecutable
    }

    private static let knownShells = [
        "/bin/zsh",
        "/bin/bash",
        "/bin/sh",
        "/usr/local/bin/fish",
        "/opt/homebrew/bin/fish",
        "/usr/local/bin/zsh",
        "/opt/homebrew/bin/zsh",
        "/usr/local/bin/bash",
        "/opt/homebrew/bin/bash",
    ]

    private var availableShells: [String] {
        Self.knownShells.filter { FileManager.default.isExecutableFile(atPath: $0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings")
                    .font(.title2.bold())

                GroupBox("General") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
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
                            Spacer()
                        }
                        HStack {
                            Toggle("Confirm before quitting", isOn: $confirmOnQuit)
                            Spacer()
                        }
                        HStack {
                            Toggle("Restore tabs on launch", isOn: $restoreTabsOnLaunch)
                            Spacer()
                        }
                        HStack {
                            Toggle("Disable animation", isOn: $disableAnimation)
                            Spacer()
                        }
                    }
                    .padding(8)
                }

                GroupBox("Shell") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Picker("Shell path:", selection: Binding(
                                get: {
                                    if isCustomShell { return "__custom__" }
                                    let current = shellPath.isEmpty ? "auto" : shellPath
                                    if current == "auto" { return "auto" }
                                    if availableShells.contains(current) { return current }
                                    return "__custom__"
                                },
                                set: { newValue in
                                    if newValue == "__custom__" {
                                        isCustomShell = true
                                        customShellPath = shellPath
                                    } else if newValue == "auto" {
                                        isCustomShell = false
                                        shellPath = ""
                                    } else {
                                        isCustomShell = false
                                        shellPath = newValue
                                    }
                                }
                            )) {
                                Text("Auto ($SHELL)").tag("auto")
                                ForEach(availableShells, id: \.self) { path in
                                    Text(path).tag(path)
                                }
                                Divider()
                                Text("Custom...").tag("__custom__")
                            }
                            Spacer()
                        }

                        if isCustomShell {
                            HStack {
                                TextField("Path to shell or command", text: Binding(
                                    get: { customShellPath },
                                    set: { customShellPath = $0; shellTestResult = nil }
                                ))
                                    .textFieldStyle(.roundedBorder)
                                    .focused($shellFieldFocused)
                                    .onSubmit { testAndApplyShell() }
                                    .onChange(of: shellFieldFocused) {
                                        if !shellFieldFocused && !customShellPath.isEmpty {
                                            testAndApplyShell()
                                        }
                                    }
                                Button("Test") { testAndApplyShell() }
                                    .buttonStyle(.bordered)
                            }

                            if let result = shellTestResult {
                                HStack(spacing: 4) {
                                    switch result {
                                    case .ok:
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                        Text("Valid executable — applied.")
                                    case .notFound:
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                        Text("File not found.")
                                    case .notExecutable:
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.red)
                                        Text("Not executable.")
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }

                        Text("Changes apply to new tabs only.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }
                .onAppear {
                    let current = shellPath
                    if !current.isEmpty && current != "auto" && !availableShells.contains(current) {
                        isCustomShell = true
                        customShellPath = current
                    }
                }

                GroupBox("API") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Picker("Socket API (\(AppIdentity.controlSocketPath)):", selection: $apiAccess) {
                                Text("Enabled").tag("enabled")
                                Text("Ask on first request").tag("ask")
                                Text("Disabled").tag("disabled")
                            }
                            .pickerStyle(.menu)
                            Spacer()
                        }
                        HStack {
                            Picker("MCP server (HTTP, port \(String(MCPHTTPServer.defaultPort))):", selection: $mcpAccess) {
                                Text("Enabled").tag("enabled")
                                Text("Ask on first request").tag("ask")
                                Text("Disabled").tag("disabled")
                            }
                            .pickerStyle(.menu)
                            Spacer()
                        }
                        Text("MCP server changes take effect after restart.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                GroupBox("Panel Chrome") {
                    VStack(alignment: .leading, spacing: 8) {
                        Picker("Chrome:", selection: Binding(
                            get: { windowController.chromeStyle },
                            set: { windowController.setChromeStyle($0) }
                        )) {
                            ForEach(PanelChromeStyle.allCases) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        Text("Light = Unclutter-style bottom tabs. Dark = classic top tab bar.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                GroupBox("Terminal Appearance") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Written to \(ManagedConfig.overridesPath). Your own Ghostty config is included ahead of it and never modified.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
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
                        }

                        HStack {
                            Text("Size:").frame(width: 60, alignment: .leading)
                            Slider(value: $fontSize, in: 8...32, step: 1) { editing in
                                if !editing { apply(.fontSize, String(Int(fontSize))) }
                            }
                            Text("\(Int(fontSize)) pt").font(.caption).monospacedDigit().frame(width: 46)
                        }

                        HStack {
                            Text("Opacity:").frame(width: 60, alignment: .leading)
                            Slider(value: $backgroundOpacity, in: 0.3...1, step: 0.01) { editing in
                                if !editing { apply(.backgroundOpacity, String(format: "%.2f", backgroundOpacity)) }
                            }
                            Text("\(Int(backgroundOpacity * 100))%").font(.caption).monospacedDigit().frame(width: 46)
                        }

                        HStack {
                            Text("Blur:").frame(width: 60, alignment: .leading)
                            Slider(value: $blurRadius, in: 0...50, step: 1) { editing in
                                if !editing {
                                    apply(.backgroundBlurRadius, blurRadius == 0 ? nil : String(Int(blurRadius)))
                                }
                            }
                            Text(blurRadius == 0 ? "off" : "\(Int(blurRadius))")
                                .font(.caption).monospacedDigit().frame(width: 46)
                        }

                        Picker("Cursor:", selection: $cursorStyle) {
                            ForEach(TerminalAppearanceSettings.cursorStyles, id: \.self) { style in
                                Text(style.capitalized).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: cursorStyle) { apply(.cursorStyle, cursorStyle) }
                    }
                    .padding(8)
                }

                GroupBox("Terminal Theme") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bundled Ghostty themes; drop your own in ~/.config/ghostty/themes to override. Palette button on the tab bar is the fast path.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Filter themes…", text: $themeFilter)
                            .textFieldStyle(.roundedBorder)

                        let filtered = themeCatalog.themeNames.filter {
                            themeFilter.isEmpty || $0.localizedCaseInsensitiveContains(themeFilter)
                        }

                        Toggle("Follow system appearance", isOn: $followsAppearance)
                            .help("Use one theme in Light mode and another in Dark mode.")

                        Picker(followsAppearance ? "Light theme" : "Theme", selection: $lightTheme) {
                            ForEach(filtered, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                        .pickerStyle(.menu)

                        if followsAppearance {
                            Picker("Dark theme", selection: $darkTheme) {
                                ForEach(filtered, id: \.self) { name in
                                    Text(name).tag(name)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        HStack(spacing: 10) {
                            Button("Apply Theme") {
                                let selection: ThemeSelection = followsAppearance
                                    ? .pair(light: lightTheme, dark: darkTheme)
                                    : .single(lightTheme)
                                let ok = windowController.applyGhosttyTheme(selection)
                                themeApplyMessage = ok
                                    ? "Applied “\(selection.configValue)”."
                                    : "Theme not found."
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Reload Themes") {
                                Task { await themeCatalog.reload() }
                            }
                            .buttonStyle(.bordered)
                            .disabled(themeCatalog.isLoading)

                            Spacer()
                        }

                        if let themeApplyMessage {
                            Text(themeApplyMessage)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text("\(themeCatalog.themeNames.count) themes · also available from the palette button on the tab bar")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        HStack(spacing: 12) {
                            Button("Open Config") {
                                GhosttyApp.shared.openConfig()
                            }
                            .buttonStyle(.bordered)

                            Button("Reload Config") {
                                GhosttyApp.shared.reloadConfig()
                            }
                            .buttonStyle(.bordered)

                            Spacer()
                        }
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

                GroupBox("Keyboard") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            KeyboardShortcuts.Recorder("Toggle Terminal:", name: .toggleTerminal)
                            Spacer()
                        }
                        HStack {
                            KeyboardShortcuts.Recorder("Next Tab:", name: .nextTab)
                            Spacer()
                        }
                        HStack {
                            KeyboardShortcuts.Recorder("Previous Tab:", name: .previousTab)
                            Spacer()
                        }
                        Text("Ctrl+Tab and ⌘1-9 are always available.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }

                GroupBox("Size") {
                    VStack(spacing: 8) {
                        HStack {
                            Text("Width:")
                                .frame(width: 50, alignment: .leading)
                            Slider(
                                value: Binding(
                                    get: { Double(windowController.widthPercent) },
                                    set: { windowController.setWidthPercent(Int($0)) }
                                ),
                                in: 30...100,
                                step: 5
                            )
                            Text("\(windowController.widthPercent)%")
                                .monospacedDigit()
                                .frame(width: 36)
                        }

                        HStack {
                            Text("Height:")
                                .frame(width: 50, alignment: .leading)
                            Slider(
                                value: Binding(
                                    get: { Double(windowController.heightPercent) },
                                    set: { windowController.setHeightPercent(Int($0)) }
                                ),
                                in: 20...100,
                                step: 5
                            )
                            Text("\(windowController.heightPercent)%")
                                .monospacedDigit()
                                .frame(width: 36)
                        }
                    }
                    .padding(8)
                }

                GroupBox("Display") {
                    HStack {
                        Picker("Screen:", selection: Binding(
                            get: { windowController.displayID },
                            set: { windowController.setDisplayID($0) }
                        )) {
                            Text("Auto (follow cursor)").tag(0 as Int)
                            ForEach(NSScreen.screens, id: \.self) { screen in
                                Text(screen.localizedName)
                                    .tag(screenID(for: screen))
                            }
                        }
                        Spacer()
                    }
                    .padding(8)
                }
                GroupBox("Updates") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle("Check for updates automatically", isOn: Binding(
                                get: { SparkleUpdater.shared.automaticallyChecksForUpdates },
                                set: { SparkleUpdater.shared.automaticallyChecksForUpdates = $0 }
                            ))
                            Spacer()
                        }
                        HStack {
                            Button("Check for Updates…") {
                                SparkleUpdater.shared.checkForUpdates()
                            }
                            .disabled(!SparkleUpdater.shared.canCheckForUpdates)
                            Spacer()
                        }
                    }
                    .padding(8)
                }

                Divider()
                    .padding(.top, 8)

                Button(action: {
                    NSApplication.shared.terminate(nil)
                }) {
                    Label("Quit \(AppIdentity.displayName)", systemImage: "power")
                }
                .buttonStyle(.plain)
                .foregroundColor(.red)

                Divider()
                    .padding(.top, 8)

                Text("\(AppIdentity.displayName) v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)

                DisclosureGroup("Acknowledgements") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("GhosttyKit")
                            .font(.caption.bold())
                        Text("Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("MIT License — Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files, to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, subject to the above copyright notice and this permission notice being included in all copies or substantial portions of the Software.")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)

                        Divider()

                        Text("KeyboardShortcuts")
                            .font(.caption.bold())
                        Text("Copyright (c) Sindre Sorhus")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("MIT License")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                }
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PanelChrome.contentBackground(style: windowController.chromeStyle))
        .preferredColorScheme(PanelChrome.colorScheme(style: windowController.chromeStyle))
    }

    /// Write a setting and reload, so the change is visible immediately rather than
    /// at the next launch.
    private func apply(_ setting: TerminalSetting, _ value: String?) {
        TerminalAppearanceSettings.set(setting, to: value)
        GhosttyApp.shared.reloadConfig()
    }

    private func testAndApplyShell() {
        let path = customShellPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { shellTestResult = .notFound; return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            shellTestResult = .notFound
        } else if !fm.isExecutableFile(atPath: path) {
            shellTestResult = .notExecutable
        } else {
            shellTestResult = .ok
            shellPath = path
        }
    }

    private func screenID(for screen: NSScreen) -> Int {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0
    }
}
