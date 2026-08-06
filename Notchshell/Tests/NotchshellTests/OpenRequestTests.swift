import Testing
import Foundation
@testable import Notchshell

/// Resolving "open a terminal here" requests. Every route into the app — Finder's
/// Services menu, `open -a` with a path, a `notchshell://` URL — funnels through
/// this, so the awkward inputs are worth pinning: a file rather than a folder, a
/// path that is gone, a URL with nothing in it.
@Suite(.serialized)
struct OpenRequestTests {

    private func withTemporaryTree(_ body: (_ dir: URL, _ file: URL) throws -> Void) throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("notchshell-open-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("notes.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        try body(dir, file)
    }

    // MARK: - Paths

    @Test func directory_isUsedAsIs() throws {
        try withTemporaryTree { dir, _ in
            #expect(OpenRequest.forPath(dir.path).directory == dir.path)
        }
    }

    /// "Open a terminal here" on a file means its folder — what every editor's
    /// reveal-in-terminal does. Handing the file path to a shell as a working
    /// directory would simply fail.
    @Test func file_resolvesToItsContainingDirectory() throws {
        try withTemporaryTree { dir, file in
            #expect(OpenRequest.forPath(file.path).directory == dir.path)
        }
    }

    @Test func missingPath_hasNoDirectory() {
        let path = NSTemporaryDirectory() + "/notchshell-absent-\(UUID().uuidString)"
        #expect(OpenRequest.forPath(path).directory == nil)
    }

    // MARK: - URLs

    @Test func url_withPath() throws {
        try withTemporaryTree { dir, _ in
            let url = URL(string: "\(AppIdentity.slug)://\(dir.path)")!
            #expect(OpenRequest.forURL(url)?.directory == dir.path)
        }
    }

    @Test func url_withCwdQuery() throws {
        try withTemporaryTree { dir, _ in
            var components = URLComponents()
            components.scheme = AppIdentity.slug
            components.host = "open"
            components.queryItems = [URLQueryItem(name: "cwd", value: dir.path)]
            #expect(OpenRequest.forURL(components.url!)?.directory == dir.path)
        }
    }

    /// A bare URL is a valid request: show the panel, start no tab.
    @Test func bareURL_showsPanelWithoutADirectory() {
        let url = URL(string: "\(AppIdentity.slug)://")!
        let request = OpenRequest.forURL(url)
        #expect(request != nil)
        #expect(request?.directory == nil)
    }

    /// This is how `open -a` and Finder's "Open With" actually arrive on modern
    /// macOS — as file URLs through the same delegate method. Rejecting them made
    /// both routes silently do nothing, which is exactly how it first behaved.
    @Test func fileURL_isAccepted() throws {
        try withTemporaryTree { dir, file in
            #expect(OpenRequest.forURL(URL(fileURLWithPath: dir.path))?.directory == dir.path)
            #expect(OpenRequest.forURL(URL(fileURLWithPath: file.path))?.directory == dir.path)
        }
    }

    @Test func foreignScheme_isRejected() {
        #expect(OpenRequest.forURL(URL(string: "ssh://example.com")!) == nil)
    }

    @Test func url_schemeIsCaseInsensitive() throws {
        try withTemporaryTree { dir, _ in
            let url = URL(string: "\(AppIdentity.slug.uppercased())://\(dir.path)")!
            #expect(OpenRequest.forURL(url)?.directory == dir.path)
        }
    }

    // MARK: - Info.plist declares the routes

    private static func infoPlist() throws -> [String: Any] {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Notchshell/Resources/Info.plist")
        let plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try #require(plist as? [String: Any])
    }

    /// The handlers are useless if the bundle does not advertise them, and nothing at
    /// runtime complains when it doesn't — the app simply never gets asked.
    @Test func infoPlist_declaresTheURLScheme() throws {
        let types = try #require(try Self.infoPlist()["CFBundleURLTypes"] as? [[String: Any]])
        let schemes = types.compactMap { $0["CFBundleURLSchemes"] as? [String] }.flatMap { $0 }
        #expect(schemes.contains(AppIdentity.slug))
    }

    @Test func infoPlist_declaresFolderHandling() throws {
        let types = try #require(try Self.infoPlist()["CFBundleDocumentTypes"] as? [[String: Any]])
        let contentTypes = types.compactMap { $0["LSItemContentTypes"] as? [String] }.flatMap { $0 }
        #expect(contentTypes.contains("public.folder"))
    }

    /// The Services entry names a selector by string; a rename on either side breaks
    /// it silently.
    @Test func infoPlist_serviceMessageMatchesTheHandler() throws {
        let services = try #require(try Self.infoPlist()["NSServices"] as? [[String: Any]])
        let messages = services.compactMap { $0["NSMessage"] as? String }
        #expect(messages.contains("openTabAtFolder"))
        #expect(AppDelegate.instancesRespond(to: Selector("openTabAtFolder:userData:error:")))
    }
}
