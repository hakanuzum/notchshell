import SwiftUI
import AppKit

/// The camera on the tab bar: start, stop, and what to do with the result.
struct RecordButton: View {
    @ObservedObject var windowController: WindowController
    @ObservedObject var recorder: PanelRecorder

    @State private var showResult = false
    @State private var exporting = false
    @State private var exportedGIF: URL?
    /// Pin state to put back. Recording pins the panel, because auto-hide would order
    /// the window out mid-take and capture would go silent with nothing to show for it.
    @State private var pinBeforeRecording = false

    /// Set by the tab bar from the chrome setting.
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: toggle) {
            Image(systemName: recorder.isRecording ? "stop.circle.fill" : "video")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(recorder.isRecording ? Self.recordingRed : FolderTabPalette.of(colorScheme).barIcon)
                .frame(width: 24, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(recorder.isRecording ? "Stop Recording" : "Record Panel")
        .popover(isPresented: $showResult, arrowEdge: .top) {
            resultPopover
        }
        .onChange(of: showResult) { _, open in
            windowController.beginTransientInteraction(seconds: open ? 120 : 0.8)
        }
        // Dragging the bottom handle changes the terminal's height while the take is
        // running. The crop has to follow, or the recording keeps framing a rectangle
        // that is no longer the terminal.
        .onChange(of: windowController.heightPercent) { followTerminal() }
        .onChange(of: windowController.widthPercent) { followTerminal() }
        .onChange(of: windowController.chromeStyle) { followTerminal() }
    }

    private func followTerminal() {
        recorder.updateCrop(windowController.terminalContentRect)
    }

    private static let recordingRed = Color(red: 0.90, green: 0.22, blue: 0.20)

    // MARK: - Result

    private var resultPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(recorder.lastRecording?.lastPathComponent ?? "Recording")
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 8) {
                Button("Show in Finder") {
                    guard let url = recorder.lastRecording else { return }
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    showResult = false
                }
                Button(exporting ? "Exporting…" : "Export GIF") { exportGIF() }
                    .disabled(exporting || recorder.lastRecording == nil)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            if let exportedGIF {
                Text("GIF written next to it: \(exportedGIF.lastPathComponent)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            } else {
                Text("MP4 is smaller and plays everywhere; GIF is for places that only take images.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    // MARK: - Actions

    private func toggle() {
        if recorder.isRecording {
            Task {
                await recorder.stop()
                windowController.isPinned = pinBeforeRecording
                exportedGIF = nil
                showResult = recorder.lastRecording != nil
                if recorder.lastRecording == nil { report("Nothing was captured.") }
            }
            return
        }

        Task {
            pinBeforeRecording = windowController.isPinned
            windowController.isPinned = true
            do {
                try await recorder.start(
                    window: windowController.panel,
                    crop: windowController.terminalContentRect,
                    name: Self.recordingName()
                )
            } catch {
                windowController.isPinned = pinBeforeRecording
                report(message(for: error))
            }
        }
    }

    private func exportGIF() {
        guard let mp4 = recorder.lastRecording else { return }
        exporting = true
        Task {
            let destination = GIFExport.destination(for: mp4)
            do {
                try await GIFExport.export(mp4: mp4, to: destination)
                exportedGIF = destination
            } catch {
                report("Could not write the GIF.")
            }
            exporting = false
        }
    }

    private static func recordingName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "\(AppIdentity.displayName) \(formatter.string(from: Date()))"
    }

    private func message(for error: Error) -> String {
        switch error {
        case PanelRecorder.StartFailure.permissionMissing:
            return "Recording needs Screen Recording permission. Nothing else in \(AppIdentity.displayName) uses it."
        case PanelRecorder.StartFailure.permissionNeedsRelaunch:
            return "Screen Recording is granted, but macOS only hands it out at launch. Quit and reopen \(AppIdentity.displayName), then record."
        case PanelRecorder.StartFailure.windowNotFound:
            return "The panel is not on screen."
        default:
            return "Could not start recording."
        }
    }

    /// An alert rather than an inline label: starting a recording is a deliberate act,
    /// and a failure that only whispers leaves a button that looks broken.
    private func report(_ text: String) {
        windowController.beginTransientInteraction(seconds: 60)
        let alert = NSAlert()
        alert.messageText = "Recording"
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        if text.contains("Screen Recording permission") {
            alert.addButton(withTitle: "Open System Settings")
        }
        if alert.runModal() == .alertSecondButtonReturn {
            ScreenRecordingPermission.openSystemSettings()
        }
        windowController.beginTransientInteraction(seconds: 1)
    }
}
