import Foundation
import Sparkle

/// Thin wrapper around Sparkle's SPUStandardUpdaterController.
/// Provides a shared instance for menu items and Settings UI.
@MainActor
final class SparkleUpdater: ObservableObject {
    static let shared = SparkleUpdater()

    private let controller: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        // Observe canCheckForUpdates from SPUUpdater
        controller.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller.updater.automaticallyChecksForUpdates }
        set { controller.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }
}
