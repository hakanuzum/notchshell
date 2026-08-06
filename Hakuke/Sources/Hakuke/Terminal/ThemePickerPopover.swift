import SwiftUI
import AppKit

/// Muxy-style quick theme picker. Applies Ghostty theme only (no starship/zsh rewrites).
struct ThemePickerPopover: View {
    @ObservedObject var windowController: WindowController
    let onDismiss: () -> Void

    @State private var filter = ""
    @State private var themes: [String] = []
    @State private var selected: String = GhosttyThemeCatalog.currentThemeName()
        ?? UserDefaults.standard.string(forKey: "selectedGhosttyTheme")
        ?? "Catppuccin Mocha"
    @State private var applying: String?
    @State private var swatchCache: [String: [Color]] = [:]

    private var filtered: [String] {
        if filter.isEmpty { return themes }
        return themes.filter { $0.localizedCaseInsensitiveContains(filter) }
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

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(filtered, id: \.self) { name in
                        ThemeRow(
                            name: name,
                            isSelected: name == selected,
                            isApplying: applying == name,
                            swatches: swatchCache[name] ?? GhosttyThemeCatalog.swatchColors(for: name)
                        ) {
                            apply(name)
                        }
                        .onAppear {
                            if swatchCache[name] == nil {
                                swatchCache[name] = GhosttyThemeCatalog.swatchColors(for: name)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(width: 320, height: 320)

            if filtered.isEmpty {
                Text("No themes match")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(16)
            }

            Divider()
            HStack {
                Text("\(filtered.count) / \(themes.count) themes")
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
        .onAppear {
            windowController.beginTransientInteraction(seconds: 120)
            themes = GhosttyThemeCatalog.availableThemes()
            if let current = GhosttyThemeCatalog.currentThemeName() {
                selected = current
            }
            for name in themes.prefix(24) {
                swatchCache[name] = GhosttyThemeCatalog.swatchColors(for: name)
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
        // Keep picker open to try multiple themes
    }
}

private struct ThemeRow: View {
    let name: String
    let isSelected: Bool
    let isApplying: Bool
    let swatches: [Color]
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

                HStack(spacing: 2) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(swatches.first ?? Color.black)
                            .frame(width: 28, height: 18)
                        Text("Ab")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(swatches.count > 1 ? swatches[1] : .white)
                    }
                    ForEach(Array(swatches.dropFirst(2).prefix(14).enumerated()), id: \.offset) { _, c in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(c)
                            .frame(width: 14, height: 18)
                    }
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
