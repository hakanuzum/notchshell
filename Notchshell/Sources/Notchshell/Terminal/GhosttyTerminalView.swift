import AppKit
import GhosttyKit

/// NSView subclass that hosts the Ghostty Metal renderer and forwards input events.
final class GhosttyTerminalView: NSView {
    weak var backend: GhosttyBackend?
    private var trackingArea: NSTrackingArea?
    private var markedTextStorage = NSMutableAttributedString()
    private var keyTextAccumulator: [String]?

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // Do NOT set wantsLayer here. Ghostty's Metal renderer makes this view
        // "layer-hosting" by setting view.layer BEFORE view.wantsLayer = true.
        // Setting wantsLayer first would make it "layer-backed" instead,
        // which breaks IOSurface compositing.
    }

    // MARK: - Responder

    override var acceptsFirstResponder: Bool { true }
    /// Claiming opacity lets AppKit skip whatever is behind this view — which is the
    /// right call until the user asks for a translucent background, and fatal after.
    override var isOpaque: Bool { !TerminalAppearanceSettings.isTranslucent }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let surface = backend?.surface {
            ghostty_surface_set_focus(surface, true)
            if let displayID = window?.screen?.displayID, displayID != 0 {
                ghostty_surface_set_display_id(surface, displayID)
            }
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result, let surface = backend?.surface {
            ghostty_surface_set_focus(surface, false)
        }
        return result
    }

    // MARK: - Layout & Display

    override func layout() {
        super.layout()
        updateSurfaceSize()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil else { return }
        updateSurfaceSize()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contentsScale = window?.backingScaleFactor ?? 1.0
        CATransaction.commit()
        updateSurfaceSize()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        // Report the appearance that is actually in effect. This used to be pinned to
        // dark, which fought GhosttyApp's own scheme handling and, more importantly,
        // made `theme = light:A,dark:B` inert — Ghostty was never told to switch.
        guard let surface = backend?.surface else { return }
        ghostty_surface_set_color_scheme(surface, GhosttyApp.shared.systemColorScheme)
    }

    func updateSurfaceSize() {
        guard let surface = backend?.surface else { return }
        let backingSize = convertToBacking(NSRect(origin: .zero, size: bounds.size)).size
        let wpx = UInt32(max(1, floor(backingSize.width)))
        let hpx = UInt32(max(1, floor(backingSize.height)))

        let scale = window?.backingScaleFactor ?? 1.0
        let xScale = bounds.width > 0 ? backingSize.width / bounds.width : scale
        let yScale = bounds.height > 0 ? backingSize.height / bounds.height : scale

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.contentsScale = scale
        CATransaction.commit()

        ghostty_surface_set_content_scale(surface, xScale, yScale)
        ghostty_surface_set_size(surface, wpx, hpx)
    }


    // MARK: - Tracking areas

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let old = trackingArea { removeTrackingArea(old) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .activeAlways],
            owner: self, userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    // MARK: - Keyboard events

    override func doCommand(by selector: Selector) {
        // Suppress NSBeep — interpretKeyEvents calls this for non-text keys
        // (e.g. deleteBackward:, moveUp:). Ghostty handles all keys via ghostty_surface_key.
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return false }

        // Only handle if this view (or a descendant) is the first responder.
        guard let fr = window?.firstResponder as? NSView,
              fr === self || fr.isDescendant(of: self) else { return false }
        guard let surface = backend?.surface else { return false }

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // During IME composition, let non-Cmd keys flow to keyDown normally.
        if hasMarkedText(), !flags.contains(.command) {
            return false
        }

        // If Ghostty has a keybinding for this key, handle it.
        let isBinding: Bool = {
            var ke = ghosttyKeyEvent(for: event, surface: surface)
            let text = event.characters ?? ""
            var bindFlags = ghostty_binding_flags_e(0)
            return text.withCString { ptr in
                ke.text = ptr
                return ghostty_surface_key_is_binding(surface, ke, &bindFlags)
            }
        }()

        if isBinding {
            keyDown(with: event)
            return true
        }

        // Cmd+key: route through keyDown so Ghostty handles copy/paste/etc.
        // Without this, AppKit's responder chain eats Cmd+keys.
        if flags.contains(.command) {
            keyDown(with: event)
            return true
        }

        return false
    }

    override func keyDown(with event: NSEvent) {
        guard let surface = backend?.surface else { return }

        // Delete with a selection removes the whole selection: one backspace per selected
        // character. A terminal has no editable region the way an editor does, so this is
        // best-effort — the backspaces delete from the shell's cursor, which for the
        // common case (a trailing selection on the command line, cursor at the end) is
        // exactly what was highlighted. Only plain Delete; ⌥/⌘-Delete keep their
        // word/line meanings.
        let editingMods = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.keyCode == 51, editingMods.isEmpty, ghostty_surface_has_selection(surface) {
            var text = ghostty_text_s()
            if ghostty_surface_read_selection(surface, &text), let ptr = text.text, text.text_len > 0 {
                let count = String(cString: ptr).count
                ghostty_surface_free_text(surface, &text)
                for _ in 0..<count {
                    backend?.sendKeyPress(keyCode: 51, text: "\u{7F}")
                }
                return
            }
        }

        // Path 1: Non-printable keys (backspace, arrows, tab, escape, return, F-keys)
        // Bypass interpretKeyEvents to avoid NSBeep on rapid input.
        if markedTextStorage.length == 0 {
            let chars = event.characters ?? ""
            let isNonPrintable = chars.isEmpty || chars.unicodeScalars.allSatisfy {
                $0.value < 0x20 || $0.value == 0x7F ||
                ($0.value >= 0xF700 && $0.value <= 0xF8FF)
            }
            if isNonPrintable {
                sendKeyDirect(surface: surface, event: event)
                return
            }
        }

        // Path 2: Everything else — IME for text composition.
        // Ghostty handles option-as-alt, ctrl sequences, etc. via its own config.
        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }
        let hadMarkedText = markedTextStorage.length > 0

        let translationMods = ghostty_surface_key_translation_mods(surface, Self.modsFromEvent(event))
        let translationEvent = Self.applyTranslationMods(event, translated: translationMods)

        interpretKeyEvents([translationEvent])
        syncPreedit(clearIfNeeded: hadMarkedText)

        var keyEvent = ghostty_input_key_s()
        keyEvent.action = action
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = Self.modsFromEvent(event)
        keyEvent.consumed_mods = Self.consumedMods(translationMods)
        keyEvent.unshifted_codepoint = Self.unshiftedCodepoint(event)
        keyEvent.composing = markedTextStorage.length > 0 || hadMarkedText

        let accumulated = keyTextAccumulator ?? []
        if !accumulated.isEmpty {
            keyEvent.composing = false
            for text in accumulated {
                if shouldSendText(text) {
                    text.withCString { ptr in
                        keyEvent.text = ptr
                        _ = ghostty_surface_key(surface, keyEvent)
                    }
                } else {
                    keyEvent.text = nil
                    _ = ghostty_surface_key(surface, keyEvent)
                }
            }
        } else if let text = textForKeyEvent(translationEvent), shouldSendText(text) {
            text.withCString { ptr in
                keyEvent.text = ptr
                _ = ghostty_surface_key(surface, keyEvent)
            }
        } else {
            keyEvent.text = nil
            _ = ghostty_surface_key(surface, keyEvent)
        }
    }

    override func keyUp(with event: NSEvent) {
        guard let surface = backend?.surface else { super.keyUp(with: event); return }
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_RELEASE
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = Self.modsFromEvent(event)
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.text = nil
        keyEvent.composing = false
        keyEvent.unshifted_codepoint = Self.unshiftedCodepoint(event)
        _ = ghostty_surface_key(surface, keyEvent)
    }

    override func flagsChanged(with event: NSEvent) {
        guard let surface = backend?.surface else { super.flagsChanged(with: event); return }
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_PRESS
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = Self.modsFromEvent(event)
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.text = nil
        keyEvent.composing = false
        keyEvent.unshifted_codepoint = 0
        _ = ghostty_surface_key(surface, keyEvent)
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        // Clicking into the terminal dismisses the Settings sidebar (a click within the
        // sidebar does not reach here, so it stays open). The click still drives the
        // terminal below, so it both closes the sidebar and does what it would anyway.
        NotificationCenter.default.post(name: .terminalClicked, object: nil)
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(backend?.surface, point.x, bounds.height - point.y, Self.modsFromEvent(event))
        _ = ghostty_surface_mouse_button(backend?.surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, Self.modsFromEvent(event))
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(backend?.surface, point.x, bounds.height - point.y, Self.modsFromEvent(event))
        _ = ghostty_surface_mouse_button(backend?.surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, Self.modsFromEvent(event))
        copySelectionIfEnabled()
    }

    /// Copy-on-select: the moment a mouse selection is finished, put it on the clipboard
    /// so it can be pasted without a further Copy — the behaviour iTerm2 and others call
    /// "copy on select". Gated behind a default-on setting, and behind an actual
    /// selection so a plain click (which clears any selection) does not wipe the
    /// clipboard.
    private func copySelectionIfEnabled() {
        guard UserDefaults.standard.object(forKey: "copyOnSelect") as? Bool ?? true,
              let surface = backend?.surface,
              ghostty_surface_has_selection(surface) else { return }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text),
              let ptr = text.text, text.text_len > 0 else { return }
        let selection = String(cString: ptr)
        ghostty_surface_free_text(surface, &text)
        guard !selection.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(selection, forType: .string)
        NotificationCenter.default.post(name: .terminalDidCopy, object: nil,
                                        userInfo: ["count": selection.count])
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(backend?.surface, point.x, bounds.height - point.y, Self.modsFromEvent(event))
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(backend?.surface, point.x, bounds.height - point.y, Self.modsFromEvent(event))
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface = backend?.surface else { super.rightMouseDown(with: event); return }
        // If a TUI app captured the mouse (mc, vim, etc.), forward the click
        if ghostty_surface_mouse_captured(surface) {
            let point = convert(event.locationInWindow, from: nil)
            ghostty_surface_mouse_pos(surface, point.x, bounds.height - point.y, Self.modsFromEvent(event))
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, Self.modsFromEvent(event))
            return
        }
        // Show context menu
        let menu = NSMenu()
        let hasSelection = ghostty_surface_has_selection(surface)

        let copyItem = NSMenuItem(title: "Copy", action: #selector(contextCopy), keyEquivalent: "c")
        copyItem.keyEquivalentModifierMask = .command
        copyItem.isEnabled = hasSelection
        menu.addItem(copyItem)

        let pasteItem = NSMenuItem(title: "Paste", action: #selector(contextPaste), keyEquivalent: "v")
        pasteItem.keyEquivalentModifierMask = .command
        menu.addItem(pasteItem)

        if hasSelection {
            let cutItem = NSMenuItem(title: "Cut", action: #selector(contextCut), keyEquivalent: "x")
            cutItem.keyEquivalentModifierMask = .command
            menu.addItem(cutItem)
        }

        menu.addItem(.separator())

        let splitH = NSMenuItem(title: "Split Horizontal", action: #selector(contextSplitH), keyEquivalent: "d")
        splitH.keyEquivalentModifierMask = .command
        menu.addItem(splitH)

        let splitV = NSMenuItem(title: "Split Vertical", action: #selector(contextSplitV), keyEquivalent: "d")
        splitV.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(splitV)

        menu.addItem(.separator())

        let selectAllItem = NSMenuItem(title: "Select All", action: #selector(contextSelectAll), keyEquivalent: "a")
        selectAllItem.keyEquivalentModifierMask = .command
        menu.addItem(selectAllItem)

        let clearItem = NSMenuItem(title: "Clear", action: #selector(contextClear), keyEquivalent: "k")
        clearItem.keyEquivalentModifierMask = .command
        menu.addItem(clearItem)

        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface = backend?.surface else { super.rightMouseUp(with: event); return }
        if ghostty_surface_mouse_captured(surface) {
            _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, Self.modsFromEvent(event))
        }
    }

    // MARK: - Context menu actions

    @objc private func contextCopy() {
        guard let surface = backend?.surface else { return }
        "copy:clipboard".withCString { ptr in
            _ = ghostty_surface_binding_action(surface, ptr, UInt(14))
        }
    }

    @objc private func contextPaste() {
        guard let surface = backend?.surface,
              let text = NSPasteboard.general.string(forType: .string) else { return }
        guard let data = text.data(using: .utf8), !data.isEmpty else { return }
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: CChar.self) else { return }
            ghostty_surface_text(surface, base, UInt(rawBuffer.count))
        }
    }

    @objc private func contextCut() {
        contextCopy()
        backend?.sendKeyPress(keyCode: 51, text: "\u{7F}")
    }

    @objc private func contextSelectAll() {
        guard let surface = backend?.surface else { return }
        "select_all".withCString { ptr in
            _ = ghostty_surface_binding_action(surface, ptr, UInt(10))
        }
    }

    @objc private func contextSplitH() {
        NotificationCenter.default.post(name: .splitRequest, object: nil, userInfo: ["axis": "horizontal"])
    }

    @objc private func contextSplitV() {
        NotificationCenter.default.post(name: .splitRequest, object: nil, userInfo: ["axis": "vertical"])
    }

    @objc private func contextClear() {
        backend?.send(text: "\u{0C}")
    }

    /// Accumulated scroll and pinch toward the next whole-point font step. Kept between
    /// events because one wheel notch or one pinch frame is a fraction of a step, and
    /// stepping per event would either overshoot or ignore small movements.
    private var fontZoomAccumulator: CGFloat = 0

    override func scrollWheel(with event: NSEvent) {
        guard backend?.surface != nil else { return }

        // ⌘-scroll zooms the font instead of scrolling the buffer — the mouse's
        // counterpart to pinch-to-zoom on a trackpad. Consumed here so the scrollback
        // does not also move under the cursor.
        if event.modifierFlags.contains(.command) {
            zoomFont(byScroll: event)
            return
        }

        var x = event.scrollingDeltaX
        var y = event.scrollingDeltaY
        let precise = event.hasPreciseScrollingDeltas
        if precise { x *= 2; y *= 2 }

        var scrollMods: Int32 = precise ? 1 : 0
        let momentum: Int32
        switch event.momentumPhase {
        case .began:     momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_BEGAN.rawValue)
        case .changed:   momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_CHANGED.rawValue)
        case .ended:     momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_ENDED.rawValue)
        case .cancelled: momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_CANCELLED.rawValue)
        default:         momentum = Int32(GHOSTTY_MOUSE_MOMENTUM_NONE.rawValue)
        }
        scrollMods |= momentum << 1

        ghostty_surface_mouse_scroll(backend?.surface, x, y, ghostty_input_scroll_mods_t(scrollMods))
    }

    // MARK: - Font zoom (⌘-scroll and pinch)

    /// One font point per this much accumulated *precise* (trackpad) scroll, in points.
    /// A two-finger drag emits many small deltas; this makes the zoom firm rather than
    /// racing away. A mouse wheel does not use this — see below.
    private static let preciseScrollPerFontStep: CGFloat = 20

    /// One font point per this much accumulated pinch. `magnification` is a small ratio
    /// (a full pinch is ~0.3–0.5 end to end), so a step every ~0.04 gives a firm but
    /// unhurried zoom.
    private static let magnificationPerFontStep: CGFloat = 0.04

    private func zoomFont(byScroll event: NSEvent) {
        // Direction, not the "natural scrolling" setting: up/away enlarges, down/toward
        // shrinks, like every other app's ⌘-zoom. That setting only flips content
        // scrolling, which this path replaces.
        if event.hasPreciseScrollingDeltas {
            fontZoomAccumulator += event.scrollingDeltaY
            stepFontFromAccumulator(unit: Self.preciseScrollPerFontStep)
        } else {
            // A mouse wheel: one notch, one point. `scrollingDeltaY` is ±1 per notch in
            // line units, so its sign is the whole story and accumulation is not needed.
            let notches = event.scrollingDeltaY
            guard notches != 0 else { return }
            GhosttyApp.shared.adjustFontSize(by: notches > 0 ? 1 : -1)
        }
    }

    override func magnify(with event: NSEvent) {
        // Pinch-to-zoom on the trackpad: the mouse-free counterpart to ⌘-scroll. No
        // modifier — pinch has no other meaning over a terminal, and requiring ⌘ on a
        // gesture no app asks for it would just make it feel broken.
        fontZoomAccumulator += event.magnification * (Self.preciseScrollPerFontStep / Self.magnificationPerFontStep)
        stepFontFromAccumulator(unit: Self.preciseScrollPerFontStep)
        if event.phase == .ended || event.phase == .cancelled { fontZoomAccumulator = 0 }
    }

    /// Convert accumulated precise movement into whole-point steps and apply them,
    /// keeping the sub-step remainder so slow movement still eventually lands a step.
    private func stepFontFromAccumulator(unit: CGFloat) {
        let steps = (fontZoomAccumulator / unit).rounded(.towardZero)
        guard steps != 0 else { return }
        fontZoomAccumulator -= steps * unit
        GhosttyApp.shared.adjustFontSize(by: Double(steps))
    }

    override func mouseExited(with event: NSEvent) {
        guard NSEvent.pressedMouseButtons == 0 else { return }
        ghostty_surface_mouse_pos(backend?.surface, -1, -1, Self.modsFromEvent(event))
    }

    // MARK: - Key helpers

    /// Send a key event directly to Ghostty, bypassing interpretKeyEvents.
    /// Returns whether Ghostty handled the key (useful for Ctrl path fallthrough).
    @discardableResult
    private func sendKeyDirect(surface: ghostty_surface_t, event: NSEvent) -> Bool {
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = Self.modsFromEvent(event)
        keyEvent.consumed_mods = GHOSTTY_MODS_NONE
        keyEvent.composing = false
        keyEvent.unshifted_codepoint = Self.unshiftedCodepoint(event)
        // Use textForKeyEvent to properly handle function keys (nil text)
        // and control characters (unmodified char for Ghostty's KeyEncoder)
        if let text = textForKeyEvent(event), shouldSendText(text) {
            return text.withCString { ptr in
                keyEvent.text = ptr
                return ghostty_surface_key(surface, keyEvent)
            }
        } else {
            keyEvent.text = nil
            return ghostty_surface_key(surface, keyEvent)
        }
    }

    /// Build a ghostty_input_key_s for binding checks (used in performKeyEquivalent).
    private func ghosttyKeyEvent(for event: NSEvent, surface: ghostty_surface_t) -> ghostty_input_key_s {
        var keyEvent = ghostty_input_key_s()
        keyEvent.action = GHOSTTY_ACTION_PRESS
        keyEvent.keycode = UInt32(event.keyCode)
        keyEvent.mods = Self.modsFromEvent(event)
        keyEvent.consumed_mods = Self.consumedMods(
            ghostty_surface_key_translation_mods(surface, Self.modsFromEvent(event))
        )
        keyEvent.text = nil
        keyEvent.composing = false
        keyEvent.unshifted_codepoint = Self.unshiftedCodepoint(event)
        return keyEvent
    }

    /// Whether text should be sent to Ghostty (printable, not control chars).
    func shouldSendText(_ text: String) -> Bool {
        guard let first = text.utf8.first else { return false }
        return first >= 0x20
    }

    /// Extract text from a key event, handling control character encoding.
    /// For control chars, returns the unmodified character so Ghostty's KeyEncoder can apply its own encoding.
    /// Returns nil for function keys (Private Use Area).
    func textForKeyEvent(_ event: NSEvent) -> String? {
        guard let chars = event.characters, !chars.isEmpty else { return nil }
        if chars.count == 1, let scalar = chars.unicodeScalars.first {
            if scalar.value < 0x20 {
                return event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.control))
            }
            // Private Use Area characters (function keys) — don't send as text
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF {
                return nil
            }
        }
        return chars
    }

    /// Sync preedit (IME composition) state with Ghostty.
    private func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface = backend?.surface else { return }
        if markedTextStorage.length > 0 {
            markedTextStorage.string.withCString { ptr in
                ghostty_surface_preedit(surface, ptr, UInt(strlen(ptr)))
            }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    /// Create a translated NSEvent when macos-option-as-alt config modifies modifiers.
    private static func applyTranslationMods(_ event: NSEvent, translated: ghostty_input_mods_e) -> NSEvent {
        var newFlags = event.modifierFlags
        for (flag, ghosttyMod) in [
            (NSEvent.ModifierFlags.shift, GHOSTTY_MODS_SHIFT),
            (.control, GHOSTTY_MODS_CTRL),
            (.option, GHOSTTY_MODS_ALT),
            (.command, GHOSTTY_MODS_SUPER),
        ] {
            if translated.rawValue & ghosttyMod.rawValue != 0 {
                newFlags.insert(flag)
            } else {
                newFlags.remove(flag)
            }
        }
        guard newFlags != event.modifierFlags else { return event }
        return NSEvent.keyEvent(
            with: event.type, location: event.locationInWindow,
            modifierFlags: newFlags, timestamp: event.timestamp,
            windowNumber: event.windowNumber, context: nil,
            characters: event.characters(byApplyingModifiers: newFlags) ?? "",
            charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
            isARepeat: event.isARepeat, keyCode: event.keyCode
        ) ?? event
    }

    // MARK: - Modifier helpers

    static func modsFromEvent(_ event: NSEvent) -> ghostty_input_mods_e {
        var mods: UInt32 = GHOSTTY_MODS_NONE.rawValue
        let flags = event.modifierFlags
        if flags.contains(.shift)   { mods |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { mods |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option)  { mods |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { mods |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { mods |= GHOSTTY_MODS_CAPS.rawValue }
        return ghostty_input_mods_e(rawValue: mods)
    }

    /// Consumed mods: only Shift and Option contribute to text translation.
    static func consumedMods(_ mods: ghostty_input_mods_e) -> ghostty_input_mods_e {
        var result: UInt32 = GHOSTTY_MODS_NONE.rawValue
        if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { result |= GHOSTTY_MODS_SHIFT.rawValue }
        if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { result |= GHOSTTY_MODS_ALT.rawValue }
        return ghostty_input_mods_e(rawValue: result)
    }

    static func unshiftedCodepoint(_ event: NSEvent) -> UInt32 {
        guard let chars = event.characters(byApplyingModifiers: []),
              let scalar = chars.unicodeScalars.first else { return 0 }
        return scalar.value
    }
}

// MARK: - NSTextInputClient

extension GhosttyTerminalView: NSTextInputClient {
    func hasMarkedText() -> Bool {
        markedTextStorage.length > 0
    }

    func markedRange() -> NSRange {
        guard markedTextStorage.length > 0 else {
            return NSRange(location: NSNotFound, length: 0)
        }
        return NSRange(location: 0, length: markedTextStorage.length)
    }

    func selectedRange() -> NSRange {
        NSRange(location: NSNotFound, length: 0)
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let text: String
        if let attrStr = string as? NSAttributedString {
            text = attrStr.string
        } else if let str = string as? String {
            text = str
        } else {
            text = ""
        }
        markedTextStorage.mutableString.setString(text)

        // Sync preedit if not inside a keyDown handler
        if keyTextAccumulator == nil, let surface = backend?.surface {
            if text.isEmpty {
                ghostty_surface_preedit(surface, nil, 0)
            } else {
                text.withCString { ptr in
                    ghostty_surface_preedit(surface, ptr, UInt(strlen(ptr)))
                }
            }
        }
    }

    func unmarkText() {
        if markedTextStorage.length > 0 {
            markedTextStorage.mutableString.setString("")
            if let surface = backend?.surface {
                ghostty_surface_preedit(surface, nil, 0)
            }
        }
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }

    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }

    func insertText(_ string: Any, replacementRange: NSRange) {
        let chars: String
        if let attrStr = string as? NSAttributedString {
            chars = attrStr.string
        } else if let str = string as? String {
            chars = str
        } else {
            return
        }
        unmarkText()
        if keyTextAccumulator != nil {
            keyTextAccumulator?.append(chars)
        } else if let surface = backend?.surface {
            // Direct send outside keyDown (e.g. paste via Services menu)
            guard let data = chars.data(using: .utf8), !data.isEmpty else { return }
            data.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress?.assumingMemoryBound(to: CChar.self) else { return }
                ghostty_surface_text(surface, base, UInt(rawBuffer.count))
            }
        }
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface = backend?.surface, let window else { return .zero }
        var x: Double = 0, y: Double = 0, w: Double = 10, h: Double = 14
        ghostty_surface_ime_point(surface, &x, &y, &w, &h)
        let viewRect = NSRect(x: x, y: frame.size.height - y, width: w, height: max(h, 14))
        return window.convertToScreen(convert(viewRect, to: nil))
    }
}

// MARK: - NSScreen displayID helper

extension NSScreen {
    var displayID: UInt32 {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }
}
