import SwiftUI
import AppKit
import KeyboardShortcuts

@main
struct HakukeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    static func main() {
        // Prevent multiple instances
        let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: AppIdentity.bundleID)
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

        // Launch debug terminal window if --debug-window [command] is passed.
        // The command used to be a path on the original author's machine, so this
        // harness only ever worked for them; take it from the command line instead.
        if let flagIndex = CommandLine.arguments.firstIndex(of: "--debug-window") {
            let command = CommandLine.arguments.dropFirst(flagIndex + 1).first
            guard let command else {
                print("--debug-window needs a command to run, e.g. --debug-window scripts/tui-test.sh")
                NSApp.terminate(nil)
                return
            }
            NSApp.setActivationPolicy(.regular)
            let dw = DebugTerminalWindow()
            dw.open(command: command)
            debugWindow = dw

            // Screenshot after TUI renders
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                dw.dumpLayerTree()
                let path = AppIdentity.debugScratchPath("debug-screenshot.png")
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
                accessibilityDescription: AppIdentity.displayName
            )
        }

        let menu = NSMenu()

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let versionItem = NSMenuItem(title: "\(AppIdentity.displayName) v\(version) (\(build))", action: nil, keyEquivalent: "")
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

        let quitItem = NSMenuItem(title: "Quit \(AppIdentity.displayName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
        alert.messageText = "Quit \(AppIdentity.displayName)?"
        alert.informativeText = "You have \(terminalCount) open terminal tab\(terminalCount == 1 ? "" : "s"). All sessions will be closed."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}
