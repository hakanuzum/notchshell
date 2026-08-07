import Testing
import Foundation
@testable import Notchshell

/// What the bundle declares about permissions.
///
/// These matter more than most plist entries because the failure is silent. macOS
/// attributes a child process's request to the app that spawned it and reads the
/// prompt text from Info.plist; with no key for that permission the request is
/// denied outright — no prompt, no dialog, nothing in the app's log. A script in the
/// terminal just fails, and the reason is nowhere the user can see it.
@Suite(.serialized)
struct PermissionDeclarationTests {

    private static var resources: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Notchshell/Resources")
    }

    private static func plist(_ name: String) throws -> [String: Any] {
        let url = resources.appendingPathComponent(name)
        let value = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try #require(value as? [String: Any])
    }

    /// A terminal cannot know what will be run in it, so every permission a child
    /// process might reasonably ask for needs a description.
    @Test func infoPlist_declaresEveryPermissionAProcessMightRequest() throws {
        let info = try Self.plist("Info.plist")
        let required = [
            "NSAppleEventsUsageDescription",
            "NSCalendarsUsageDescription",
            "NSCameraUsageDescription",
            "NSContactsUsageDescription",
            "NSDesktopFolderUsageDescription",
            "NSDocumentsFolderUsageDescription",
            "NSDownloadsFolderUsageDescription",
            "NSLocalNetworkUsageDescription",
            "NSMicrophoneUsageDescription",
            "NSPhotoLibraryUsageDescription",
            "NSRemindersUsageDescription",
            "NSRemovableVolumesUsageDescription",
            "NSSystemAdministrationUsageDescription",
        ]
        let missing = required.filter { (info[$0] as? String)?.isEmpty ?? true }
        #expect(missing.isEmpty, "no prompt will be shown for: \(missing)")
    }

    /// The prompt names this app, so it should say who is actually asking. "Notchshell
    /// would like to access your contacts" is misleading — Notchshell does not want
    /// your contacts; something the user ran does.
    @Test func usageDescriptions_attributeTheRequestToTheProcess() throws {
        let info = try Self.plist("Info.plist")
        let descriptions = info.filter { $0.key.hasSuffix("UsageDescription") }
            .compactMapValues { $0 as? String }
        #expect(!descriptions.isEmpty)
        for (key, text) in descriptions {
            #expect(text.contains("process running in the terminal"),
                    "\(key) does not say who is asking: \(text)")
        }
    }

    // MARK: - Entitlements

    /// Sandboxing would defeat the point: the app exists to run programs the user
    /// chooses, with the user's own access to their own files.
    @Test func entitlements_sandboxIsOff() throws {
        let entitlements = try Self.plist("notchshell.entitlements")
        #expect(entitlements["com.apple.security.app-sandbox"] as? Bool == false)
    }

    /// Child processes are arbitrary: interpreters with a JIT allocate executable
    /// memory, and binaries the user builds are not signed by us. Under a hardened
    /// runtime, missing these kills those processes.
    @Test func entitlements_allowArbitraryChildProcesses() throws {
        let entitlements = try Self.plist("notchshell.entitlements")
        for key in ["com.apple.security.cs.allow-jit",
                    "com.apple.security.cs.allow-unsigned-executable-memory",
                    "com.apple.security.cs.disable-library-validation",
                    "com.apple.security.cs.allow-dyld-environment-variables"] {
            #expect(entitlements[key] as? Bool == true, "missing \(key)")
        }
    }

    /// Declared alongside NSAppleEventsUsageDescription — one without the other
    /// either blocks osascript or prompts with no explanation.
    @Test func entitlements_appleEventsMatchTheUsageDescription() throws {
        let entitlements = try Self.plist("notchshell.entitlements")
        let info = try Self.plist("Info.plist")
        #expect(entitlements["com.apple.security.automation.apple-events"] as? Bool == true)
        #expect(info["NSAppleEventsUsageDescription"] != nil)
    }
}
