import SwiftUI
import AppKit

/// One searchable list of everything the app can do, plus every theme it can wear.
///
/// Themes are in here rather than behind their own picker because 602 of them is past
/// the point where a list is browsable: the only practical way through it is to type a
/// name. Actions and themes stay visibly separate — an action changes what happens, a
/// theme changes how it looks, and mixing them into one undifferentiated list would
/// make both harder to scan.
struct CommandPalette: View {
    @ObservedObject var windowController: WindowController
    let onDismiss: () -> Void

    @StateObject private var catalog = ThemeCatalogStore()
    @State private var query = ""
    @State private var selection = 0

    /// A row is either something to do or something to wear.
    enum Item: Identifiable {
        case action(AppAction)
        case theme(String)

        var id: String {
            switch self {
            case .action(let a): return "action.\(a.id)"
            case .theme(let name): return "theme.\(name)"
            }
        }

        var title: String {
            switch self {
            case .action(let a): return a.title
            case .theme(let name): return name
            }
        }
    }

    private var items: [Item] {
        Self.items(query: query,
                   actions: windowController.actions,
                   themeNames: catalog.themeNames)
    }

    /// Actions first, then themes. Themes only once something has been typed — opening
    /// the palette onto 602 theme names would bury the twenty things you actually came
    /// for.
    ///
    /// Pulled out of the view and made static so it can be tested directly. It was a
    /// computed property inside `body`'s reach, and when the list came back wrong the
    /// only way to look at it was to squint at a screenshot.
    static func items(query: String, actions: [AppAction], themeNames: [String]) -> [Item] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)

        let matchedActions = actions
            .filter { $0.isEnabled() }
            .filter { trimmed.isEmpty || matches($0.title, trimmed) }
            .map(Item.action)

        guard !trimmed.isEmpty else { return matchedActions }

        let themes = themeNames
            .filter { matches($0, trimmed) }
            .prefix(40)
            .map(Item.theme)

        return matchedActions + themes
    }

    /// Substring, case- and diacritic-insensitive. Not fuzzy matching: with theme names
    /// like "Ayu Mirage" and "Aurora", a fuzzy matcher puts noise above the exact thing
    /// you typed, and typing the name is the whole reason you opened this.
    static func matches(_ haystack: String, _ needle: String) -> Bool {
        haystack.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                PaletteField(text: $query,
                             onMove: move,
                             onCommit: { run(at: selection) },
                             onCancel: onDismiss)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if items.isEmpty {
                Text(query.isEmpty ? "No commands" : "Nothing matches")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                row(item, isSelected: index == selection)
                                    // The item's own id, not the row's position. Keying
                                    // on the index told SwiftUI that row 0 was the same
                                    // view no matter what was in it, so typing changed
                                    // the list underneath and left the old rows drawn:
                                    // the model said 7 Nord themes while the screen
                                    // still showed New Tab and Split Right.
                                    .id(item.id)
                                    .onTapGesture { run(at: index) }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: selection) { _, new in
                        guard new >= 0, new < items.count else { return }
                        proxy.scrollTo(items[new].id, anchor: .center)
                    }
                }
            }
        }
        .frame(width: 420)
        // Typing narrows the list under the cursor, so an index held from the previous
        // list would point at something the user never looked at.
        .onChange(of: query) { _, _ in selection = 0 }
        .task { await catalog.load() }
    }

    @ViewBuilder
    private func row(_ item: Item, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            switch item {
            case .action(let action):
                Text(action.title)
                    .font(.system(size: 12))
                Spacer(minLength: 8)
                Text(action.group.rawValue)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                if let shortcut = action.shortcut {
                    Text(shortcut.display)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 34, alignment: .trailing)
                }
            case .theme(let name):
                // The swatches are the point: a theme's name tells you almost nothing
                // and its colours tell you everything.
                if let swatches = catalog.swatches(for: name) {
                    HStack(spacing: 2) {
                        ForEach(Array(swatches.prefix(8).enumerated()), id: \.offset) { _, colour in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(colour)
                                .frame(width: 7, height: 11)
                        }
                    }
                }
                Text(name)
                    .font(.system(size: 12))
                Spacer(minLength: 8)
                Text("Theme")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear)
        .contentShape(Rectangle())
    }

    private func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        selection = min(max(selection + delta, 0), items.count - 1)
    }

    private func run(at index: Int) {
        guard index >= 0, index < items.count else { return }
        let item = items[index]
        onDismiss()
        switch item {
        case .action(let action):
            action.perform()
        case .theme(let name):
            windowController.beginTransientInteraction(seconds: 3.0)
            _ = windowController.applyGhosttyTheme(named: name)
        }
    }
}

/// A search field that hands the arrow keys and Escape back rather than eating them.
///
/// SwiftUI's `TextField` has no way to see those: `onKeyPress` is 15.0-only and
/// `.onExitCommand` does not fire while a field is first responder. Without this the
/// palette would be mouse-only, which defeats the point of a palette.
private struct PaletteField: NSViewRepresentable {
    var text: Binding<String>
    let onMove: (Int) -> Void
    let onCommit: () -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.placeholderString = "Run a command or pick a theme"
        field.delegate = context.coordinator
        context.coordinator.apply(self)
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.apply(self)
        // Only when SwiftUI genuinely holds something else. Writing the field's own
        // value back into it moves the insertion point to the start, which turns
        // typing "nord" into "dron".
        if field.stringValue != text.wrappedValue { field.stringValue = text.wrappedValue }
    }

    /// Holds the callbacks directly rather than a copy of the `PaletteField` struct.
    ///
    /// The first version stored the struct and wrote through `parent.text`. The field
    /// filled in — AppKit puts the characters there itself — while SwiftUI's `query`
    /// stayed empty, so the list never filtered and there was no way to tell from the
    /// screen which of the two had the text. Closures refreshed on every update leave
    /// nothing to go stale.
    final class Coordinator: NSObject, NSTextFieldDelegate {
        private var onText: (String) -> Void = { _ in }
        private var onMove: (Int) -> Void = { _ in }
        private var onCommit: () -> Void = {}
        private var onCancel: () -> Void = {}

        func apply(_ field: PaletteField) {
            onText = { field.text.wrappedValue = $0 }
            onMove = field.onMove
            onCommit = field.onCommit
            onCancel = field.onCancel
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            onText(field.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView,
                     doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                onMove(-1)
                return true
            case #selector(NSResponder.moveDown(_:)):
                onMove(1)
                return true
            case #selector(NSResponder.insertNewline(_:)):
                onCommit()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                onCancel()
                return true
            default:
                return false
            }
        }
    }
}
