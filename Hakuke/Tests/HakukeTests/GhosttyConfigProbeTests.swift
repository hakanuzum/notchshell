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
        guard ProcessInfo.processInfo.environment["MACUAKE_TEST_GHOSTTY"] != nil else {
            print("PROBE: skipped — set MACUAKE_TEST_GHOSTTY=1 to run")
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
}
