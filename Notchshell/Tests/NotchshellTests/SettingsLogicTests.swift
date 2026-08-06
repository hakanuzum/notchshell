import Testing
import Foundation
@testable import Notchshell

/// Tests for settings validation logic:
/// - Shell path validation (testAndApplyShell behavior)
/// - Shell picker binding logic
/// - TerminalInstance.configuredShell resolution
@MainActor
@Suite(.serialized)
struct ShellValidationTests {

    // MARK: - Shell path validation (mirrors testAndApplyShell logic)

    @Test func emptyPath_isInvalid() {
        let fm = FileManager.default
        let path = ""
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmed.isEmpty)
    }

    @Test func whitespaceOnlyPath_isInvalid() {
        let path = "   \t  "
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(trimmed.isEmpty)
    }

    @Test func nonExistentPath_notFound() {
        let path = "/this/path/does/not/exist/shell"
        let fm = FileManager.default
        #expect(!fm.fileExists(atPath: path))
    }

    @Test func validExecutable_binZsh_found() {
        let path = "/bin/zsh"
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: path))
        #expect(fm.isExecutableFile(atPath: path))
    }

    @Test func validExecutable_binBash_found() {
        let path = "/bin/bash"
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: path))
        #expect(fm.isExecutableFile(atPath: path))
    }

    @Test func validExecutable_binSh_found() {
        let path = "/bin/sh"
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: path))
        #expect(fm.isExecutableFile(atPath: path))
    }

    @Test func existingNonExecutable_detected() {
        // /etc/hosts exists but is not executable
        let path = "/etc/hosts"
        let fm = FileManager.default
        #expect(fm.fileExists(atPath: path))
        #expect(!fm.isExecutableFile(atPath: path))
    }

    @Test func pathWithWhitespace_trimmedBeforeValidation() {
        let path = "  /bin/zsh  "
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        let fm = FileManager.default
        #expect(fm.isExecutableFile(atPath: trimmed))
    }

    // MARK: - Shell validation flow (full logic)

    /// Mirrors the testAndApplyShell logic from SettingsView
    private enum ShellTestResult { case ok, notFound, notExecutable }

    private func validateShellPath(_ rawPath: String) -> ShellTestResult {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return .notFound }
        let fm = FileManager.default
        if !fm.fileExists(atPath: path) { return .notFound }
        if !fm.isExecutableFile(atPath: path) { return .notExecutable }
        return .ok
    }

    @Test func validate_emptyPath_notFound() {
        #expect(validateShellPath("") == .notFound)
    }

    @Test func validate_whitespace_notFound() {
        #expect(validateShellPath("   ") == .notFound)
    }

    @Test func validate_nonExistent_notFound() {
        #expect(validateShellPath("/no/such/shell") == .notFound)
    }

    @Test func validate_nonExecutable_detected() {
        #expect(validateShellPath("/etc/hosts") == .notExecutable)
    }

    @Test func validate_validShell_ok() {
        #expect(validateShellPath("/bin/zsh") == .ok)
    }

    @Test func validate_withLeadingWhitespace_ok() {
        #expect(validateShellPath("  /bin/zsh  ") == .ok)
    }
}

// MARK: - Shell picker binding logic

@MainActor
@Suite(.serialized)
struct ShellPickerTests {

    /// Mirrors the shell picker get-binding logic from SettingsView
    private static let knownShells = [
        "/bin/zsh", "/bin/bash", "/bin/sh",
        "/usr/local/bin/fish", "/opt/homebrew/bin/fish",
        "/usr/local/bin/zsh", "/opt/homebrew/bin/zsh",
        "/usr/local/bin/bash", "/opt/homebrew/bin/bash",
    ]

    private var availableShells: [String] {
        Self.knownShells.filter { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func pickerValue(shellPath: String, isCustomShell: Bool) -> String {
        if isCustomShell { return "__custom__" }
        let current = shellPath.isEmpty ? "auto" : shellPath
        if current == "auto" { return "auto" }
        if availableShells.contains(current) { return current }
        return "__custom__"
    }

    @Test func customShell_alwaysReturnsCustom() {
        #expect(pickerValue(shellPath: "/bin/zsh", isCustomShell: true) == "__custom__")
    }

    @Test func emptyShellPath_returnsAuto() {
        #expect(pickerValue(shellPath: "", isCustomShell: false) == "auto")
    }

    @Test func autoString_returnsAuto() {
        #expect(pickerValue(shellPath: "auto", isCustomShell: false) == "auto")
    }

    @Test func knownAvailableShell_returnsPath() {
        // /bin/zsh should be available on macOS
        let result = pickerValue(shellPath: "/bin/zsh", isCustomShell: false)
        #expect(result == "/bin/zsh")
    }

    @Test func unknownPath_returnsCustom() {
        let result = pickerValue(shellPath: "/weird/unknown/shell", isCustomShell: false)
        #expect(result == "__custom__")
    }

    @Test func availableShells_containsZsh() {
        #expect(availableShells.contains("/bin/zsh"))
    }

    @Test func availableShells_containsBash() {
        #expect(availableShells.contains("/bin/bash"))
    }

    @Test func availableShells_excludesNonexistent() {
        #expect(!availableShells.contains("/usr/local/bin/fish") || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/fish"))
    }
}

// MARK: - TerminalInstance.configuredShell

@MainActor
@Suite(.serialized)
struct ConfiguredShellTests {

    @Test func defaultShell_usesEnvironment() {
        // Reset UserDefaults
        UserDefaults.standard.removeObject(forKey: "shellPath")
        let shell = TerminalInstance.configuredShell
        // Should be $SHELL or /bin/zsh
        let envShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        #expect(shell == envShell)
    }

    @Test func emptyShellPath_usesEnvironment() {
        UserDefaults.standard.set("", forKey: "shellPath")
        let shell = TerminalInstance.configuredShell
        let envShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        #expect(shell == envShell)
        UserDefaults.standard.removeObject(forKey: "shellPath")
    }

    @Test func autoString_usesEnvironment() {
        UserDefaults.standard.set("auto", forKey: "shellPath")
        let shell = TerminalInstance.configuredShell
        let envShell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        #expect(shell == envShell)
        UserDefaults.standard.removeObject(forKey: "shellPath")
    }

    @Test func customPath_returnsThatPath() {
        UserDefaults.standard.set("/bin/bash", forKey: "shellPath")
        let shell = TerminalInstance.configuredShell
        #expect(shell == "/bin/bash")
        UserDefaults.standard.removeObject(forKey: "shellPath")
    }

    @Test func configuredShell_returnsNonEmpty() {
        let shell = TerminalInstance.configuredShell
        #expect(!shell.isEmpty)
    }

    @Test func configuredShell_isValidExecutable() {
        let shell = TerminalInstance.configuredShell
        #expect(FileManager.default.isExecutableFile(atPath: shell))
    }
}

// MARK: - ControlServer.accessState

@MainActor
@Suite(.serialized)
struct APIAccessStateTests {

    @Test func defaultState_isUnset() {
        UserDefaults.standard.removeObject(forKey: "apiAccess")
        #expect(ControlServer.accessState == "unset")
    }

    @Test func setState_enabled_persists() {
        ControlServer.accessState = "enabled"
        #expect(ControlServer.accessState == "enabled")
        UserDefaults.standard.removeObject(forKey: "apiAccess")
    }

    @Test func setState_disabled_persists() {
        ControlServer.accessState = "disabled"
        #expect(ControlServer.accessState == "disabled")
        UserDefaults.standard.removeObject(forKey: "apiAccess")
    }

    @Test func setState_overwritesPrevious() {
        ControlServer.accessState = "enabled"
        ControlServer.accessState = "disabled"
        #expect(ControlServer.accessState == "disabled")
        UserDefaults.standard.removeObject(forKey: "apiAccess")
    }

    @Test func setState_enabledDisabled_roundTrips() {
        ControlServer.accessState = "enabled"
        #expect(ControlServer.accessState == "enabled")
        ControlServer.accessState = "disabled"
        #expect(ControlServer.accessState == "disabled")
        ControlServer.accessState = "enabled"
        #expect(ControlServer.accessState == "enabled")
        UserDefaults.standard.removeObject(forKey: "apiAccess")
    }
}

// MARK: - GhosttyApp config path tests

@MainActor
@Suite(.serialized)
struct GhosttyConfigTests {

    @Test func configPath_isNonEmpty() {
        let path = GhosttyApp.shared.configPath
        #expect(!path.isEmpty)
    }

    /// `configPath` deliberately points at the layer this app owns, not at the user's
    /// Ghostty config — that one is included from it and never written to. This test
    /// asserted the opposite until the config layer was introduced, and it was not
    /// running at the time, so nothing caught the change.
    @Test func configPath_isOurOwnLayerNotTheUsers() {
        let path = GhosttyApp.shared.configPath
        #expect(path == ManagedConfig.rootPath)
        #expect(path.hasSuffix("/\(AppIdentity.slug)/config"))
        #expect(path != ManagedConfig.userGhosttyConfigPath)
    }

    @Test func reloadConfig_noCrash() {
        GhosttyApp.shared.initialize()
        GhosttyApp.shared.reloadConfig()
        // No crash = pass
    }
}

// MARK: - Display ID tests

@MainActor
@Suite(.serialized)
struct DisplayIDTests {

    @Test func displayID_setter_updatesValue() {
        let wc = WindowController()
        wc.setDisplayID(5)
        #expect(wc.displayID == 5)
        wc.setDisplayID(0)
        #expect(wc.displayID == 0)
    }

    @Test func displayID_setAndRead_roundTrips() {
        let wc = WindowController()
        for id in [0, 1, 42, 999] {
            wc.setDisplayID(id)
            #expect(wc.displayID == id)
        }
    }
}
