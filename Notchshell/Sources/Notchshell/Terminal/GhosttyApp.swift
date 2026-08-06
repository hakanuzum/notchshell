import AppKit
import GhosttyKit
import os.log

private let log = OSLog(subsystem: AppIdentity.logSubsystem, category: "GhosttyApp")

/// Singleton managing the ghostty_app_t lifecycle. One per process, shared across all surfaces/tabs.
/// All methods must be called on the main thread.
final class GhosttyApp: @unchecked Sendable {
    static let shared = GhosttyApp()

    private(set) var app: ghostty_app_t?
    private(set) var config: ghostty_config_t?
    private var initialized = false
    /// Prevents wakeup_cb from flooding the main dispatch queue.
    /// Set to true when a tick is already enqueued, cleared after tick runs.
    private var tickPending = false
    /// Kept alive for the lifetime of the app; releasing it stops appearance updates.
    private var appearanceObservation: NSKeyValueObservation?

    private init() {}

    // MARK: - Initialization

    /// Set to true to skip Ghostty initialization (e.g. in unit tests).
    static var disableForTesting = false

    /// Detect if running inside a test host (xctest or swiftpm-testing-helper).
    private static var isTestEnvironment: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || ProcessInfo.processInfo.processName.contains("xctest")
        || ProcessInfo.processInfo.processName.contains("swiftpm-testing-helper")
    }

    func initialize() {
        guard !initialized else { return }
        initialized = true

        if Self.disableForTesting || (Self.isTestEnvironment && getenv(AppIdentity.testGhosttyEnvVar) == nil) {
            os_log(.info, log: log,
                   "Skipping GhosttyApp init (test environment; set %{public}s=1 to override)",
                   AppIdentity.testGhosttyEnvVar)
            return
        }

        // Unset NO_COLOR so TUI apps render properly
        if getenv("NO_COLOR") != nil { unsetenv("NO_COLOR") }

        useBundledResources()

        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        guard result == GHOSTTY_SUCCESS else {
            os_log(.error, log: log, "ghostty_init failed with code %d", result)
            return
        }

        guard let primaryConfig = ghostty_config_new() else {
            os_log(.error, log: log, "ghostty_config_new returned nil")
            return
        }
        ManagedConfig.load(into: primaryConfig)
        ghostty_config_finalize(primaryConfig)

        let diagnosticCount = ghostty_config_diagnostics_count(primaryConfig)
        if diagnosticCount > 0 {
            for i in 0..<diagnosticCount {
                let diag = ghostty_config_get_diagnostic(primaryConfig, i)
                if let msg = diag.message {
                    os_log(.info, log: log, "ghostty config diagnostic: %{public}s", String(cString: msg))
                }
            }
        }

        var runtimeConfig = ghostty_runtime_config_s()
        runtimeConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtimeConfig.supports_selection_clipboard = false

        runtimeConfig.wakeup_cb = { _ in
            let app = GhosttyApp.shared
            // Coalesce: only enqueue one tick at a time
            guard !app.tickPending else { return }
            app.tickPending = true
            DispatchQueue.main.async {
                app.tickPending = false
                app.tick()
            }
        }

        runtimeConfig.action_cb = { _, target, action in
            return GhosttyApp.shared.handleAction(target: target, action: action)
        }

        runtimeConfig.read_clipboard_cb = { _, _, state in
            let contents = NSPasteboard.general.string(forType: .string) ?? ""
            GhosttyApp.shared.completeClipboardRead(contents: contents, state: state)
            return true
        }

        runtimeConfig.confirm_read_clipboard_cb = { _, contents, state, _ in
            // Ghostty asks for confirmation when a paste looks unsafe (multi-line
            // text, control sequences). Auto-confirm — but the completion MUST pass
            // confirmed=true, otherwise Ghostty re-issues this same request and we
            // recurse until the stack overflows (SIGSEGV).
            let text = contents.map { String(cString: $0) }
                ?? NSPasteboard.general.string(forType: .string) ?? ""
            GhosttyApp.shared.completeClipboardRead(contents: text, state: state, confirmed: true)
        }

        runtimeConfig.write_clipboard_cb = {
            (userdata: UnsafeMutableRawPointer?,
             location: ghostty_clipboard_e,
             content: UnsafePointer<ghostty_clipboard_content_s>?,
             count: Int,
             confirm: Bool) in
            guard let content, count > 0 else { return }
            // Find the text/plain MIME content
            for i in 0..<count {
                let item = content[i]
                guard let mime = item.mime, let data = item.data else { continue }
                let mimeStr = String(cString: mime)
                if mimeStr == "text/plain" || mimeStr.hasPrefix("text/") {
                    let str = String(cString: data)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(str, forType: .string)
                    return
                }
            }
            // Fallback: use first content item
            if let data = content[0].data {
                let str = String(cString: data)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(str, forType: .string)
            }
        }

        runtimeConfig.close_surface_cb = { userdata, _ in
            // Surface close is handled via the action callback (SHOW_CHILD_EXITED)
        }

        if let created = ghostty_app_new(&runtimeConfig, primaryConfig) {
            self.app = created
            self.config = primaryConfig
            os_log(.info, log: log, "GhosttyApp initialized successfully")
        } else {
            os_log(.error, log: log, "ghostty_app_new failed, retrying with default config")
            // Retry with minimal config
            ghostty_config_free(primaryConfig)
            guard let fallbackConfig = ghostty_config_new() else { return }
            ghostty_config_finalize(fallbackConfig)
            if let created = ghostty_app_new(&runtimeConfig, fallbackConfig) {
                self.app = created
                self.config = fallbackConfig
            } else {
                ghostty_config_free(fallbackConfig)
                os_log(.error, log: log, "ghostty_app_new failed even with default config")
            }
        }

        // Track app-level focus
        if let app, let nsApp = NSApp {
            ghostty_app_set_focus(app, nsApp.isActive)
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            if let app = self?.app { ghostty_app_set_focus(app, true) }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            if let app = self?.app { ghostty_app_set_focus(app, false) }
        }

        // Follow the system appearance so a light/dark theme pair switches with it.
        appearanceObservation = NSApp?.observe(\.effectiveAppearance, options: [.new]) { _, _ in
            DispatchQueue.main.async { GhosttyApp.shared.broadcastColorScheme() }
        }
        broadcastColorScheme()
    }

    /// Point Ghostty at the resources this app ships, overriding anything inherited.
    ///
    /// These are *not* treated as user overrides. On a machine with another
    /// Ghostty-based terminal installed, launching from a shell inherits that app's
    /// `GHOSTTY_RESOURCES_DIR` and `TERMINFO`, and an earlier version of this deferred
    /// to them — so the app silently used a competitor's theme catalog and terminfo
    /// database, and would have broken outright once that app was uninstalled. What we
    /// ship is always present, so it always wins.
    ///
    /// User themes are not affected: `GhosttyThemeCatalog.resourceRoots` searches
    /// `~/.config/ghostty/themes` ahead of the bundle.
    private func useBundledResources() {
        guard let resources = GhosttyThemeCatalog.bundledResourcesRoot else {
            // Running from a test host or a bundle built without the copy step.
            os_log(.error, log: log, "No bundled Ghostty resources — themes and terminfo will be missing")
            return
        }
        setenv("GHOSTTY_RESOURCES_DIR", resources, 1)

        // libghostty derives TERMINFO as a sibling of the resources directory, but set
        // it explicitly so an inherited value cannot win.
        let terminfo = (resources as NSString).deletingLastPathComponent + "/terminfo"
        if FileManager.default.fileExists(atPath: terminfo) {
            setenv("TERMINFO", terminfo, 1)
        } else {
            os_log(.error, log: log,
                   "Bundled terminfo missing at %{public}s — TERM=xterm-ghostty will not resolve",
                   terminfo)
        }
        os_log(.info, log: log, "Using bundled resources at %{public}s", resources)
    }

    // MARK: - Tick

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    // MARK: - Clipboard

    /// Registry of active backends for clipboard routing (protected by lock for thread safety)
    private let backendsLock = NSLock()
    private var _activeBackends: [ObjectIdentifier: GhosttyBackend] = [:]

    func registerBackend(_ backend: GhosttyBackend) {
        backendsLock.lock()
        _activeBackends[ObjectIdentifier(backend)] = backend
        backendsLock.unlock()
    }

    func unregisterBackend(_ backend: GhosttyBackend) {
        backendsLock.lock()
        _activeBackends.removeValue(forKey: ObjectIdentifier(backend))
        backendsLock.unlock()
    }

    private var activeBackends: [ObjectIdentifier: GhosttyBackend] {
        backendsLock.lock()
        let copy = _activeBackends
        backendsLock.unlock()
        return copy
    }

    private func completeClipboardRead(
        contents: String,
        state: UnsafeMutableRawPointer?,
        confirmed: Bool = false
    ) {
        // Find the focused surface: check all windows for a GhosttyTerminalView first responder.
        let focusedSurface: ghostty_surface_t? = {
            for window in NSApp.windows {
                if let fr = window.firstResponder as? GhosttyTerminalView,
                   let surface = fr.backend?.surface {
                    return surface
                }
            }
            // Fallback: first registered backend
            return activeBackends.values.first(where: { $0.surface != nil })?.surface
        }()

        guard let surface = focusedSurface else { return }
        contents.withCString { ptr in
            ghostty_surface_complete_clipboard_request(surface, ptr, state, confirmed)
        }
    }

    // MARK: - Action routing

    private func handleAction(target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        // Surface-level actions
        if target.tag == GHOSTTY_TARGET_SURFACE {
            let surfaceHandle = target.target.surface
            guard let surfaceHandle else { return false }
            let userdata = ghostty_surface_userdata(surfaceHandle)
            guard let userdata else { return false }
            let backend = Unmanaged<GhosttyBackend>.fromOpaque(userdata).takeUnretainedValue()
            return backend.handleAction(action)
        }

        // App-level actions
        switch action.tag {
        case GHOSTTY_ACTION_RELOAD_CONFIG:
            reloadConfig()
            return true
        case GHOSTTY_ACTION_RING_BELL:
            return true // Suppress terminal bell
        default:
            return false
        }
    }

    func reloadConfig() {
        guard let app, let oldConfig = config else { return }
        guard let newConfig = ghostty_config_new() else {
            os_log(.error, log: log, "reloadConfig: ghostty_config_new failed")
            return
        }
        ManagedConfig.load(into: newConfig)
        ghostty_config_finalize(newConfig)

        let diagCount = ghostty_config_diagnostics_count(newConfig)
        if diagCount > 0 {
            for i in 0..<diagCount {
                let diag = ghostty_config_get_diagnostic(newConfig, i)
                if let msg = diag.message {
                    os_log(.error, log: log, "config diagnostic: %{public}s", String(cString: msg))
                }
            }
        }

        ghostty_app_update_config(app, newConfig)

        // Update each surface with its own config clone and refresh
        for backend in activeBackends.values {
            guard let surface = backend.surface else { continue }
            if let cloned = ghostty_config_clone(newConfig) {
                ghostty_surface_update_config(surface, cloned)
                ghostty_config_free(cloned)
            }
            ghostty_surface_refresh(surface)
        }

        ghostty_config_free(oldConfig)
        config = newConfig
        os_log(.info, log: log, "Config reloaded (diagnostics: %d, surfaces: %d)", diagCount, activeBackends.count)
    }

    // MARK: - Config management

    /// Config file this app loads. Not the user's Ghostty config — that one is
    /// included from here and is never written to. See `ManagedConfig`.
    var configPath: String { ManagedConfig.rootPath }

    // MARK: - Colour scheme

    /// The system appearance, which is what Ghostty needs in order to pick a side of a
    /// `theme = light:A,dark:B` pair.
    ///
    /// This used to be derived from the active palette's brightness, and
    /// `GhosttyTerminalView` separately pinned every surface to dark. Both were wrong
    /// for the same reason: this value is an *input* telling Ghostty which appearance
    /// is in effect, not a description of the colours we ended up with. Reporting dark
    /// unconditionally also made a light/dark pair impossible — Ghostty would never be
    /// told to switch.
    var systemColorScheme: ghostty_color_scheme_e {
        let appearance = NSApp?.effectiveAppearance ?? NSAppearance.currentDrawing()
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return isDark ? GHOSTTY_COLOR_SCHEME_DARK : GHOSTTY_COLOR_SCHEME_LIGHT
    }

    var systemPrefersDark: Bool { systemColorScheme == GHOSTTY_COLOR_SCHEME_DARK }

    /// Tell every surface which appearance is in effect, then refresh chrome to match
    /// whichever half of a theme pair that selects.
    func broadcastColorScheme() {
        let scheme = systemColorScheme
        if let app { ghostty_app_set_color_scheme(app, scheme) }
        for backend in activeBackends.values {
            guard let surface = backend.surface else { continue }
            ghostty_surface_set_color_scheme(surface, scheme)
            ghostty_surface_refresh(surface)
        }
        refreshChromeColors()
    }

    /// Repaint the app's own chrome from the theme currently in effect.
    ///
    /// The chrome cannot read the resolved colours back from a live surface, and a
    /// finalized config collapses a pair to one side regardless of appearance
    /// (measured: `light:Latte,dark:Mocha` reports Latte's background). So resolve the
    /// pair here and read that theme's file directly.
    func refreshChromeColors() {
        guard let value = ManagedConfig.currentTheme(),
              let selection = ThemeSelection(configValue: value) else { return }
        let name = selection.theme(forDarkAppearance: systemPrefersDark)
        guard let theme = GhosttyThemeCatalog.parseTerminalTheme(named: name) else { return }
        for backend in activeBackends.values {
            backend.applyBackgroundColor(theme.background)
        }
        NotificationCenter.default.post(name: .terminalThemeDidChange, object: nil)
    }

    // MARK: - Theme

    /// Apply a theme selection and reload every surface.
    @discardableResult
    func apply(themeSelection selection: ThemeSelection) -> Bool {
        guard GhosttyThemeCatalog.apply(selection) else { return false }
        reloadConfig()
        broadcastColorScheme()
        os_log(.info, log: log, "Theme applied: %{public}s", selection.configValue)
        return true
    }

    @discardableResult
    func applyTheme(named name: String) -> Bool {
        apply(themeSelection: .single(name))
    }

    /// Open our config file in the default editor. It carries the include lines that
    /// pull in the user's own Ghostty config, so it is the right entry point for
    /// "where do I configure this".
    func openConfig() {
        ManagedConfig.ensureExists()
        NSWorkspace.shared.open(URL(fileURLWithPath: ManagedConfig.rootPath))
    }

    // MARK: - Cleanup

    func shutdown() {
        if let app {
            ghostty_app_free(app)
            self.app = nil
        }
        if let config {
            ghostty_config_free(config)
            self.config = nil
        }
    }
}
