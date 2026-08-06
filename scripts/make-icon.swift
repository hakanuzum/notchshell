// Build the macOS app icon from the source artwork.
//
// Usage: swift scripts/make-icon.swift <source.png> <output.icns>
//
// The source is 1024x1024, which is exactly the largest size macOS asks for, so
// nothing is ever scaled up and no detail is invented. What this does do is fit the
// artwork to the medium:
//
//   - crops the dead margin (the mark fills ~61% x ~46% of its canvas and sits 113px
//     above centre, so used as-is it would read small and top-heavy),
//   - centres it inside the standard macOS icon body — 824x824 within a 1024 canvas,
//     corner radius 185.4 — so it sits on the same grid as every other Dock icon,
//   - keeps everything outside that shape transparent, because a full-bleed square
//     is the one thing a macOS icon must not be,
//   - renders each size in a single step from the 1024 master rather than chaining
//     downscales, which is what smears fine detail.

import AppKit

// MARK: - Arguments

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write("usage: make-icon.swift <source.png> <output.icns>\n".data(using: .utf8)!)
    exit(2)
}
let sourcePath = arguments[1]
let outputPath = arguments[2]

// MARK: - Geometry (Apple's macOS icon grid)

let canvas: CGFloat = 1024
let bodySize: CGFloat = 824
let cornerRadius: CGFloat = 185.4
let bodyOrigin = (canvas - bodySize) / 2
let body = CGRect(x: bodyOrigin, y: bodyOrigin, width: bodySize, height: bodySize)

/// How much of the body the artwork fills. Below 1 so the mark has the breathing
/// room Apple's grid expects rather than touching the squircle edge.
let artworkFill: CGFloat = 0.86

/// Padding added around the measured content box, as a fraction of its size. The
/// neon glow fades below the detection threshold, so a hard crop would clip it.
let glowPadding: CGFloat = 0.06

// MARK: - Load

guard let image = NSImage(contentsOfFile: sourcePath),
      let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("could not read \(sourcePath)\n".data(using: .utf8)!)
    exit(1)
}

// MARK: - Measure the content

/// Bounding box of everything meaningfully brighter than the black field, in CoreGraphics
/// coordinates (origin bottom-left).
func contentBounds(of cg: CGImage, threshold: Double = 28) -> CGRect {
    let w = cg.width, h = cg.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                             bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return CGRect(x: 0, y: 0, width: w, height: h)
    }
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w {
            let i = (y * w + x) * 4
            let luma = 0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i+1]) + 0.0722 * Double(pixels[i+2])
            if luma > threshold {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
    }
    guard maxX >= minX, maxY >= minY else {
        return CGRect(x: 0, y: 0, width: w, height: h)
    }
    // The pixel buffer is drawn bottom-up, so these are already CG coordinates.
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

var crop = contentBounds(of: source)
crop = crop.insetBy(dx: -crop.width * glowPadding, dy: -crop.height * glowPadding)
    .intersection(CGRect(x: 0, y: 0, width: source.width, height: source.height))

guard let cropped = source.cropping(to: crop) else {
    FileHandle.standardError.write("crop failed\n".data(using: .utf8)!)
    exit(1)
}

/// Background colour, sampled from a corner of the source so the squircle matches the
/// artwork's own field instead of a guessed black.
func cornerColour(of cg: CGImage) -> CGColor {
    var pixel = [UInt8](repeating: 0, count: 4)
    let ctx = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    return CGColor(red: CGFloat(pixel[0]) / 255, green: CGFloat(pixel[1]) / 255,
                   blue: CGFloat(pixel[2]) / 255, alpha: 1)
}
let background = cornerColour(of: source)

// MARK: - Compose the 1024 master

func renderMaster() -> CGImage? {
    guard let ctx = CGContext(data: nil, width: Int(canvas), height: Int(canvas),
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high

    let squircle = CGPath(roundedRect: body, cornerWidth: cornerRadius, cornerHeight: cornerRadius,
                          transform: nil)
    ctx.addPath(squircle)
    ctx.setFillColor(background)
    ctx.fillPath()

    // Clip so the artwork's own black field cannot spill past the rounded corners.
    ctx.addPath(squircle)
    ctx.clip()

    let maxSide = bodySize * artworkFill
    let scale = min(maxSide / CGFloat(cropped.width), maxSide / CGFloat(cropped.height))
    let drawSize = CGSize(width: CGFloat(cropped.width) * scale, height: CGFloat(cropped.height) * scale)
    let drawRect = CGRect(x: body.midX - drawSize.width / 2,
                          y: body.midY - drawSize.height / 2,
                          width: drawSize.width, height: drawSize.height)
    ctx.draw(cropped, in: drawRect)

    return ctx.makeImage()
}

guard let master = renderMaster() else {
    FileHandle.standardError.write("compose failed\n".data(using: .utf8)!)
    exit(1)
}

// MARK: - Emit the iconset

func write(_ cg: CGImage, to url: URL) throws {
    let rep = NSBitmapImageRep(cgImage: cg)
    rep.size = NSSize(width: cg.width, height: cg.height)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "make-icon", code: 1)
    }
    try data.write(to: url)
}

/// Resample the master to `side` in one step. Chaining downscales is what turns fine
/// detail (the tube joints, the lightning) into mush.
func resized(_ cg: CGImage, to side: Int) -> CGImage? {
    guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
    return ctx.makeImage()
}

let outputURL = URL(fileURLWithPath: outputPath)
let iconset = outputURL.deletingPathExtension().appendingPathExtension("iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

// name -> pixel side. iconutil requires exactly these.
let variants: [(String, Int)] = [
    ("icon_16x16.png", 16),      ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),      ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),   ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),   ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),   ("icon_512x512@2x.png", 1024),
]

for (name, side) in variants {
    guard let scaled = side == Int(canvas) ? master : resized(master, to: side) else {
        FileHandle.standardError.write("resize to \(side) failed\n".data(using: .utf8)!)
        exit(1)
    }
    try write(scaled, to: iconset.appendingPathComponent(name))
}

// Keep the composed master beside the source artwork, not beside the .icns — the
// Resources root is copied into the bundle and has no use for a preview file.
let masterURL = URL(fileURLWithPath: sourcePath)
    .deletingLastPathComponent()
    .appendingPathComponent("notchshell-icon-master.png")
try write(master, to: masterURL)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", outputURL.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed\n".data(using: .utf8)!)
    exit(1)
}
try? FileManager.default.removeItem(at: iconset)

print("source content : \(Int(crop.width))x\(Int(crop.height)) cropped from \(source.width)x\(source.height)")
print("artwork fills  : \(Int(artworkFill * 100))% of the \(Int(bodySize))pt icon body")
print("wrote          : \(outputURL.path)")
print("master preview : \(masterURL.path)")
