import AVFoundation
import ImageIO
import UniformTypeIdentifiers
import CoreGraphics
import Foundation

/// Turns a finished recording into an animated GIF.
///
/// Built on ImageIO and AVFoundation, both of which ship with macOS, so a GIF costs no
/// dependency — the alternative was `agg`, which would have meant asking the user to
/// install a Rust toolchain to convert a file the app already had.
///
/// A GIF is the wrong format for a terminal in every way that matters — 256 colours,
/// no interframe compression worth the name, and a size that grows with duration far
/// faster than H.264. It is here because it is the one thing that plays inline
/// everywhere, and MP4 stays the default for that reason.
enum GIFExport {

    enum Failure: Error {
        case noFrames
        case cannotWrite
    }

    /// Deliberately coarse. Terminal output is mostly static between keystrokes, so
    /// frames past ~12fps cost size without showing anything new, and 900px is wide
    /// enough to read 80 columns.
    static let framesPerSecond: Double = 12
    /// Wide enough that 12pt glyphs survive. 900 was the first try and the text came
    /// out unreadable, which is the whole point of the file.
    static let maxWidth: CGFloat = 1600

    static func export(mp4 source: URL, to destination: URL) async throws {
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        guard duration > 0 else { throw Failure.noFrames }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // The recording is deliberately sparse — frames are only written when the
        // terminal changed — so most sampled instants fall between stored frames. With
        // zero tolerance those requests simply fail, and a four-second capture came out
        // as nine frames playing in under a second. Reaching backwards asks the right
        // question instead: what was on screen at this moment?
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .zero

        if let track = try await asset.loadTracks(withMediaType: .video).first {
            let size = try await track.load(.naturalSize)
            if size.width > maxWidth {
                let factor = maxWidth / size.width
                generator.maximumSize = CGSize(
                    width: (size.width * factor).rounded(),
                    height: (size.height * factor).rounded()
                )
            }
        }

        let frameCount = max(1, Int(duration * framesPerSecond))
        let times = (0..<frameCount).map {
            NSValue(time: CMTime(seconds: Double($0) / framesPerSecond, preferredTimescale: 600))
        }

        try? FileManager.default.removeItem(at: destination)
        guard let output = CGImageDestinationCreateWithURL(
            destination as CFURL, UTType.gif.identifier as CFString, frameCount, nil
        ) else { throw Failure.cannotWrite }

        CGImageDestinationSetProperties(output, [
            kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
        ] as CFDictionary)

        // Reaching backwards means consecutive samples often resolve to the same stored
        // frame. Writing each one would put dozens of identical images in the file for
        // every pause. Holding one image and lengthening its delay instead says the
        // same thing — this was on screen for a while — in one frame.
        var written = 0
        var held: (image: CGImage, time: CMTime, samples: Int)?

        func flush() {
            guard let held else { return }
            CGImageDestinationAddImage(output, held.image, delay(forSamples: held.samples))
            written += 1
        }

        for await result in generator.images(for: times.map(\.timeValue)) {
            guard case let .success(_, image, actual) = result else { continue }
            if var current = held, current.time == actual {
                current.samples += 1
                held = current
            } else {
                flush()
                held = (image, actual, 1)
            }
        }
        flush()

        guard written > 0, CGImageDestinationFinalize(output) else { throw Failure.noFrames }
    }

    /// GIF delays are stored in hundredths of a second, and many decoders quietly floor
    /// anything under 0.02s to 0.1s. Nothing here goes below that, but the clamp is
    /// where the assumption is written down.
    private static func delay(forSamples samples: Int) -> CFDictionary {
        let seconds = max(Double(samples) / framesPerSecond, 0.02)
        return [
            kCGImagePropertyGIFDictionary: [
                kCGImagePropertyGIFUnclampedDelayTime: seconds,
                kCGImagePropertyGIFDelayTime: seconds,
            ],
        ] as CFDictionary
    }

    /// `foo.mp4` → `foo.gif`, alongside the recording.
    static func destination(for mp4: URL) -> URL {
        mp4.deletingPathExtension().appendingPathExtension("gif")
    }
}
