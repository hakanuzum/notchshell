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
    ///
    /// **The size is what makes the button, and it is not the pixel count.** Finder
    /// takes the toolbar button's *width* from the image's size, then draws the image
    /// scaled to fit the button's height. The bundled art is 128px at 72dpi, which
    /// `NSImage` reads as 128×128pt, so the button came out 128pt wide — around three
    /// times every other item in the toolbar — with a ~16pt mark adrift in the middle
    /// of all that space. Nothing about the artwork caused it; only that number did.
    /// OpenInTerminal's toolbar asset measures 23×23pt, which is the same finding read
    /// from a toolbar that always looked right.
    ///
    /// `image.size` alone does not do it — measured, the button stayed 128pt wide. The
    /// representation has to be resized too: the image crosses an XPC boundary to reach
    /// Finder and is rebuilt there, and what survives the trip is what the
    /// representations claim. Resizing them rather than redrawing keeps all 128px as
    /// retina detail behind a 23pt image.
    private func mark(side: CGFloat) -> NSImage {
        guard let url = Bundle.main.url(forResource: "NotchshellFinderToolbar",
                                        withExtension: "png"),
              let image = NSImage(contentsOf: url) else {
            return NSImage(systemSymbolName: "apple.terminal",
                           accessibilityDescription: "Notchshell") ?? NSImage()
        }
        for rep in image.representations {
            rep.size = NSSize(width: side, height: side)
        }
        image.size = NSSize(width: side, height: side)
        image.isTemplate = true
        return image
    }

    /// How big the mark *looks* against the glyph beside it is set twice over: by this,
    /// and by the ~72% of its own canvas the mark covers (`make-finder-toolbar-icon.swift`).
    override var toolbarItemImage: NSImage { mark(side: 23) }

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
        let item = NSMenuItem(title: title,
                              action: #selector(openHere(_:)),
                              keyEquivalent: "")
        // The mark in the right-click menu, where every other item has one and a bare
        // line reads as unfinished — but not under the toolbar button, where it would
        // repeat the mark you just clicked to get there.
        //
        // 16pt, not the toolbar's 23: a menu row grows to whatever its image claims, so
        // the toolbar size would leave this one item standing taller than the rest of
        // the menu it is joining.
        if menuKind != .toolbarItemMenu {
            item.image = mark(side: 16)
        }
        menu.addItem(item)
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
