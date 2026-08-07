// Assemble a directory of PNG frames into an animated GIF.
//
// Usage: swift scripts/make-gif.swift <frames-dir> <out.gif> [--fps N] [--width N]
//
// Frames are taken in sorted filename order, so capture them zero-padded. The width
// cap is applied before palletising: a GIF is 256 colours per frame, and downsampling
// first is what keeps a terminal's antialiased glyphs from banding.

import AppKit
import ImageIO
import UniformTypeIdentifiers

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write("usage: make-gif.swift <frames-dir> <out.gif> [--fps N] [--width N]\n".data(using: .utf8)!)
    exit(2)
}
let framesDir = URL(fileURLWithPath: arguments[1])
let outputURL = URL(fileURLWithPath: arguments[2])

func option(_ name: String, default fallback: Int) -> Int {
    guard let i = arguments.firstIndex(of: name), i + 1 < arguments.count,
          let value = Int(arguments[i + 1]) else { return fallback }
    return value
}
let fps = max(1, option("--fps", default: 12))
let maxWidth = option("--width", default: 1200)

let frames = try FileManager.default
    .contentsOfDirectory(at: framesDir, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension.lowercased() == "png" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }

guard !frames.isEmpty else {
    FileHandle.standardError.write("no PNG frames in \(framesDir.path)\n".data(using: .utf8)!)
    exit(1)
}

guard let destination = CGImageDestinationCreateWithURL(
    outputURL as CFURL, UTType.gif.identifier as CFString, frames.count, nil) else {
    FileHandle.standardError.write("could not create \(outputURL.path)\n".data(using: .utf8)!)
    exit(1)
}

CGImageDestinationSetProperties(destination, [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0],
] as CFDictionary)

let frameProperties = [
    kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 1.0 / Double(fps)],
] as CFDictionary

func scaled(_ image: CGImage) -> CGImage {
    guard image.width > maxWidth else { return image }
    let height = Int((Double(image.height) * Double(maxWidth) / Double(image.width)).rounded())
    guard let ctx = CGContext(data: nil, width: maxWidth, height: height, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return image }
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: maxWidth, height: height))
    return ctx.makeImage() ?? image
}

var written = 0
for frame in frames {
    guard let source = CGImageSourceCreateWithURL(frame as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { continue }
    CGImageDestinationAddImage(destination, scaled(image), frameProperties)
    written += 1
}

guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write("failed to write \(outputURL.path)\n".data(using: .utf8)!)
    exit(1)
}

let bytes = (try? FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int) ?? 0
print("wrote \(outputURL.path): \(written) frames at \(fps)fps, \(bytes / 1024) KB")
