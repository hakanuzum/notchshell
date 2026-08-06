import Testing
import AppKit
import GhosttyKit
@testable import Hakuke

/// What reading themes costs, and the guarantee the picker depends on: that it is
/// paid once rather than on every render pass.
@MainActor
@Suite(.serialized)
struct ThemeCatalogPerformanceTests {

    private static let ghosttyReady: Bool = {
        ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) == GHOSTTY_SUCCESS
    }()

    private static var vendoredThemes: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("vendor/themes/themes")
    }

    private func milliseconds(_ body: () -> Void) -> Double {
        let start = DispatchTime.now().uptimeNanoseconds
        body()
        return Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
    }

    /// Not an assertion about speed — a record of the cost the picker used to pay on
    /// every SwiftUI render pass, which is why it now pays it once in a store.
    @Test func report_costOfReadingThemes() throws {
        #expect(Self.ghosttyReady)
        let dir = Self.vendoredThemes
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            .filter { !$0.hasPrefix(".") }.sorted()
        #expect(names.count > 400)

        let whole = milliseconds {
            for name in names {
                _ = GhosttyThemeCatalog.terminalTheme(atPath: dir.appendingPathComponent(name).path)
            }
        }

        // A row is ~64pt in a 320pt list, so roughly a dozen are on screen at once.
        let visible = names.prefix(12)
        let onePass = milliseconds {
            for name in visible {
                _ = GhosttyThemeCatalog.terminalTheme(atPath: dir.appendingPathComponent(name).path)
            }
        }

        print(String(format: "  themes                 %d", names.count))
        print(String(format: "  all of them            %.0f ms  (%.2f ms each)", whole, whole / Double(names.count)))
        print(String(format: "  the ~12 visible rows   %.1f ms  (%.0f%% of a 16.7ms frame)",
                     onePass, onePass / 16.7 * 100))
    }

    /// The store must read each theme once, however many times the view asks for it.
    /// This is the property the old picker lacked: it called into the catalog from
    /// inside a ForEach body, so every render re-read every visible theme from disk.
    @Test func store_readsEachThemeOnce() async throws {
        #expect(Self.ghosttyReady)
        let store = ThemeCatalogStore(directoryOverride: Self.vendoredThemes.path)
        await store.load()

        let firstReads = store.diskReadCount
        #expect(firstReads > 400, "expected the catalog to be read")

        // Ask for the same swatches many times over, as re-rendering would.
        for _ in 0..<50 {
            for name in store.themeNames.prefix(12) {
                _ = store.swatches(for: name)
            }
        }
        #expect(store.diskReadCount == firstReads, "swatch lookups must not touch the disk")
    }

    @Test func store_swatchLookupIsCheap() async throws {
        #expect(Self.ghosttyReady)
        let store = ThemeCatalogStore(directoryOverride: Self.vendoredThemes.path)
        await store.load()
        let names = Array(store.themeNames.prefix(12))

        let onePass = milliseconds {
            for _ in 0..<100 {
                for name in names { _ = store.swatches(for: name) }
            }
        }
        // 100 render passes worth of lookups should not approach a single frame.
        #expect(onePass < 16.7, "100 passes took \(onePass) ms")
    }
}
