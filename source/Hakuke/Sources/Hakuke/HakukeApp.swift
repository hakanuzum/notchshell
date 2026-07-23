import SwiftUI
import AppKit
import KeyboardShortcuts

@main
struct HakukeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    static func main() {
        // Prevent multiple instances
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.hakuke.app")
        if runningApps.count > 1 {
            // Another instance is already running — activate it and exit
            runningApps.first(where: { $0 != .current })?.activate()
            exit(0)
        }
        HakukeApp.startApp()
    }

    /// Launch the standard SwiftUI app lifecycle.
    private static func startApp() {
        _startApp()
    }

    /// Trampoline into the SwiftUI lifecycle.
    @MainActor
    private static func _startApp() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let windowController = WindowController()
    private var statusItem: NSStatusItem!
    private var controlServer: ControlServer?
    private var mcpHTTPServer: MCPHTTPServer?
    private var debugWindow: DebugTerminalWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        GhosttyApp.shared.initialize()

        // Launch debug terminal window if --debug-window flag is passed
        if CommandLine.arguments.contains("--debug-window") {
            NSApp.setActivationPolicy(.regular)
            let dw = DebugTerminalWindow()
            let script = "/Users/maksimnagaev/Projects/hakuke/scripts/tui-test.sh"
            dw.open(command: script)
            debugWindow = dw

            // Screenshot after TUI renders
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                dw.dumpLayerTree()
                let path = "/tmp/hakuke-debug-screenshot.png"
                dw.screenshot(to: path)
                let alpha = dw.measureAlpha(fromScreenshot: path)
                print("DEBUG: Screenshot saved to \(path)")
                print("DEBUG: Center alpha = \(alpha) (1.0 = fully opaque)")
            }
            return
        }
        setupStatusItem()
        setupHotkey()
        let cs = ControlServer(windowController: windowController)
        controlServer = cs
        let mcpAccess = UserDefaults.standard.string(forKey: "mcpAccess") ?? "ask"
        if mcpAccess != "disabled" {
            let mcp = MCPHTTPServer(controlServer: cs)
            mcp.start()
            mcpHTTPServer = mcp
        }
        _ = SparkleUpdater.shared // Start automatic update checks
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "terminal",
                accessibilityDescription: "hakuke"
            )
        }

        let menu = NSMenu()

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let versionItem = NSMenuItem(title: "hakuke v\(version) (\(build))", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())

        let toggleItem = NSMenuItem(title: "Toggle Terminal", action: #selector(toggleTerminal), keyEquivalent: "")
        toggleItem.target = self
        toggleItem.setShortcut(for: .toggleTerminal)
        menu.addItem(toggleItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettingsMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        let helpItem = NSMenuItem(title: "Help", action: #selector(openHelpMenu), keyEquivalent: "/")
        helpItem.keyEquivalentModifierMask = .command
        helpItem.target = self
        menu.addItem(helpItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit hakuke", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func setupHotkey() {
        KeyboardShortcuts.onKeyDown(for: .toggleTerminal) { [weak self] in
            self?.windowController.toggle()
        }
    }

    @objc private func toggleTerminal() {
        windowController.toggle()
    }

    @objc private func openSettingsMenu() {
        windowController.openSettings()
    }

    @objc private func openHelpMenu() {
        windowController.openHelp()
    }

    @objc private func checkForUpdates() {
        SparkleUpdater.shared.checkForUpdates()
    }

    func applicationWillTerminate(_ notification: Notification) {
        windowController.tabManager.saveTabState()
    }

    // MARK: - Quit confirmation

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard UserDefaults.standard.bool(forKey: "confirmOnQuit") else { return .terminateNow }
        let terminalCount = windowController.tabManager.tabs.filter { $0.kind == .terminal }.count
        guard terminalCount > 0 else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Quit hakuke?"
        alert.informativeText = "You have \(terminalCount) open terminal tab\(terminalCount == 1 ? "" : "s"). All sessions will be closed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}
