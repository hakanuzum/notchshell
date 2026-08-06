import Foundation

/// Where an "open a terminal here" request wants the new tab to start.
///
/// macOS has no system-wide default terminal, so the request arrives by whichever
/// route the caller had available — a folder from Finder, a `notchshell://` URL, an
/// `open -a` with a path. They all reduce to the same thing: a directory, or nothing.
///
/// Resolution is separated from the AppKit entry points so it can be tested without
/// a running app, and because the awkward cases are all in the resolution: a file
/// rather than a directory, a path that does not exist, a URL with no path at all.
struct OpenRequest: Equatable {
    /// Directory the new tab should start in. Nil means "just show the panel".
    let directory: String?

    /// A file's containing directory; a directory as itself; nil when neither exists.
    ///
    /// Callers pass what the user clicked, which for "open a terminal here" on a file
    /// means its folder — the same thing every editor's "reveal in terminal" does.
    static func forPath(_ path: String) -> OpenRequest {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return OpenRequest(directory: nil)
        }
        if isDirectory.boolValue {
            return OpenRequest(directory: path)
        }
        return OpenRequest(directory: (path as NSString).deletingLastPathComponent)
    }

    /// Accepts `notchshell:///Users/me/src`, `notchshell://open?cwd=/Users/me/src`,
    /// bare `notchshell://` (show the panel, no new tab) — and `file://` URLs.
    ///
    /// The two `notchshell://` shapes exist because neither covers everything: a path
    /// in the URL body is the obvious form to type, but a query parameter survives
    /// tools that insist on a host component.
    ///
    /// `file://` is here because that is how the request actually arrives. Modern
    /// AppKit delivers `open -a Notchshell <folder>` and Finder's "Open With" through
    /// `application(_:open:)` as file URLs rather than through the older
    /// `openFiles:`, so rejecting them made both routes silently do nothing.
    static func forURL(_ url: URL) -> OpenRequest? {
        if url.isFileURL {
            return forPath(url.path)
        }
        guard url.scheme?.lowercased() == AppIdentity.slug else { return nil }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let cwd = components.queryItems?.first(where: { $0.name == "cwd" })?.value,
           !cwd.isEmpty {
            return forPath((cwd as NSString).expandingTildeInPath)
        }

        let path = url.path
        guard !path.isEmpty, path != "/" else { return OpenRequest(directory: nil) }
        return forPath((path as NSString).expandingTildeInPath)
    }
}
