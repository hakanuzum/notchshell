// Encode a directory of PNG frames as an H.264 MP4.
//
// Usage: swift scripts/make-mp4.swift <frames-dir> <out.mp4> [--fps N] [--width N]
//
// Frames are taken in sorted filename order, so capture them zero-padded.
//
// Bitrate is set explicitly rather than left to AVFoundation, whose default is tuned
// for camera footage where a smeared edge costs nothing. A terminal is high-contrast
// text on a flat field, and the default turns 12pt glyphs into mush.

import AVFoundation
import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write("usage: make-mp4.swift <frames-dir> <out.mp4> [--fps N] [--width N]\n".data(using: .utf8)!)
    exit(2)
}
let framesDir = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

func option(_ name: String, default fallback: Int) -> Int {
    guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count,
          let value = Int(arguments[i + 1]) else { return fallback }
    return value
}
let fps = max(1, option("--fps", default: 14))
let targetWidth = option("--width", default: 1600)

let frames = try FileManager.default
    .contentsOfDirectory(at: framesDir, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension.lowercased() == "png" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

guard let first = frames.first,
      let probe = NSImage(contentsOf: first)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("no readable PNG frames in \(framesDir.path)\n".data(using: .utf8)!)
    exit(1)
}

// H.264 wants even dimensions; an odd width silently fails to encode on some configs.
func even(_ n: Int) -> Int { n % 2 == 0 ? n : n - 1 }
let width = even(min(targetWidth, probe.width))
let height = even(Int((Double(probe.height) * Double(width) / Double(probe.width)).rounded()))

try? FileManager.default.removeItem(at: outputURL)
let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: width * height * 8,
        AVVideoMaxKeyFrameIntervalKey: fps * 2,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
    ],
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
    ])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

func buffer(from image: CGImage) -> CVPixelBuffer? {
    guard let pool = adaptor.pixelBufferPool else { return nil }
    var pixelBuffer: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
          let output = pixelBuffer else { return nil }
    CVPixelBufferLockBaseAddress(output, [])
    defer { CVPixelBufferUnlockBaseAddress(output, []) }
    guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(output),
                              width: width, height: height, bitsPerComponent: 8,
                              bytesPerRow: CVPixelBufferGetBytesPerRow(output),
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return output
}

var index = 0
let queue = DispatchQueue(label: "make-mp4")
let done = DispatchSemaphore(value: 0)

input.requestMediaDataWhenReady(on: queue) {
    while input.isReadyForMoreMediaData {
        guard index < frames.count else {
            input.markAsFinished()
            done.signal()
            return
        }
        let url = frames[index]
        defer { index += 1 }
        guard let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let pixels = buffer(from: image) else { continue }
        adaptor.append(pixels, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: CMTimeScale(fps)))
    }
}

done.wait()
let finished = DispatchSemaphore(value: 0)
writer.finishWriting { finished.signal() }
finished.wait()

guard writer.status == .completed else {
    FileHandle.standardError.write("encode failed: \(writer.error?.localizedDescription ?? "unknown")\n".data(using: .utf8)!)
    exit(1)
}

let bytes = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
print("wrote \(outputURL.path): \(frames.count) frames, \(width)x\(height) at \(fps)fps, \(bytes / 1024) KB")
