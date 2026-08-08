import AppKit
import KeyboardShortcuts

/// A key on the keyboard, by virtual key code.
///
/// The codes were scattered through `WindowController` as private constants next to the
/// switch that used them. They live here now because two more things need to read them:
/// the palette, to print a shortcut beside a command, and the shortcut editor after it.
enum KeyCode {
    static let tab: UInt16 = 48
    static let t: UInt16 = 17
    static let w: UInt16 = 13
    static let comma: UInt16 = 43
    static let p: UInt16 = 35
    static let leftBracket: UInt16 = 33
    static let rightBracket: UInt16 = 30
    static let d: UInt16 = 2
    static let f: UInt16 = 3
    static let g: UInt16 = 5
    static let k: UInt16 = 40
    static let slash: UInt16 = 44
    static let `return`: UInt16 = 36

    static let digits: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
    ]

    /// How a key prints in a shortcut. Only the keys this app binds — a general
    /// keycode-to-character table would need the current keyboard layout, and getting
    /// that subtly wrong is worse than not offering it.
    static func symbol(for keyCode: UInt16) -> String {
        switch keyCode {
        case tab: return "⇥"
        case t: return "T"
        case w: return "W"
        case comma: return ","
        case p: return "P"
        case leftBracket: return "["
        case rightBracket: return "]"
        case d: return "D"
        case f: return "F"
        case g: return "G"
        case k: return "K"
        case slash: return "/"
        case `return`: return "↩"
        default:
            if let digit = digits[keyCode] { return String(digit) }
            return "?"
        }
    }
}

/// A key combination, as this app matches and prints it.
struct ActionShortcut: Equatable {
    var keyCode: UInt16
    var command: Bool = true
    var shift: Bool = false
    var control: Bool = false
    var option: Bool = false

    func matches(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        return event.keyCode == keyCode
            && flags.contains(.command) == command
            && flags.contains(.shift) == shift
            && flags.contains(.control) == control
            && flags.contains(.option) == option
    }

    /// In the order macOS prints modifiers — ⌃⌥⇧⌘ — which is not the order they are
    /// declared in.
    var display: String {
        var out = ""
        if control { out += "⌃" }
        if option { out += "⌥" }
        if shift { out += "⇧" }
        if command { out += "⌘" }
        return out + KeyCode.symbol(for: keyCode)
    }
}

/// One thing this app can be asked to do, named once.
///
/// Before this, an action was an anonymous `case` in `WindowController`'s key switch:
/// it had a key, a body and a comment, but no name and no existence outside that
/// switch. Nothing else could enumerate the actions, so a command palette or a shortcut
/// editor would each have had to restate the whole list — and a restated list drifts.
/// This app has been bitten by exactly that before, which is why `AppIdentity` exists.
///
/// So the registry is the single source: the key monitor resolves through it, and
/// everything else reads from it.
struct AppAction: Identifiable {
    /// Stable across renames of `title`, because the shortcut editor will persist it.
    let id: String
    let title: String
    /// Groups the palette lists under, and the section a shortcut editor would use.
    let group: Group
    let shortcut: ActionShortcut?
    /// Whether running it right now would do anything. A palette that offers "Reopen
    /// Closed Tab" with nothing closed is offering a no-op.
    let isEnabled: @MainActor () -> Bool
    let perform: @MainActor () -> Void

    /// Whether the shortcut editor offers this one.
    ///
    /// Four are deliberately fixed, and Settings says so rather than listing them:
    /// ⌘1–9 and ⌃⇥ are conventions rather than preferences, ⌘/ belongs to the menu bar,
    /// and ⌘P opens the editor's own sibling — rebinding the way in from inside is a
    /// door that can lock itself.
    let isRebindable: Bool

    enum Group: String, CaseIterable {
        case tabs = "Tabs"
        case panes = "Panes"
        case view = "View"
        case app = "App"
    }

    init(id: String,
         title: String,
         group: Group,
         shortcut: ActionShortcut? = nil,
         isRebindable: Bool = true,
         isEnabled: @escaping @MainActor () -> Bool = { true },
         perform: @escaping @MainActor () -> Void) {
        self.id = id
        self.title = title
        self.group = group
        self.shortcut = shortcut
        self.isRebindable = isRebindable
        self.isEnabled = isEnabled
        self.perform = perform
    }
}

extension AppAction {
    /// The name the recorder stores a rebinding under.
    ///
    /// Derived from `id` rather than declared separately, so a stored shortcut cannot
    /// end up attached to a different action than the one it is listed against. The
    /// built-in binding is registered as the library's default, which is what makes the
    /// recorder's "reset" mean "back to how it shipped" rather than "unbound".
    var shortcutName: KeyboardShortcuts.Name? {
        guard isRebindable else { return nil }
        return KeyboardShortcuts.Name("action.\(id)", default: shortcut.flatMap(\.recorderShortcut))
    }
}

extension ActionShortcut {
    /// This shortcut in the recorder's own vocabulary.
    var recorderShortcut: KeyboardShortcuts.Shortcut? {
        var modifiers: NSEvent.ModifierFlags = []
        if command { modifiers.insert(.command) }
        if shift { modifiers.insert(.shift) }
        if control { modifiers.insert(.control) }
        if option { modifiers.insert(.option) }
        return KeyboardShortcuts.Shortcut(
            KeyboardShortcuts.Key(rawValue: Int(keyCode)), modifiers: modifiers
        )
    }
}
