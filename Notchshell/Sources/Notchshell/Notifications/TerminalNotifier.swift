import Foundation
import AppKit
import UserNotifications
import os.log

/// Posts a macOS notification when a terminal asks for attention while you are not
/// looking at it.
///
/// The signal is not the bell. Measured against Claude Code 2.1: its `auto` notification
/// channel branches on `TERM_PROGRAM`, and libghostty sets `TERM_PROGRAM=ghostty`
/// (`vendor/ghostty/src/termio/Exec.zig`), so the `ghostty` branch is taken and the
/// agent emits OSC 9 / OSC 777 — a desktop notification carrying a title and a body —
/// rather than a BEL. Waiting for a bell here would have waited forever. Ghostty parses
/// both and hands them over as `GHOSTTY_ACTION_DESKTOP_NOTIFICATION`; this app used to
/// drop that action on the floor.
///
/// The bell is still honoured as a second path, for a program that rings one because it
/// found no richer channel — `Apple_Terminal` takes that branch, and so does anyone who
/// set `terminal_bell` by hand.
@MainActor
final class TerminalNotifier: NSObject {
    static let shared = TerminalNotifier()

    /// Posted when the user clicks a notification. `userInfo["tabID"]` names the tab.
    static let didActivateNotification = Notification.Name("notchshellNotificationActivated")

    /// Read from the notification-centre delegate, which arrives off the main actor.
    nonisolated static let tabIDKey = "tabID"

    /// Authorization is asked for on the first notification, not at launch. A menu-bar
    /// app that prompts for notifications before it has anything to say reads as
    /// presumptuous, and the answer is more informative when there is something to show.
    private var authorization: Bool?
    private var authorizationInFlight = false
    private var pending: [Item] = []

    /// Tab id → the identifier of the notification currently showing for it, so the
    /// previous one can be taken away before a new one is posted. See `post`.
    private var liveIdentifiers: [String: String] = [:]
    private var sequence = 0

    private struct Item {
        let title: String
        let subtitle: String
        let body: String
        let tabID: String
    }

    private override init() {
        super.init()
    }

    /// Set the delegate early so a click has somewhere to land. Cheap, and it does not
    /// prompt — only `requestAuthorization` does.
    func start() {
        guard !AppIdentity.isTestEnvironment else { return }
        UNUserNotificationCenter.current().delegate = self
    }

    func notify(title: String, subtitle: String, body: String, tabID: String) {
        guard !AppIdentity.isTestEnvironment else { return }
        guard UserDefaults.standard.object(forKey: "agentNotifications") == nil
                || UserDefaults.standard.bool(forKey: "agentNotifications") else { return }

        let item = Item(title: title, subtitle: subtitle, body: body, tabID: tabID)
        switch authorization {
        case .some(true):
            post(item)
        case .some(false):
            return
        case nil:
            pending.append(item)
            requestAuthorization()
        }
    }

    /// Drop a tab's notification once it has been read. Looking at the tab is the
    /// answer to the ask, so leaving the banner in Notification Centre afterwards
    /// would only ask again.
    func clear(tabID: String) {
        guard !AppIdentity.isTestEnvironment else { return }
        pending.removeAll { $0.tabID == tabID }
        guard let identifier = liveIdentifiers.removeValue(forKey: tabID) else { return }
        UNUserNotificationCenter.current()
            .removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    private func requestAuthorization() {
        guard !authorizationInFlight else { return }
        authorizationInFlight = true
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
                Task { @MainActor in
                    guard let self else { return }
                    self.authorizationInFlight = false
                    self.authorization = granted
                    if let error {
                        os_log(.error, "Notification authorization failed: %{public}@",
                               error.localizedDescription)
                    }
                    let queued = self.pending
                    self.pending.removeAll()
                    guard granted else { return }
                    for item in queued { self.post(item) }
                }
            }
    }

    private func post(_ item: Item) {
        let content = UNMutableNotificationContent()
        content.title = item.title
        // The tab, not the message — with several agents running, which one asked is
        // the part you cannot recover from the text.
        content.subtitle = item.subtitle
        content.body = item.body
        content.userInfo = [Self.tabIDKey: item.tabID]
        if UserDefaults.standard.object(forKey: "agentNotificationSound") == nil
            || UserDefaults.standard.bool(forKey: "agentNotificationSound") {
            content.sound = .default
        }

        // Still one live notification per tab — an agent that asks twice while you are
        // away should leave one entry saying so, not a stack of them — but by taking
        // the old one away, not by reusing its identifier.
        //
        // Reusing it was the bug. macOS treats a repeated identifier as an edit of the
        // notification already delivered: the text changes in Notification Centre and
        // nothing alerts. Measured in the notification database — a second call left
        // the record count unchanged and only moved its timestamp, so the second time
        // an agent asked for you, you were never told.
        if let previous = liveIdentifiers[item.tabID] {
            UNUserNotificationCenter.current()
                .removeDeliveredNotifications(withIdentifiers: [previous])
        }
        sequence += 1
        let identifier = "\(item.tabID)#\(sequence)"
        liveIdentifiers[item.tabID] = identifier

        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                os_log(.error, "Notification delivery failed: %{public}@",
                       error.localizedDescription)
            }
        }
    }
}

extension TerminalNotifier: UNUserNotificationCenterDelegate {
    /// Show the banner even when Notchshell is the frontmost app.
    ///
    /// macOS suppresses notifications from a foreground app unless it says otherwise
    /// here, and that default is wrong for a terminal: the panel being up and focused
    /// says nothing about whether you are looking at the tab that called. It is exactly
    /// the case this feature exists for — an agent finishing in tab two while you work
    /// in tab three — and without this the banner never appeared for it. Whether the
    /// notification is worth showing at all was already decided in `TabManager`, which
    /// stays silent when you *are* on the tab.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let tabID = response.notification.request.content.userInfo[Self.tabIDKey] as? String
        Task { @MainActor in
            if let tabID {
                NotificationCenter.default.post(
                    name: Self.didActivateNotification,
                    object: nil,
                    userInfo: [Self.tabIDKey: tabID]
                )
            }
            completionHandler()
        }
    }
}
