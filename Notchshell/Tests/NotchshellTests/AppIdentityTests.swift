import Testing
import Foundation
@testable import Notchshell

/// `AppIdentity` and `Info.plist` declare the same facts in two places, and they had
/// already drifted once: the shipped bundle declared one identifier while `project.yml`
/// and the Help text told users to reset a different one, a domain that
/// never existed. Nothing at runtime notices that, so pin it here.
@Suite(.serialized)
struct AppIdentityTests {

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)      // …/Notchshell/Tests/NotchshellTests/<this file>
            .deletingLastPathComponent()      // NotchshellTests
            .deletingLastPathComponent()      // Tests
            .deletingLastPathComponent()      // Notchshell
            .deletingLastPathComponent()      // repo root
    }

    private static func infoPlist() throws -> [String: Any] {
        let url = repoRoot.appendingPathComponent("Notchshell/Resources/Info.plist")
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: Any])
    }

    @Test func bundleIdentifier_matchesInfoPlist() throws {
        let plist = try Self.infoPlist()
        #expect(plist["CFBundleIdentifier"] as? String == AppIdentity.bundleID)
    }

    /// What Finder and the menus show is the capitalised display name; the lowercase
    /// slug belongs to paths and the command line. Mixing them up is the easy mistake
    /// here, so assert both directions.
    @Test func bundleName_matchesDisplayName() throws {
        let plist = try Self.infoPlist()
        #expect(plist["CFBundleName"] as? String == AppIdentity.displayName)
        #expect(plist["CFBundleExecutable"] as? String == AppIdentity.displayName)
    }

    @Test func displayNameAndSlug_differOnlyInCase() {
        #expect(AppIdentity.displayName.lowercased() == AppIdentity.slug)
        #expect(AppIdentity.displayName != AppIdentity.slug, "the display name should be capitalised")
        #expect(AppIdentity.displayName.first?.isUppercase == true)
    }

    /// Machine-facing identifiers stay lowercase whatever the display name does.
    @Test func machineFacingNames_stayLowercase() {
        #expect(AppIdentity.bundleID == AppIdentity.bundleID.lowercased())
        #expect(AppIdentity.controlSocketPath == AppIdentity.controlSocketPath.lowercased())
        #expect(AppIdentity.configDirectory.hasSuffix("/\(AppIdentity.slug)"))
        #expect(AppIdentity.Links.repository.hasSuffix("/\(AppIdentity.slug)"))
    }

    /// Sparkle checks for updates at this URL. If it drifts from the repository the
    /// app silently stops receiving updates — no error, just nothing.
    @Test func sparkleFeed_pointsAtTheRepository() throws {
        let plist = try Self.infoPlist()
        let feed = try #require(plist["SUFeedURL"] as? String)
        #expect(feed.hasPrefix(AppIdentity.Links.repository + "/"))
    }

    // MARK: - Derived paths

    @Test func configDirectory_isUnderDotConfig_andNotGhostty() {
        let dir = AppIdentity.configDirectory
        #expect(dir.hasSuffix("/.config/\(AppIdentity.slug)"))
        // The user's own Ghostty config must never be the directory we write to.
        #expect(!dir.hasSuffix("/.config/ghostty"))
    }

    @Test func controlSocket_isNamespacedToTheApp() {
        #expect(AppIdentity.controlSocketPath == "/tmp/\(AppIdentity.slug).sock")
    }

    @Test func slug_isSafeForPathsAndCommandLine() {
        #expect(!AppIdentity.slug.isEmpty)
        #expect(AppIdentity.slug == AppIdentity.slug.lowercased())
        #expect(AppIdentity.slug.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" })
    }
}
