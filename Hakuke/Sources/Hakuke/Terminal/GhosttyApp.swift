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

        // Ensure GHOSTTY_RESOURCES_DIR is set so Ghostty can find themes,
        // shell integration, etc. When launched from a non-Ghostty context
        // (e.g. Raycast, Spotlight, Finder) this env var won't be inherited.
        // Point Ghostty at the catalog we ship. Previously this probed for another
        // terminal's install (Ghostty.app, Homebrew, Muxy), which left the theme
        // picker empty on any machine that had none of them.
        if getenv("GHOSTTY_RESOURCES_DIR") == nil,
           let bundled = GhosttyThemeCatalog.bundledResourcesRoot {
            setenv("GHOSTTY_RESOURCES_DIR", bundled, 1)
            os_log(.info, log: log, "Set GHOSTTY_RESOURCES_DIR=%{public}s", bundled)
        }

        let result = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        guard result == GHOSTTY_SUCCESS else {
            os_log(.error, log: log, "ghostty_init failed with code %d", result)
            return
        }

        guard let primaryConfig = ghostty_config_new() else {
            os_log(.error, log: log, "ghostty_config_new returned nil")
            return
        }
        ghostty_config_load_default_files(primaryConfig)
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
        ghostty_config_load_default_files(newConfig)
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

    /// Path to the Ghostty config file.
    var configPath: String {
        guard app != nil else {
            return NSString(string: "~/.config/ghostty/config").expandingTildeInPath
        }
        let s = ghostty_config_open_path()
        guard let ptr = s.ptr, s.len > 0 else {
            return NSString(string: "~/.config/ghostty/config").expandingTildeInPath
        }
        return String(cString: ptr)
    }

    /// Apply a Ghostty theme by name (config only) and reload all surfaces.
    @discardableResult
    func applyTheme(named name: String) -> Bool {
        guard GhosttyThemeCatalog.applyTheme(named: name) else { return false }
        reloadConfig()
        if let parsed = GhosttyThemeCatalog.parseTerminalTheme(named: name) {
            for backend in activeBackends.values {
                backend.applyBackgroundColor(parsed.background)
                if let surface = backend.surface {
                    let isLight = parsed.background.usingColorSpace(.deviceRGB).map {
                        (0.2126 * $0.redComponent + 0.7152 * $0.greenComponent + 0.0722 * $0.blueComponent) > 0.5
                    } ?? false
                    ghostty_surface_set_color_scheme(
                        surface,
                        isLight ? GHOSTTY_COLOR_SCHEME_LIGHT : GHOSTTY_COLOR_SCHEME_DARK
                    )
                    ghostty_surface_refresh(surface)
                }
            }
        }
        os_log(.info, log: log, "Theme applied: %{public}s", name)
        return true
    }

    /// Open the Ghostty config file in the default editor.
    func openConfig() {
        let path = configPath
        // Ensure file exists
        let fm = FileManager.default
        let dir = (path as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: dir) {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        if !fm.fileExists(atPath: path) {
            try? "# Ghostty config — see https://ghostty.org/docs/config\n".write(toFile: path, atomically: true, encoding: .utf8)
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
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
