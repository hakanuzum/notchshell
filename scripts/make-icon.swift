// Build the macOS app icon from the source artwork.
//
// Usage: swift scripts/make-icon.swift <source.png> <output.icns> [--as-is]
//
// A 1024x1024 source is exactly the largest size macOS asks for, so nothing is ever
// scaled up and no detail is invented. Every size is resampled from the master in a
// single step; chaining downscales is what smears fine detail.
//
// With --as-is the artwork is emitted unchanged: use it when the source is already
// composed as an icon and you want it exactly as drawn.
//
// Without it, the artwork is fitted to Apple's icon grid — the content box is
// measured and the surrounding backdrop cropped away, the mark is centred inside an
// 824x824 body with corner radius 185.4, the backdrop is matted to transparent so a
// non-square mark does not carry bright wedges in its corners, and everything outside
// the squircle stays clear.

import AppKit

// MARK: - Arguments

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write("""
    usage: make-icon.swift <source.png> <output.icns> [--as-is]

      --as-is  emit the artwork unchanged at every size: no crop, no matte, no
               squircle. Use when the source is already composed as an icon.

    """.data(using: .utf8)!)
    exit(2)
}
let sourcePath = arguments[1]
let outputPath = arguments[2]
let asIs = arguments.dropFirst(3).contains("--as-is")

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

/// All the source pixels, once, so the passes below can share them.
func rgba(of cg: CGImage) -> [UInt8] {
    let w = cg.width, h = cg.height
    var pixels = [UInt8](repeating: 0, count: w * h * 4)
    CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
              bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
        .draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return pixels
}
let pixels = rgba(of: source)
let sourceWidth = source.width, sourceHeight = source.height

/// The artwork's own backdrop, taken from a corner. Defining "content" as anything
/// that differs from it handles a mark on white as well as a mark on black — the
/// first pass here only knew about bright-on-black and would have treated an entire
/// white canvas as content.
func backdrop() -> (r: Double, g: Double, b: Double) {
    (Double(pixels[0]), Double(pixels[1]), Double(pixels[2]))
}
let field = backdrop()

/// Bounding box of everything that differs from the backdrop, in CoreGraphics
/// coordinates (origin bottom-left).
func contentBounds(threshold: Double = 40) -> CGRect {
    var minX = sourceWidth, minY = sourceHeight, maxX = -1, maxY = -1
    for y in 0..<sourceHeight {
        for x in 0..<sourceWidth {
            let i = (y * sourceWidth + x) * 4
            let dr = Double(pixels[i]) - field.r
            let dg = Double(pixels[i+1]) - field.g
            let db = Double(pixels[i+2]) - field.b
            if (dr * dr + dg * dg + db * db).squareRoot() > threshold {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
    }
    guard maxX >= minX, maxY >= minY else {
        return CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight)
    }
    // The pixel buffer is drawn bottom-up, so these are already CG coordinates.
    return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
}

/// Content box padded for glow. Only needed when composing; --as-is skips the whole
/// analysis, which is also the expensive part.
func paddedContentBounds() -> CGRect {
    contentBounds()
        .insetBy(dx: -CGFloat(sourceWidth) * glowPadding, dy: -CGFloat(sourceHeight) * glowPadding)
        .intersection(CGRect(x: 0, y: 0, width: sourceWidth, height: sourceHeight))
}

/// The crop, with the export backdrop turned transparent.
///
/// A mark is rarely square: cropping a circular badge to its bounding box leaves the
/// backdrop in the corners, which would then sit inside the icon as four bright
/// wedges. Alpha ramps in over a distance range rather than switching at a threshold,
/// so a glow that fades into its own backdrop keeps a soft edge instead of a sawtooth.
func mattedCrop(_ box: CGRect) -> CGImage? {
    let x0 = Int(box.minX), y0 = Int(box.minY)
    let w = Int(box.width), h = Int(box.height)
    var out = [UInt8](repeating: 0, count: w * h * 4)
    let near = 20.0, far = 60.0
    for y in 0..<h {
        for x in 0..<w {
            let src = ((y0 + y) * sourceWidth + (x0 + x)) * 4
            let dst = (y * w + x) * 4
            let r = Double(pixels[src]), g = Double(pixels[src+1]), b = Double(pixels[src+2])
            let distance = ((r - field.r) * (r - field.r)
                          + (g - field.g) * (g - field.g)
                          + (b - field.b) * (b - field.b)).squareRoot()
            let t = min(1, max(0, (distance - near) / (far - near)))
            let alpha = t * t * (3 - 2 * t)   // smoothstep
            out[dst]   = UInt8(r * alpha)
            out[dst+1] = UInt8(g * alpha)
            out[dst+2] = UInt8(b * alpha)
            out[dst+3] = UInt8(alpha * 255)
        }
    }
    return CGContext(data: &out, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                     space: CGColorSpaceCreateDeviceRGB(),
                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
}

/// Colour to fill the squircle with: the one that dominates *inside* the mark, so the
/// icon body reads as the artwork's own field rather than as a plate behind it.
///
/// Not the corner pixel — that is the backdrop the mark was exported on, which for a
/// mark drawn on white would paint a white icon behind a black disc.
func dominantColour(in box: CGRect) -> CGColor {
    var histogram: [Int: Int] = [:]
    let x0 = Int(box.minX), x1 = Int(box.maxX), y0 = Int(box.minY), y1 = Int(box.maxY)
    for y in stride(from: y0, through: min(y1, sourceHeight - 1), by: 2) {
        for x in stride(from: x0, through: min(x1, sourceWidth - 1), by: 2) {
            let i = (y * sourceWidth + x) * 4
            // Quantise to 5 bits per channel so near-identical shades group together.
            let key = (Int(pixels[i]) >> 3) << 10 | (Int(pixels[i+1]) >> 3) << 5 | (Int(pixels[i+2]) >> 3)
            histogram[key, default: 0] += 1
        }
    }
    guard let (key, _) = histogram.max(by: { $0.value < $1.value }) else {
        return CGColor(gray: 0, alpha: 1)
    }
    let r = CGFloat((key >> 10) & 0x1f) / 31
    let g = CGFloat((key >> 5) & 0x1f) / 31
    let b = CGFloat(key & 0x1f) / 31
    return CGColor(red: r, green: g, blue: b, alpha: 1)
}
// MARK: - Compose the 1024 master

func renderMaster() -> CGImage? {
    let crop = paddedContentBounds()
    guard let cropped = mattedCrop(crop) else { return nil }
    let background = dominantColour(in: crop)

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

let master: CGImage
if asIs {
    master = source
} else {
    guard let composed = renderMaster() else {
        FileHandle.standardError.write("compose failed\n".data(using: .utf8)!)
        exit(1)
    }
    master = composed
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

print(asIs ? "mode           : as-is (unmodified artwork at every size)"
                 : "source content : \(Int(paddedContentBounds().width))x\(Int(paddedContentBounds().height)) cropped from \(sourceWidth)x\(sourceHeight)")
if !asIs { print("artwork fills  : \(Int(artworkFill * 100))% of the \(Int(bodySize))pt icon body") }
print("wrote          : \(outputURL.path)")
print("master preview : \(masterURL.path)")
