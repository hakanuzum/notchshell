import AppKit
import GhosttyKit
import os.log

private let log = OSLog(subsystem: AppIdentity.logSubsystem, category: "DebugWindow")

/// Minimal test window — plain opaque NSWindow with GhosttyBackend directly.
/// No SwiftUI, no NSPanel, no animation. For diagnosing transparency issues.
@MainActor
final class DebugTerminalWindow {
    /// Increment this on every meaningful change to verify the running build.
    static let buildVersion = 4

    private var window: NSWindow?
    private var backend: GhosttyBackend?

    /// Opens a plain NSWindow with a Ghostty terminal running the default shell.
    func open(command: String? = nil) {
        close()

        os_log(.info, log: log, "=== DebugTerminalWindow build v%d ===", Self.buildVersion)

        let frame = NSRect(x: 200, y: 200, width: 800, height: 500)

        let win = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        win.title = "\(AppIdentity.displayName) debug terminal (v\(Self.buildVersion))"
        win.isOpaque = true
        win.backgroundColor = .black
        win.isReleasedWhenClosed = false

        let b = GhosttyBackend()
        let termView = b.view
        os_log(.info, log: log, "termView type: %{public}s, isOpaque: %d, wantsLayer: %d",
               String(describing: type(of: termView)), termView.isOpaque ? 1 : 0, termView.wantsLayer ? 1 : 0)
        if let layer = termView.layer {
            os_log(.info, log: log, "termView.layer: %{public}s, isOpaque: %d, bg: %{public}s",
                   String(describing: type(of: layer)), layer.isOpaque ? 1 : 0,
                   layer.backgroundColor != nil ? "set" : "nil")
        }
        termView.frame = win.contentView!.bounds
        termView.autoresizingMask = [.width, .height]
        win.contentView!.addSubview(termView)

        // If command provided, run it directly as the process
        // Otherwise start default shell
        let executable: String
        let execName: String
        if let cmd = command {
            executable = "/bin/bash"
            execName = "bash"
            // For bash -c to work, we need the Ghostty command field
            // Instead, just run the script directly
        } else {
            executable = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
            execName = "-" + (executable as NSString).lastPathComponent
        }

        if let cmd = command {
            // Run script directly as the process
            b.startProcess(executable: cmd, execName: (cmd as NSString).lastPathComponent, currentDirectory: nil)
        } else {
            b.startProcess(executable: executable, execName: execName, currentDirectory: nil)
        }

        win.makeKeyAndOrderFront(nil)
        win.makeFirstResponder(termView)
        NSApp.activate(ignoringOtherApps: true)

        self.window = win
        self.backend = b

        os_log(.info, log: log, "Debug terminal window opened")
    }

    func backend_send(_ text: String) {
        backend?.send(text: text)
    }

    func close() {
        backend?.terminate()
        window?.close()
        backend = nil
        window = nil
    }

    /// Captures a screenshot using screencapture CLI tool.
    @discardableResult
    func screenshot(to path: String) -> Bool {
        guard let win = window else {
            os_log(.error, log: log, "No debug window to screenshot")
            return false
        }
        let windowID = win.windowNumber
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-l", "\(windowID)", "-o", "-x", path]
        do {
            try proc.run()
            proc.waitUntilExit()
            os_log(.info, log: log, "Screenshot saved to %{public}s", path)
            return proc.terminationStatus == 0
        } catch {
            os_log(.error, log: log, "screencapture failed: %{public}s", error.localizedDescription)
            return false
        }
    }

    /// Dumps the layer tree to /tmp/hakuke-layer-dump.txt
    func dumpLayerTree() {
        guard let win = window else { return }
        var lines: [String] = []
        lines.append("=== LAYER TREE DUMP ===")
        lines.append("Window isOpaque: \(win.isOpaque)")
        lines.append("Window backgroundColor: \(String(describing: win.backgroundColor))")
        if let contentView = win.contentView {
            dumpView(contentView, indent: 0, into: &lines)
        }
        lines.append("=== END DUMP ===")
        let text = lines.joined(separator: "\n")
        try? text.write(toFile: AppIdentity.debugScratchPath("layer-dump.txt"), atomically: true, encoding: .utf8)
    }

    private func dumpView(_ view: NSView, indent: Int, into lines: inout [String]) {
        let pad = String(repeating: "  ", count: indent)
        lines.append("\(pad)View: \(type(of: view)) frame=\(view.frame) isOpaque=\(view.isOpaque) wantsLayer=\(view.wantsLayer) alphaValue=\(view.alphaValue)")
        if let layer = view.layer {
            dumpLayer(layer, indent: indent + 1, into: &lines)
        }
        for sub in view.subviews {
            dumpView(sub, indent: indent + 1, into: &lines)
        }
    }

    private func dumpLayer(_ layer: CALayer, indent: Int, into lines: inout [String]) {
        let pad = String(repeating: "  ", count: indent)
        let bg = layer.backgroundColor != nil ? "\(layer.backgroundColor!)" : "nil"
        lines.append("\(pad)Layer: \(type(of: layer)) isOpaque=\(layer.isOpaque) bg=\(bg) opacity=\(layer.opacity) bounds=\(layer.bounds) masksToBounds=\(layer.masksToBounds)")
        for sub in layer.sublayers ?? [] {
            dumpLayer(sub, indent: indent + 1, into: &lines)
        }
    }

    /// Samples center pixels alpha from a saved screenshot PNG.
    func measureAlpha(fromScreenshot path: String) -> Double {
        guard let image = NSImage(contentsOfFile: path),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return -1 }

        let w = bitmap.pixelsWide
        let h = bitmap.pixelsHigh
        guard w > 0, h > 0 else { return -1 }

        var totalAlpha: Double = 0
        var count = 0
        let sampleSize = 10
        let cx = w / 2
        let cy = h / 2

        for dy in 0..<sampleSize {
            for dx in 0..<sampleSize {
                let x = cx - sampleSize/2 + dx
                let y = cy - sampleSize/2 + dy
                guard x >= 0, x < w, y >= 0, y < h else { continue }
                if let color = bitmap.colorAt(x: x, y: y) {
                    totalAlpha += color.alphaComponent
                    count += 1
                }
            }
        }

        return count > 0 ? totalAlpha / Double(count) : -1
    }
}
