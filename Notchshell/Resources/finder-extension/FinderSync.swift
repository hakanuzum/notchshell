import Cocoa
import FinderSync

/// Puts Notchshell in Finder: an item at the top of the right-click menu, and a button
/// in the toolbar.
///
/// The app already answers `open -a`, a Finder service and the `notchshell://` scheme,
/// but all three ask the user to go and find them. A folder you are already looking at
/// is the most common place to want a terminal, and this is the only route macOS offers
/// that puts the app *in* that view rather than a menu below it.
///
/// Deliberately does nothing itself. It resolves which folder you meant and opens a
/// `notchshell://` URL; the app does the rest. That keeps the extension inside the
/// sandbox macOS insists on for it without needing an application group to talk home —
/// a group identifier has to carry a team prefix, which an ad-hoc build has not got.
///
/// `@objc` on the class is load-bearing. Swift exposes a class to the Objective-C
/// runtime as `Module.Class`, while `NSExtensionPrincipalClass` in Info.plist is a bare
/// name; without this the extension registers, enables, and then silently never
/// launches, which reads exactly like a code-signing rejection and is not one.
@objc(NotchshellFinderSync)
final class NotchshellFinderSync: FIFinderSync {

    override init() {
        super.init()
        // Every mounted volume, not `/`. Watching the root works but claims more than
        // is meant, and a volume mounted later would not be covered either way — hence
        // the observer.
        let controller = FIFinderSyncController.default()
        controller.directoryURLs = Set(
            FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]
            ) ?? [URL(fileURLWithPath: "/")]
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification, object: nil, queue: .main
        ) { note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            FIFinderSyncController.default().directoryURLs.insert(url)
        }
    }

    // MARK: - Toolbar

    override var toolbarItemName: String { "Notchshell" }
    override var toolbarItemToolTip: String { "Open this folder in Notchshell" }

    /// The app's own mark, carried inside the extension rather than read from the app.
    /// A Finder Sync extension is sandboxed, so the containing app's Resources are not
    /// its to open; the build copies the image in beside it.
    ///
    /// Drawn as a template so macOS tints it for the toolbar and inverts it in dark
    /// mode, the way every other toolbar glyph behaves.
    /// A padded, square copy of the mark rather than the menu-bar one.
    ///
    /// Finder scales this into a fixed slot, so how big the mark *looks* is decided by
    /// how much of its own canvas it fills. The menu-bar artwork fills its canvas edge
    /// to edge — measured, no transparent border at all — so scaled into the same box
    /// as a system glyph it came out visibly heavier than everything beside it. The
    /// toolbar copy sits at ~62% of a square canvas, which is where the system's own
    /// glyphs sit. Setting a smaller `size` does not help: the slot rescales it back.
    override var toolbarItemImage: NSImage {
        guard let url = Bundle.main.url(forResource: "NotchshellFinderToolbar",
                                        withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "apple.terminal",
                           accessibilityDescription: "Notchshell") ?? NSImage()
        }
        image.isTemplate = true
        return image
    }

    // MARK: - Menus

    /// One item, worded for where it appears.
    ///
    /// The toolbar button is only a mark, so the menu it drops has to carry the words:
    /// "Open Terminal". In the right-click menu you are pointing at a folder and asking
    /// for something new in it, which is what the rest of that menu says too — "New
    /// Folder", "New File" — so it reads "New Terminal" there.
    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
        let title = menuKind == .toolbarItemMenu ? "Open Terminal" : "New Terminal"
        // No icon on the item. Dropped from the toolbar button it would repeat the mark
        // you just clicked, and in the right-click menu the words are enough.
        menu.addItem(NSMenuItem(title: title,
                                action: #selector(openHere(_:)),
                                keyEquivalent: ""))
        return menu
    }

    /// The folder the click meant.
    ///
    /// Right-clicking a file means the folder it is in — you cannot open a terminal
    /// "at" a spreadsheet, and refusing would only make the item look broken. Empty
    /// space, the sidebar and the toolbar all mean the folder on screen.
    private func targetDirectory() -> URL? {
        let controller = FIFinderSyncController.default()
        if let selected = controller.selectedItemURLs()?.first {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: selected.path, isDirectory: &isDirectory) {
                return isDirectory.boolValue ? selected : selected.deletingLastPathComponent()
            }
        }
        return controller.targetedURL()
    }

    @objc private func openHere(_ sender: AnyObject?) {
        guard let directory = targetDirectory() else { return }
        var components = URLComponents()
        components.scheme = "notchshell"
        // No host: `notchshell:///Users/…`. The app accepts both shapes, and leaving
        // the host empty keeps the path whole rather than eating its first component.
        components.path = directory.path
        guard let url = components.url else { return }
        NSWorkspace.shared.open(url)
    }
}
