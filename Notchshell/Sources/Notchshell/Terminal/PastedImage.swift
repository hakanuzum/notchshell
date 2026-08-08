import AppKit
import os.log

/// Turns an image on the clipboard into a file path the terminal can paste.
///
/// A terminal has nowhere to put a picture. But the programs people run in one now do —
/// `claude`, `codex` and the rest take an image by path — and the thing you have when
/// you press ⌘V after a screenshot is pixels, not a path. So the pixels are written
/// somewhere and the path is typed instead, which is what you would have done by hand.
///
/// Only when the clipboard has no text of its own. Copying from a web page usually puts
/// both an image and its text on the board, and someone pressing ⌘V there means the
/// text; guessing otherwise would break ordinary pasting to serve a rarer case.
enum PastedImage {
    private static let log = OSLog(subsystem: AppIdentity.bundleID, category: "paste")

    /// Where the files go. Under this app's own data directory rather than `/tmp`, so
    /// they survive a reboot long enough for an agent to still be looking at one.
    static var directory: String { "\(AppIdentity.dataDirectory)/pasted" }

    /// Keep a week. Long enough that a conversation can refer back to an image, short
    /// enough that a screenshot habit does not quietly fill a disk.
    static let maximumAge: TimeInterval = 7 * 24 * 60 * 60

    /// The clipboard's image written to a file, or nil when there is nothing to write.
    static func pathForClipboardImage(_ pasteboard: NSPasteboard = .general) -> String? {
        // Text wins. See the note above.
        if let text = pasteboard.string(forType: .string), !text.isEmpty { return nil }

        guard let png = pngData(from: pasteboard) else { return nil }

        let stamp = Self.timestamp.string(from: Date())
        let path = "\(directory)/pasted-\(stamp).png"
        do {
            try FileManager.default.createDirectory(atPath: directory,
                                                    withIntermediateDirectories: true)
            try png.write(to: URL(fileURLWithPath: path), options: .atomic)
        } catch {
            os_log(.error, log: log, "Could not write pasted image: %{public}@",
                   error.localizedDescription)
            return nil
        }
        prune()
        return path
    }

    /// PNG whatever the board is holding.
    ///
    /// A screenshot arrives as TIFF, a browser drag as PNG, a file copied in Finder as a
    /// `file://` URL — and an agent asked to read `.tiff` will usually decline. One
    /// format out means one thing to explain.
    private static func pngData(from pasteboard: NSPasteboard) -> Data? {
        // A file already on disk is already a path; no copy needed.
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let url = urls.first, url.isFileURL,
           NSImage(contentsOf: url) != nil {
            return nil
        }
        guard let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// The path to paste for whatever is on the clipboard, or nil to let the terminal
    /// paste as it always has.
    ///
    /// A file copied in Finder is already a path, and reaching a terminal for it is the
    /// commonest reason anyone wants one — so its own path is used rather than a copy
    /// of its contents. Only pixels with no file behind them get written out.
    static func pathToPaste(_ pasteboard: NSPasteboard = .general) -> String? {
        if let text = pasteboard.string(forType: .string), !text.isEmpty { return nil }

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let url = urls.first, url.isFileURL {
            return url.path
        }
        return pathForClipboardImage(pasteboard)
    }

    /// A path with a space in it is a path someone will forget to quote.
    static func shellQuoted(_ path: String) -> String {
        guard path.contains(where: { " \t\"'\\$`&|;()<>*?[]{}!#~".contains($0) }) else {
            return path
        }
        return "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func prune() {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory) else { return }
        let cutoff = Date().addingTimeInterval(-maximumAge)
        for name in names {
            let path = "\(directory)/\(name)"
            guard let attributes = try? fm.attributesOfItem(atPath: path),
                  let modified = attributes[.modificationDate] as? Date,
                  modified < cutoff else { continue }
            try? fm.removeItem(atPath: path)
        }
    }

    private static let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        // No spaces and no colons: this goes on a command line, and a path that needs
        // quoting is a path someone will forget to quote.
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
