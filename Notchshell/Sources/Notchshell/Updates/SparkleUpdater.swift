import Foundation
import Sparkle

/// Thin wrapper around Sparkle's SPUStandardUpdaterController.
/// Provides a shared instance for menu items and Settings UI.
@MainActor
final class SparkleUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = SparkleUpdater()

    /// Assigned after `super.init()` because Sparkle is handed `self` as its delegate.
    private var controller: SPUStandardUpdaterController!

    @Published var canCheckForUpdates = false

    /// The version of an update that has been downloaded and is waiting to be installed,
    /// if there is one. Drives the menu-bar and Settings entries that offer to install it.
    @Published private(set) var waitingVersion: String?

    /// Sparkle's own "install it now and come back" handler, kept until the user asks.
    private var installWaiting: (() -> Void)?

    private override init() {
        super.init()
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
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

    // MARK: - Updates that would otherwise install silently

    /// Sparkle has downloaded an update and is about to schedule it for the next quit.
    ///
    /// Left alone, that means the update lands when the app terminates and the app does
    /// *not* come back — quitting was the user's own doing, so Sparkle does not undo it.
    /// For an app with a Dock icon that is reasonable. This one has none: it is
    /// `LSUIElement`, summoned by a hotkey, so a silent install on quit leaves ⌥Space
    /// dead with nothing on screen to say why.
    ///
    /// Returning true takes the update over. Sparkle stalls its scheduler and hands back
    /// a handler that installs *and relaunches*, with no UI of its own — so the app can
    /// offer it as a restart the user chooses. That choice is the point: this is a
    /// terminal, and the shells in it are somebody's work, not something to close on
    /// their behalf at a moment they did not pick.
    ///
    /// Taking control changes when the update can install, not whether it does. Quit
    /// first and Sparkle still installs on quit, as its own header promises.
    nonisolated func updater(_ updater: SPUUpdater,
                             willInstallUpdateOnQuit item: SUAppcastItem,
                             immediateInstallationBlock immediateInstallHandler: @escaping () -> Void) -> Bool {
        let version = item.displayVersionString
        Task { @MainActor in
            SparkleUpdater.shared.hold(version, install: immediateInstallHandler)
        }
        return true
    }

    private func hold(_ version: String, install: @escaping () -> Void) {
        waitingVersion = version
        installWaiting = install
    }

    /// Install the waiting update now. Sparkle quits the app, installs, and relaunches it;
    /// there is nothing to do afterwards, and nothing happens if none is waiting.
    func installWaitingUpdate() {
        installWaiting?()
    }
}
