import SwiftUI
import AppKit

/// Quick theme picker. Writes to the config layer this app owns; the user's own
/// Ghostty config is never touched.
struct ThemePickerPopover: View {
    @ObservedObject var windowController: WindowController
    let onDismiss: () -> Void

    @StateObject private var catalog = ThemeCatalogStore()
    @State private var filter = ""
    @State private var selected: String = GhosttyThemeCatalog.currentThemeName() ?? ""
    @State private var applying: String?

    private var filtered: [String] {
        guard !filter.isEmpty else { return catalog.themeNames }
        return catalog.themeNames.filter { $0.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 13))
                TextField("Search themes", text: $filter)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ZStack {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered, id: \.self) { name in
                            ThemeRow(
                                name: name,
                                isSelected: name == selected,
                                isApplying: applying == name,
                                swatches: catalog.swatches(for: name)
                            ) {
                                apply(name)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                if catalog.isLoading {
                    ProgressView().controlSize(.small)
                } else if filtered.isEmpty {
                    Text(catalog.themeNames.isEmpty ? "No themes found" : "No themes match")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 320, height: 320)

            Divider()
            HStack {
                Text("\(filtered.count) / \(catalog.themeNames.count) themes")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Spacer()
                Text(selected)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 320, height: 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            windowController.beginTransientInteraction(seconds: 120)
            await catalog.load()
            if let current = GhosttyThemeCatalog.currentThemeName() {
                selected = current
            }
        }
        .onDisappear {
            windowController.beginTransientInteraction(seconds: 0.8)
        }
    }

    private func apply(_ name: String) {
        applying = name
        windowController.beginTransientInteraction(seconds: 3.0)
        let ok = windowController.applyGhosttyTheme(named: name)
        applying = nil
        if ok { selected = name }
        // Keep the picker open so several themes can be tried in a row.
    }
}

private struct ThemeRow: View {
    let name: String
    let isSelected: Bool
    let isApplying: Bool
    /// Nil when the theme could not be read. Shown as such rather than filled with
    /// stand-in colours, which would look like a real palette.
    let swatches: [Color]?
    let onSelect: () -> Void

    @State private var hovered = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(name)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.accentColor)
                    } else if isApplying {
                        ProgressView().controlSize(.small)
                    }
                }

                if let swatches {
                    HStack(spacing: 2) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(swatches.first ?? Color.black)
                                .frame(width: 28, height: 18)
                            Text("Ab")
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundColor(swatches.count > 1 ? swatches[1] : .white)
                        }
                        ForEach(Array(swatches.dropFirst(2).prefix(14).enumerated()), id: \.offset) { _, colour in
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(colour)
                                .frame(width: 14, height: 18)
                        }
                    }
                } else {
                    Label("Could not be read", systemImage: "exclamationmark.triangle")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .frame(height: 18)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(
                        isSelected
                            ? Color.accentColor.opacity(0.12)
                            : (hovered ? Color.primary.opacity(0.06) : Color.clear)
                    )
                    .padding(.horizontal, 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}
