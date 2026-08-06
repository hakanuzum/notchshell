import Testing
import Foundation
import GhosttyKit
@testable import Hakuke

/// The promise of the managed config layer is narrow and testable: the user's own
/// HOME so they exercise the real paths without touching the developer's dotfiles.
@Suite(.serialized)
struct ManagedConfigTests {

    private static let ghosttyReady: Bool = {
        ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS
    }()

    /// Run `body` against a throwaway config home.
    ///
    /// Redirecting `HOME` does not work: `NSHomeDirectory()` resolves through
    /// `getpwuid` and ignores it, so an earlier version of these tests silently read
    /// and wrote the developer's real `~/.config`. `XDG_CONFIG_HOME` is the hook that
    /// actually reroutes both us and Ghostty.
    private func withTemporaryConfigHome(
        ghosttyConfig: String? = nil,
        _ body: (_ configHome: URL) throws -> Void
    ) throws {
        let configHome = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("notchshell-config-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: configHome, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: configHome) }

        let previous = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
        setenv("XDG_CONFIG_HOME", configHome.path, 1)
        defer {
            if let previous { setenv("XDG_CONFIG_HOME", previous, 1) } else { unsetenv("XDG_CONFIG_HOME") }
        }

        if let ghosttyConfig {
            let dir = configHome.appendingPathComponent("ghostty")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try ghosttyConfig.write(to: dir.appendingPathComponent("config"),
                                    atomically: true, encoding: .utf8)
        }

        // Guard against the failure mode that produced this comment.
        #expect(ManagedConfig.directory.hasPrefix(configHome.path),
                "config paths escaped the sandbox — they would hit the real dotfiles")

        try body(configHome)
    }

    private func contents(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: - The user's config is never written

    @Test func applyingATheme_leavesTheUserGhosttyConfigByteIdentical() throws {
        let original = """
        font-family = JetBrainsMono NF
        font-size = 13
        theme = Catppuccin Mocha
        background-opacity = 0.97
        """
        try withTemporaryConfigHome(ghosttyConfig: original) { configHome in
            let userConfig = configHome.appendingPathComponent("ghostty/config")
            let before = try Data(contentsOf: userConfig)

            ManagedConfig.setTheme("Tokyo Night")

            let after = try Data(contentsOf: userConfig)
            #expect(before == after, "the user's Ghostty config must not be rewritten")
            #expect(try contents(userConfig).contains("theme = Catppuccin Mocha"))
        }
    }

    @Test func themeIsWrittenToOurOwnFile() throws {
        try withTemporaryConfigHome { _ in
            ManagedConfig.setTheme("Tokyo Night")
            let written = try contents(URL(fileURLWithPath: ManagedConfig.themeOverridePath))
            #expect(written.contains("theme = Tokyo Night"))
            #expect(ManagedConfig.currentTheme() == "Tokyo Night")
        }
    }

    // MARK: - Migration

    /// First launch after this change must look identical to the last launch before
    /// it, so whatever theme the user already had is carried across.
    @Test func firstRun_seedsThemeFromTheUserGhosttyConfig() throws {
        try withTemporaryConfigHome(ghosttyConfig: "theme = Catppuccin Mocha\n") { _ in
            ManagedConfig.ensureExists()
            #expect(ManagedConfig.currentTheme() == "Catppuccin Mocha")
        }
    }

    @Test func firstRun_withNoUserTheme_leavesThemeUnset() throws {
        try withTemporaryConfigHome(ghosttyConfig: "font-size = 13\n") { _ in
            ManagedConfig.ensureExists()
            #expect(ManagedConfig.currentTheme() == nil)
        }
    }

    @Test func ensureExists_doesNotClobberAnExistingRootConfig() throws {
        try withTemporaryConfigHome { _ in
            ManagedConfig.ensureExists()
            let root = URL(fileURLWithPath: ManagedConfig.rootPath)
            try (contents(root) + "\n# a line the user added\n")
                .write(to: root, atomically: true, encoding: .utf8)

            ManagedConfig.ensureExists()
            #expect(try contents(root).contains("# a line the user added"))
        }
    }

    // MARK: - Layering actually resolves

    /// End-to-end: load the managed root through libghostty and confirm the user's
    /// settings came through the include while our theme layer won.
    @Test func loadedConfig_inheritsUserSettingsAndAppliesOurTheme() throws {
        #expect(Self.ghosttyReady)
        try withTemporaryConfigHome(ghosttyConfig: "background = #111111\nforeground = #aaaaaa\n") { configHome in
            // Stand in for a theme by overriding background from our own layer.
            ManagedConfig.ensureExists()
            try "background = #222222\n".write(toFile: ManagedConfig.themeOverridePath,
                                               atomically: true, encoding: .utf8)

            let config = try #require(ghostty_config_new())
            defer { ghostty_config_free(config) }
            ManagedConfig.load(into: config)
            ghostty_config_finalize(config)

            #expect(ghostty_config_diagnostics_count(config) == 0)

            var color = ghostty_config_color_s()
            let readBackground = "background".withCString {
                ghostty_config_get(config, &color, $0, UInt(strlen($0)))
            }
            #expect(readBackground)
            #expect((color.r, color.g, color.b) == (0x22, 0x22, 0x22),
                    "our layer must override the user's value")

            var fg = ghostty_config_color_s()
            let readForeground = "foreground".withCString {
                ghostty_config_get(config, &fg, $0, UInt(strlen($0)))
            }
            #expect(readForeground)
            #expect((fg.r, fg.g, fg.b) == (0xaa, 0xaa, 0xaa),
                    "settings the user set and we do not override must survive")
            _ = configHome
        }
    }

    /// A user with no Ghostty config at all must still get a working setup — the
    /// include is marked optional for exactly this case.
    @Test func loadedConfig_withoutAnyUserGhosttyConfig_producesNoDiagnostics() throws {
        #expect(Self.ghosttyReady)
        try withTemporaryConfigHome { _ in
            let config = try #require(ghostty_config_new())
            defer { ghostty_config_free(config) }
            ManagedConfig.load(into: config)
            ghostty_config_finalize(config)
            #expect(ghostty_config_diagnostics_count(config) == 0)
        }
    }
}
