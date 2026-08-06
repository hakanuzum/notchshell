import Testing
import AppKit
import GhosttyKit
@testable import Hakuke

/// Probe: which config keys does `ghostty_config_get` actually answer, and what
/// does it write into the out-pointer? The C header documents neither, so measure
/// it instead of guessing before rewriting the theme parser on top of it.
///
/// Run with: MACUAKE_TEST_GHOSTTY=1 swift test --filter GhosttyConfigProbe
@MainActor
@Suite(.serialized)
struct GhosttyConfigProbeTests {

    private static let themeText = """
    palette = 0=#191919
    palette = 1=#aa342e
    palette = 7=#bebebe
    palette = 15=#f7f7f7
    background = #102040
    foreground = #dddddd
    cursor-color = #007acc
    selection-background = #bfdbfe
    """

    private func hex(_ c: ghostty_config_color_s) -> String {
        String(format: "#%02x%02x%02x", c.r, c.g, c.b)
    }

    /// Read a config key into `T`. Returns nil when Ghostty declines the key.
    private func get<T>(_ config: ghostty_config_t, _ key: String, as: T.Type) -> T? {
        var out = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { out.deallocate() }
        let ok = key.withCString { keyPtr in
            ghostty_config_get(config, out, keyPtr, UInt(strlen(keyPtr)))
        }
        return ok ? out.pointee : nil
    }

    @Test func probeConfigGet() throws {
        guard ProcessInfo.processInfo.environment[AppIdentity.testGhosttyEnvVar] != nil else {
            print("PROBE: skipped — set \(AppIdentity.testGhosttyEnvVar)=1 to run")
            return
        }

        let rc = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)
        print("PROBE ghostty_init -> \(rc) (0 = success)")

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hakuke-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let themeFile = dir.appendingPathComponent("ProbeTheme")
        try Self.themeText.write(to: themeFile, atomically: true, encoding: .utf8)

        guard let config = ghostty_config_new() else {
            print("PROBE: ghostty_config_new returned nil — cannot continue")
            return
        }
        defer { ghostty_config_free(config) }

        themeFile.path.withCString { ghostty_config_load_file(config, $0) }
        ghostty_config_finalize(config)

        // Palette: expect 256 entries, indices 0/1/7/15 matching the fixture.
        if let palette = get(config, "palette", as: ghostty_config_palette_s.self) {
            let c = withUnsafeBytes(of: palette.colors) { raw -> [ghostty_config_color_s] in
                Array(raw.bindMemory(to: ghostty_config_color_s.self))
            }
            print("PROBE palette      -> OK, \(c.count) entries")
            print("PROBE   [0]=\(hex(c[0])) [1]=\(hex(c[1])) [7]=\(hex(c[7])) [15]=\(hex(c[15]))")
            print("PROBE   [16]=\(hex(c[16])) [255]=\(hex(c[255]))  (auto-generated range)")
        } else {
            print("PROBE palette      -> DECLINED")
        }

        for key in ["background", "foreground", "cursor-color", "selection-background",
                    "selection-foreground", "cursor-text", "theme"] {
            if let color = get(config, key, as: ghostty_config_color_s.self) {
                print("PROBE \(key.padding(toLength: 21, withPad: " ", startingAt: 0))-> \(hex(color))")
            } else {
                print("PROBE \(key.padding(toLength: 21, withPad: " ", startingAt: 0))-> DECLINED")
            }
        }

        // Does an unset optional differ from a declined key?
        let bare = ghostty_config_new()!
        defer { ghostty_config_free(bare) }
        ghostty_config_finalize(bare)
        for key in ["background", "cursor-color", "selection-background"] {
            if let color = get(bare, key, as: ghostty_config_color_s.self) {
                print("PROBE unset \(key.padding(toLength: 21, withPad: " ", startingAt: 0))-> \(hex(color))")
            } else {
                print("PROBE unset \(key.padding(toLength: 21, withPad: " ", startingAt: 0))-> DECLINED")
            }
        }
    }

    /// The layered-config design rests on two claims about `config-file` that the
    /// docs assert but we have not seen for ourselves: an included file overrides
    /// keys set in the including file, and a `?` prefix makes a missing file
    /// non-fatal. If either is false, layering our theme over the user's untouched
    /// Ghostty config does not work and the design has to change.
    @Test func probeConfigFileLayering() throws {
        guard ProcessInfo.processInfo.environment[AppIdentity.testGhosttyEnvVar] != nil else {
            print("PROBE: skipped — set \(AppIdentity.testGhosttyEnvVar)=1 to run")
            return
        }
        _ = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("hakuke-layer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let base = dir.appendingPathComponent("base.conf")     // stands in for the user's config
        let layer = dir.appendingPathComponent("layer.conf")   // stands in for our theme layer
        let root = dir.appendingPathComponent("root.conf")     // what we would load
        let missing = dir.appendingPathComponent("absent.conf").path

        try "background = #111111\nforeground = #aaaaaa\n".write(to: base, atomically: true, encoding: .utf8)
        try "background = #222222\n".write(to: layer, atomically: true, encoding: .utf8)
        try """
        config-file = ?\(missing)
        config-file = \(base.path)
        config-file = \(layer.path)
        """.write(to: root, atomically: true, encoding: .utf8)

        // load_file reads the file's own keys but does not follow its `config-file`
        // directives; ghostty_config_load_recursive_files is what expands those.
        // Measured: without the recursive pass every include is silently ignored and
        // the config resolves to Ghostty's defaults, with zero diagnostics.
        let config = ghostty_config_new()!
        defer { ghostty_config_free(config) }
        root.path.withCString { ghostty_config_load_file(config, $0) }
        ghostty_config_load_recursive_files(config)
        ghostty_config_finalize(config)

        let diagnostics = ghostty_config_diagnostics_count(config)
        print("PROBE layering diagnostics -> \(diagnostics) (0 means `?` on a missing file is fine)")
        for i in 0..<diagnostics {
            if let m = ghostty_config_get_diagnostic(config, i).message {
                print("PROBE   diagnostic: \(String(cString: m))")
            }
        }

        let bg = get(config, "background", as: ghostty_config_color_s.self).map(hex) ?? "DECLINED"
        let fg = get(config, "foreground", as: ghostty_config_color_s.self).map(hex) ?? "DECLINED"
        print("PROBE background -> \(bg)  (#222222 = later include wins, #111111 = earlier wins)")
        print("PROBE foreground -> \(fg)  (#aaaaaa = inherited from base)")

        // Same question for the loader the app actually used before this change.
        // XDG_CONFIG_HOME redirects Ghostty's default config lookup at us.
        let xdg = dir.appendingPathComponent("xdg")
        let ghosttyDir = xdg.appendingPathComponent("ghostty")
        try FileManager.default.createDirectory(at: ghosttyDir, withIntermediateDirectories: true)
        try "config-file = \(layer.path)\nforeground = #aaaaaa\n"
            .write(to: ghosttyDir.appendingPathComponent("config"), atomically: true, encoding: .utf8)

        let previousXDG = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
        setenv("XDG_CONFIG_HOME", xdg.path, 1)
        defer {
            if let previousXDG { setenv("XDG_CONFIG_HOME", previousXDG, 1) } else { unsetenv("XDG_CONFIG_HOME") }
        }

        let viaDefaults = ghostty_config_new()!
        defer { ghostty_config_free(viaDefaults) }
        ghostty_config_load_default_files(viaDefaults)
        ghostty_config_finalize(viaDefaults)
        let defaultsBG = get(viaDefaults, "background", as: ghostty_config_color_s.self).map(hex) ?? "DECLINED"
        let defaultsFG = get(viaDefaults, "foreground", as: ghostty_config_color_s.self).map(hex) ?? "DECLINED"
        print("PROBE load_default_files alone: foreground -> \(defaultsFG) (#aaaaaa = file was read)")
        print("PROBE load_default_files alone: background -> \(defaultsBG) (#222222 = include followed)")
    }

    /// Where does `theme = light:A,dark:B` get resolved?
    ///
    /// If a finalized config already reports one of the two backgrounds, the choice is
    /// baked in at config level and switching appearance means reloading. If it
    /// reports something else, the pair survives into the surface and
    /// `ghostty_surface_set_color_scheme` is what picks a side — which would mean the
    /// scheme we report has to be the real system appearance, not something derived
    /// from the palette.
    @Test func probeDualThemeResolution() throws {
        guard ProcessInfo.processInfo.environment[AppIdentity.testGhosttyEnvVar] != nil else {
            print("PROBE: skipped — set \(AppIdentity.testGhosttyEnvVar)=1 to run")
            return
        }
        _ = ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv)

        // Point Ghostty at the vendored catalog so theme names resolve.
        let themes = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("vendor/themes")
        setenv("GHOSTTY_RESOURCES_DIR", themes.path, 1)
        defer { unsetenv("GHOSTTY_RESOURCES_DIR") }

        func background(of themeValue: String) -> String {
            let dir = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("hakuke-dual-\(UUID().uuidString)")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: dir) }
            let file = dir.appendingPathComponent("config")
            try? "theme = \(themeValue)\n".write(to: file, atomically: true, encoding: .utf8)

            guard let config = ghostty_config_new() else { return "no config" }
            defer { ghostty_config_free(config) }
            file.path.withCString { ghostty_config_load_file(config, $0) }
            ghostty_config_load_recursive_files(config)
            ghostty_config_finalize(config)
            let diagnostics = ghostty_config_diagnostics_count(config)
            var note = ""
            if diagnostics > 0, let m = ghostty_config_get_diagnostic(config, 0).message {
                note = "  [\(String(cString: m))]"
            }
            return (get(config, "background", as: ghostty_config_color_s.self).map(hex) ?? "DECLINED") + note
        }

        let light = "Catppuccin Latte"
        let dark = "Catppuccin Mocha"
        print("PROBE single light  '\(light)' -> \(background(of: light))")
        print("PROBE single dark   '\(dark)'  -> \(background(of: dark))")
        print("PROBE pair          -> \(background(of: "light:\(light),dark:\(dark)"))")
    }
}
