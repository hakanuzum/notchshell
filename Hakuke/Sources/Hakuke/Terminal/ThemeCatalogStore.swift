import AppKit
import SwiftUI
import os.log

private let storeLog = OSLog(subsystem: AppIdentity.logSubsystem, category: "ThemeCatalog")

/// Holds the theme catalog in memory so views can read it without touching the disk.
///
/// The picker used to call `GhosttyThemeCatalog.swatchColors(for:)` from inside a
/// `ForEach` body. SwiftUI re-evaluates that body on every render pass, and each call
/// walked the resource roots, stat'd candidate directories, read the theme file and
/// parsed it through libghostty — for every visible row, every pass. Caching into
/// `@State` from `onAppear` made it worse rather than better: writing to that
/// dictionary invalidated the list, which re-rendered the rows, which read from disk
/// again.
///
/// Everything here is read once, off the main thread, and served from memory
/// afterwards. `ThemeCatalogPerformanceTests` pins that: swatch lookups must not
/// increase `diskReadCount`.
@MainActor
final class ThemeCatalogStore: ObservableObject {

    /// Theme names, sorted for display.
    @Published private(set) var themeNames: [String] = []

    /// True while the initial read is in flight, so the picker can say so rather than
    /// appearing empty.
    @Published private(set) var isLoading = false

    /// How many themes were read from disk. Only meaningful to tests, which use it to
    /// prove lookups are served from memory.
    private(set) var diskReadCount = 0

    private var swatchesByName: [String: [Color]] = [:]
    private let directoryOverride: String?
    private var hasLoaded = false

    /// - Parameter directoryOverride: read this directory instead of the catalog's own
    ///   search path. Tests use it to read the vendored themes directly, since
    ///   `Bundle.main` under test is the test runner and has no bundled catalog.
    init(directoryOverride: String? = nil) {
        self.directoryOverride = directoryOverride
    }

    /// Read the catalog once. Repeated calls are ignored.
    func load() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        isLoading = true

        let override = directoryOverride
        let parsed = await Task.detached(priority: .userInitiated) { () -> (names: [String], swatches: [String: [Color]], reads: Int) in
            let names = Self.names(in: override)
            var swatches: [String: [Color]] = [:]
            var reads = 0
            for name in names {
                let path = override.map { $0 + "/" + name } ?? GhosttyThemeCatalog.url(forTheme: name)?.path
                guard let path else { continue }
                reads += 1
                guard let theme = GhosttyThemeCatalog.terminalTheme(atPath: path) else { continue }
                swatches[name] = Self.swatches(from: theme)
            }
            return (names, swatches, reads)
        }.value

        themeNames = parsed.names
        swatchesByName = parsed.swatches
        diskReadCount = parsed.reads
        isLoading = false
        os_log(.info, log: storeLog, "Loaded %d themes (%d readable)",
               parsed.names.count, parsed.swatches.count)
    }

    /// Re-read the catalog, for after the user drops a theme into
    /// `~/.config/ghostty/themes` while the app is running.
    func reload() async {
        hasLoaded = false
        await load()
    }

    /// Preview swatches for a theme: background, foreground, then ANSI accents.
    /// Nil when the theme could not be read — the row should show that rather than
    /// stand-in colours that look like a real palette.
    func swatches(for name: String) -> [Color]? {
        swatchesByName[name]
    }

    // MARK: - Reading

    nonisolated private static func names(in override: String?) -> [String] {
        if let override {
            let items = (try? FileManager.default.contentsOfDirectory(atPath: override)) ?? []
            return items.filter { !$0.hasPrefix(".") }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        return GhosttyThemeCatalog.availableThemes()
    }

    nonisolated private static func swatches(from theme: TerminalTheme) -> [Color] {
        var colors: [Color] = [Color(nsColor: theme.background), Color(nsColor: theme.foreground)]
        for index in 1...14 where index < theme.ansiColors.count {
            colors.append(Color(nsColor: theme.ansiColors[index]))
        }
        return colors
    }
}
