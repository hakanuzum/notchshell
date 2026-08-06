import AppKit
import GhosttyKit
import os.log

private let log = OSLog(subsystem: AppIdentity.logSubsystem, category: "GhosttyBackend")

final class GhosttyBackend: NSObject, TerminalBackend {
    private(set) var surface: ghostty_surface_t?
    private let surfaceView: GhosttyTerminalView
    /// Opaque container view with solid black background behind the Metal rendering.
    /// Prevents transparent pixels from the Ghostty renderer bleeding through.
    private let containerView: NSView
    private var retainedSelf: Unmanaged<GhosttyBackend>?
    weak var delegate: TerminalBackendDelegate?

    var view: NSView { containerView }
    var focusableView: NSView { surfaceView }

    override init() {
        let frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        surfaceView = GhosttyTerminalView(frame: frame)

        // Opaque container: solid black layer behind the terminal
        containerView = NSView(frame: frame)
        containerView.wantsLayer = true
        containerView.layer?.isOpaque = true
        containerView.layer?.backgroundColor = NSColor.black.cgColor

        super.init()

        // Add terminal view on top of the opaque container
        surfaceView.frame = containerView.bounds
        surfaceView.autoresizingMask = [.width, .height]
        containerView.addSubview(surfaceView)

        surfaceView.backend = self
        GhosttyApp.shared.initialize()
        GhosttyApp.shared.registerBackend(self)
    }

    deinit {
        GhosttyApp.shared.unregisterBackend(self)
        if let surface {
            ghostty_surface_free(surface)
        }
        retainedSelf?.release()
    }

    // MARK: - Split surface creation

    /// Create a new GhosttyBackend for a split pane, inheriting config from this surface.
    func createSplitSurface() -> GhosttyBackend? {
        guard let surface, let app = GhosttyApp.shared.app else { return nil }

        let newBackend = GhosttyBackend()
        var config = ghostty_surface_inherited_config(surface, GHOSTTY_SURFACE_CONTEXT_SPLIT)

        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(
                nsview: Unmanaged.passUnretained(newBackend.surfaceView).toOpaque()
            )
        )

        let retained = Unmanaged.passRetained(newBackend)
        newBackend.retainedSelf = retained
        config.userdata = retained.toOpaque()

        let scale = newBackend.surfaceView.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2.0
        config.scale_factor = Double(scale)

        newBackend.surface = ghostty_surface_new(app, &config)
        guard newBackend.surface != nil else {
            os_log(.error, log: log, "Failed to create split surface")
            retained.release()
            newBackend.retainedSelf = nil
            return nil
        }

        ghostty_surface_set_color_scheme(newBackend.surface!, GHOSTTY_COLOR_SCHEME_DARK)
        ghostty_surface_refresh(newBackend.surface!)

        os_log(.info, log: log, "Split surface created")
        return newBackend
    }

    func createSplitBackend() -> TerminalBackend? {
        if let split = createSplitSurface() {
            return split
        }
        #if DEBUG
        // Test environment: no GPU surface, return plain backend for tree management tests
        return GhosttyBackend()
        #else
        return nil
        #endif
    }

    // MARK: - Process lifecycle

    func startProcess(executable: String, execName: String, currentDirectory: String?) {
        guard let app = GhosttyApp.shared.app else {
            os_log(.error, log: log, "Cannot create surface: GhosttyApp not initialized")
            return
        }

        var surfaceConfig = ghostty_surface_config_new()

        // Platform config: pass our NSView
        surfaceConfig.platform_tag = GHOSTTY_PLATFORM_MACOS
        surfaceConfig.platform = ghostty_platform_u(
            macos: ghostty_platform_macos_s(
                nsview: Unmanaged.passUnretained(surfaceView).toOpaque()
            )
        )

        // Userdata: retain self so callbacks can route back
        let retained = Unmanaged.passRetained(self)
        retainedSelf = retained
        surfaceConfig.userdata = retained.toOpaque()

        // Scale factor
        let scale = surfaceView.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2.0
        surfaceConfig.scale_factor = Double(scale)

        // Command and working directory use withCString to ensure lifetime
        let commandStr = executable
        let cwdStr = currentDirectory

        commandStr.withCString { cmdPtr in
            surfaceConfig.command = cmdPtr

            if let cwd = cwdStr, !cwd.isEmpty {
                cwd.withCString { cwdPtr in
                    surfaceConfig.working_directory = cwdPtr
                    self.surface = ghostty_surface_new(app, &surfaceConfig)
                }
            } else {
                self.surface = ghostty_surface_new(app, &surfaceConfig)
            }
        }

        guard let surface else {
            os_log(.error, log: log, "ghostty_surface_new returned nil")
            return
        }

        // Set display ID for CVDisplayLink
        if let displayID = (surfaceView.window?.screen ?? NSScreen.main)?.displayID, displayID != 0 {
            ghostty_surface_set_display_id(surface, displayID)
        }

        // Set content scale
        ghostty_surface_set_content_scale(surface, Double(scale), Double(scale))

        // Set initial size in pixels
        let backingSize = surfaceView.convertToBacking(
            NSRect(origin: .zero, size: surfaceView.bounds.size)
        ).size
        let wpx = UInt32(max(1, floor(backingSize.width)))
        let hpx = UInt32(max(1, floor(backingSize.height)))
        ghostty_surface_set_size(surface, wpx, hpx)

        // Set dark color scheme (hakuke is always dark)
        ghostty_surface_set_color_scheme(surface, GHOSTTY_COLOR_SCHEME_DARK)

        // Kick initial render
        ghostty_surface_refresh(surface)

        os_log(.info, log: log, "Surface created: %dx%d px", wpx, hpx)
    }

    func terminate() {
        guard let s = surface else { return }
        surface = nil
        ghostty_surface_free(s)
        retainedSelf?.release()
        retainedSelf = nil
    }

    // MARK: - Styling

    func applyFont(_ font: NSFont) {
        // Fonts come from Ghostty config.
    }

    func applyColors(
        foreground: NSColor, background: NSColor,
        cursor: NSColor, selection: NSColor,
        ansiColors: [NSColor]
    ) {
        // Glyph colors come from Ghostty theme; keep underlay plate in sync.
        applyBackgroundColor(background)
    }

    func applyBackgroundColor(_ color: NSColor) {
        containerView.wantsLayer = true
        containerView.layer?.isOpaque = true
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        containerView.layer?.backgroundColor = rgb.cgColor
        containerView.needsDisplay = true
    }

    // MARK: - Search (Phase 2)

    func showFindBar() {
        // Phase 2: ghostty_surface_binding_action
    }

    func findNext() {
        // Phase 2
    }

    func findPrevious() {
        // Phase 2
    }

    // MARK: - I/O

    func send(text: String) {
        guard let surface else { return }
        guard let data = text.data(using: .utf8), !data.isEmpty else { return }
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: CChar.self) else { return }
            ghostty_surface_text(surface, base, UInt(rawBuffer.count))
        }
    }

    /// Send a key press event (bypasses bracketed paste mode).
    func sendKeyPress(keyCode: UInt32, text: String, mods: ghostty_input_mods_e = GHOSTTY_MODS_NONE) {
        guard let surface else { return }
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_PRESS
        keyEvent.keycode = keyCode
        keyEvent.mods = mods
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.composing = false
        keyEvent.unshifted_codepoint = 0
        if !text.isEmpty {
            text.withCString { ptr in
                keyEvent.text = ptr
                _ = ghostty_surface_key(surface, keyEvent)
            }
        } else {
            keyEvent.text = nil
            _ = ghostty_surface_key(surface, keyEvent)
        }
    }

    func readBuffer(lineCount: Int) -> TerminalBufferSnapshot {
        guard let surface else { return TerminalBufferSnapshot(lines: [], rows: 0, cols: 0) }

        let size = ghostty_surface_size(surface)
        let rows = Int(size.rows)
        let cols = Int(size.columns)
        guard rows > 0, cols > 0 else {
            return TerminalBufferSnapshot(lines: [], rows: 0, cols: 0)
        }

        // Read viewport text via ghostty_surface_read_text
        let startRow = UInt32(max(0, rows - lineCount))
        var selection = ghostty_selection_s()
        selection.top_left = ghostty_point_s(
            tag: GHOSTTY_POINT_VIEWPORT,
            coord: GHOSTTY_POINT_COORD_TOP_LEFT,
            x: 0,
            y: startRow
        )
        selection.bottom_right = ghostty_point_s(
            tag: GHOSTTY_POINT_VIEWPORT,
            coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT,
            x: UInt32(cols - 1),
            y: UInt32(rows - 1)
        )
        selection.rectangle = false

        var text = ghostty_text_s()
        if ghostty_surface_read_text(surface, selection, &text),
           let ptr = text.text, text.text_len > 0 {
            let content = String(cString: ptr)
            ghostty_surface_free_text(surface, &text)
            let lines = content.components(separatedBy: "\n")
            return TerminalBufferSnapshot(lines: lines, rows: rows, cols: cols)
        }

        return TerminalBufferSnapshot(lines: [], rows: rows, cols: cols)
    }

    // MARK: - Action handling (called from GhosttyApp)

    func handleAction(_ action: ghostty_action_s) -> Bool {
        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            if let titlePtr = action.action.set_title.title {
                let title = String(cString: titlePtr)
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.terminalTitleChanged(title)
                }
            }
            return true

        case GHOSTTY_ACTION_PWD:
            if let pwdPtr = action.action.pwd.pwd {
                let pwd = String(cString: pwdPtr)
                DispatchQueue.main.async { [weak self] in
                    self?.delegate?.terminalDirectoryChanged(pwd)
                }
            }
            return true

        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            let exitCode = action.action.child_exited.exit_code
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.terminalProcessTerminated(exitCode: Int32(bitPattern: exitCode))
            }
            return true // Suppress Ghostty's "Press any key" fallback

        case GHOSTTY_ACTION_CELL_SIZE:
            // Size changes reported — we could use this for IME positioning
            return true

        case GHOSTTY_ACTION_COLOR_CHANGE:
            return true

        case GHOSTTY_ACTION_OPEN_URL:
            if let urlPtr = action.action.open_url.url {
                let urlStr = String(cString: urlPtr)
                if let url = URL(string: urlStr) {
                    DispatchQueue.main.async {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            return true

        case GHOSTTY_ACTION_RENDER:
            return true

        case GHOSTTY_ACTION_MOUSE_SHAPE:
            let shape = action.action.mouse_shape
            DispatchQueue.main.async { [weak self] in
                self?.updateCursor(shape)
            }
            return true

        case GHOSTTY_ACTION_RING_BELL:
            return true // Suppress terminal bell

        // Split pane actions — delegate to PaneManager via TerminalInstance
        case GHOSTTY_ACTION_NEW_SPLIT:
            let direction = action.action.new_split
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.terminalRequestedSplit(direction: direction.rawValue)
            }
            return true

        case GHOSTTY_ACTION_GOTO_SPLIT:
            let direction = action.action.goto_split
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.terminalRequestedGotoSplit(direction: direction.rawValue)
            }
            return true

        case GHOSTTY_ACTION_RESIZE_SPLIT:
            let direction = action.action.resize_split.direction
            let amount = action.action.resize_split.amount
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.terminalRequestedResizeSplit(direction: direction.rawValue, amount: amount)
            }
            return true

        case GHOSTTY_ACTION_EQUALIZE_SPLITS:
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.terminalRequestedEqualizeSplits()
            }
            return true

        case GHOSTTY_ACTION_TOGGLE_SPLIT_ZOOM:
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.terminalRequestedToggleSplitZoom()
            }
            return true

        default:
            return false
        }
    }

    private func updateCursor(_ shape: ghostty_action_mouse_shape_e) {
        switch shape {
        case GHOSTTY_MOUSE_SHAPE_TEXT:
            NSCursor.iBeam.set()
        case GHOSTTY_MOUSE_SHAPE_POINTER:
            NSCursor.pointingHand.set()
        case GHOSTTY_MOUSE_SHAPE_DEFAULT:
            NSCursor.arrow.set()
        case GHOSTTY_MOUSE_SHAPE_CROSSHAIR:
            NSCursor.crosshair.set()
        default:
            NSCursor.arrow.set()
        }
    }
}
