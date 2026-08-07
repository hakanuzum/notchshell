import AVFoundation
import AppKit
import ScreenCaptureKit
import os.log

private let log = OSLog(subsystem: AppIdentity.logSubsystem, category: "PanelRecorder")

/// Records the panel window to an MP4.
///
/// The filter is built from a single `SCWindow`, not a display, so the capture is the
/// panel and nothing else — whatever is behind it, including whatever the user is
/// actually working on, never enters the frame. That matters for a feature whose whole
/// purpose is handing the file to someone else.
///
/// MP4 is the recording format and GIF is an export of it (`GIFExport`), rather than
/// both being written at capture time. A terminal GIF is large and slow to encode;
/// doing it per-frame during a live capture would compete with the thing being
/// recorded, and most recordings are never turned into one.
@MainActor
final class PanelRecorder: NSObject, ObservableObject {

    enum StartFailure: Error {
        case permissionMissing
        /// Granted just now, but not to this process — macOS hands out screen capture
        /// at launch, so the grant applies from the next one.
        case permissionNeedsRelaunch
        case windowNotFound
        case failed(String)
    }

    @Published private(set) var isRecording = false
    @Published private(set) var lastRecording: URL?

    private var stream: SCStream?
    private var sink: Sink?
    private var configuration: SCStreamConfiguration?

    /// Recordings are things the user made to send to someone, so they go where a
    /// person would look for them rather than into a dot-directory.
    static var directory: URL {
        let movies = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Movies")
        return movies.appendingPathComponent(AppIdentity.displayName)
    }

    /// Recorded at the display's own backing resolution, because the subject is text.
    /// Downscaling a Retina panel to something chat-sized turns 12pt glyphs to mush —
    /// the first version capped at 1600px and was unreadable. The cap that remains is
    /// H.264's: 4096 is the widest level most decoders accept, and a full-width panel
    /// on this display is ~4562px, so it is a real limit rather than a preference.
    private static let maxWidth: CGFloat = 3840
    private static let framesPerSecond: Int32 = 30
    /// Text needs bits. Left to its own devices AVFoundation picks a rate tuned for
    /// camera footage, where blurring an edge costs nothing; on a terminal it eats the
    /// glyphs. Roughly 0.11 bits per pixel per frame, which a static terminal never
    /// comes close to spending.
    private static func bitrate(width: Int, height: Int) -> Int {
        Int(Double(width * height) * 0.11 * Double(framesPerSecond))
    }

    func start(window: NSWindow, crop: CGRect, name: String) async throws {
        guard !isRecording else { return }

        guard ScreenRecordingPermission.isGranted else {
            // Prompts the first time; from then on this is the user's standing answer.
            _ = ScreenRecordingPermission.request()
            throw ScreenRecordingPermission.isGranted
                ? StartFailure.permissionNeedsRelaunch
                : StartFailure.permissionMissing
        }

        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true
        )
        let windowID = CGWindowID(window.windowNumber)
        guard let target = content.windows.first(where: { $0.windowID == windowID }) else {
            throw StartFailure.windowNotFound
        }

        let scale = window.backingScaleFactor
        let pixelWidth = crop.width * scale
        let pixelHeight = crop.height * scale
        let factor = min(1, Self.maxWidth / max(pixelWidth, 1))
        let width = Self.even(pixelWidth * factor)
        let height = Self.even(pixelHeight * factor)

        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        // Only the terminal, not the chrome around it. The video track's dimensions are
        // fixed once writing starts, so a later resize changes this rectangle and lets
        // `scalesToFit` refit it — see `updateCrop`.
        configuration.sourceRect = crop
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: Self.framesPerSecond)
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.capturesAudio = false
        // Ghostty draws its own cursor; the pointer arrow on top is noise.
        configuration.showsCursor = false
        // A resize changes the crop's aspect, and the video's does not change with it.
        // Fitting keeps the terminal undistorted and pads instead.
        configuration.scalesToFit = true

        try FileManager.default.createDirectory(at: Self.directory, withIntermediateDirectories: true)
        let url = Self.directory.appendingPathComponent("\(name).mp4")

        let sink = try Sink(
            url: url, width: width, height: height,
            bitrate: Self.bitrate(width: width, height: height)
        )
        let filter = SCContentFilter(desktopIndependentWindow: target)
        let stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        try stream.addStreamOutput(sink, type: .screen, sampleHandlerQueue: sink.queue)
        try await stream.startCapture()

        self.stream = stream
        self.sink = sink
        self.configuration = configuration
        isRecording = true
        os_log(.info, log: log, "Recording %{public}@ at %dx%d", url.lastPathComponent, width, height)
    }

    /// Follow the terminal when it is resized mid-take.
    ///
    /// Only the crop moves. The video track's dimensions are fixed the moment writing
    /// starts, so a new size is refitted into them rather than changing them — which is
    /// why `scalesToFit` is on.
    func updateCrop(_ crop: CGRect) {
        guard isRecording, let stream, let configuration, crop.width > 1, crop.height > 1 else { return }
        guard configuration.sourceRect != crop else { return }
        configuration.sourceRect = crop
        Task { try? await stream.updateConfiguration(configuration) }
    }

    /// Stops and returns the finished file, or nil if nothing was ever captured.
    @discardableResult
    func stop() async -> URL? {
        guard isRecording, let stream, let sink else { return nil }
        isRecording = false
        self.stream = nil
        self.sink = nil
        self.configuration = nil

        try? await stream.stopCapture()
        let url = await sink.finish()
        lastRecording = url
        if let url {
            os_log(.info, log: log, "Wrote %{public}@", url.path)
        }
        return url
    }

    private static func even(_ value: CGFloat) -> Int {
        let rounded = Int(value.rounded())
        return max(2, rounded - (rounded % 2))
    }
}

// MARK: - Writer

/// Owns the asset writer and everything the capture callback touches.
///
/// Separate from `PanelRecorder` because the callback arrives on ScreenCaptureKit's
/// queue, not the main actor, and the writer must only ever be touched from that one
/// queue. Keeping the state here makes that a property of the type rather than a rule
/// to remember.
private final class Sink: NSObject, SCStreamOutput, @unchecked Sendable {
    let queue = DispatchQueue(label: "\(AppIdentity.slug).recorder")

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private var started = false
    private var wroteAnything = false
    private var lastSeen: CMTime = .invalid
    private let url: URL

    init(url: URL, width: Int, height: Int, bitrate: Int) throws {
        self.url = url
        try? FileManager.default.removeItem(at: url)
        writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: bitrate,
                // High profile, because Main's 8x8 transform restrictions show up as
                // ringing around glyph edges. Every target that plays H.264 at all
                // plays High.
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                // A keyframe a second: seeking in a clip someone was sent matters more
                // than the bytes, and a static terminal barely spends them.
                AVVideoMaxKeyFrameIntervalKey: 30,
            ],
        ])
        input.expectsMediaDataInRealTime = true
        writer.add(input)
        super.init()
        writer.startWriting()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid else { return }

        // Every frame counts towards how long the recording *ran*, including the ones
        // not worth writing. Without this the file ends at the last visual change, so
        // a recording that finishes on a still frame loses its tail — and one where
        // nothing happened at all comes out very nearly zero seconds long.
        let presentationTime = sampleBuffer.presentationTimeStamp
        if presentationTime.isNumeric { lastSeen = presentationTime }

        // ScreenCaptureKit keeps sending frames when nothing changed, flagged as idle
        // and carrying no new surface. Appending those would inflate the file with
        // duplicates; skipping them just leaves the previous frame on screen longer,
        // which is what actually happened.
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: raw) == .complete else { return }

        if !started {
            writer.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
            started = true
        }
        guard input.isReadyForMoreMediaData else { return }
        if input.append(sampleBuffer) { wroteAnything = true }
    }

    func finish() async -> URL? {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                guard started, wroteAnything else {
                    writer.cancelWriting()
                    continuation.resume(returning: nil)
                    return
                }
                if lastSeen.isNumeric { writer.endSession(atSourceTime: lastSeen) }
                input.markAsFinished()
                writer.finishWriting {
                    continuation.resume(returning: self.writer.status == .completed ? self.url : nil)
                }
            }
        }
    }
}
