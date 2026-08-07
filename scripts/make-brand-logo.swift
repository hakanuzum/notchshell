// Compose the brand artwork: the existing plate, with a new mark on it.
//
// Usage: swift scripts/make-brand-logo.swift <plate-source.png> <new-mark.png> <out.png>
//
// This is the step *before* make-icon.swift and make-menubar-icon.swift, both of which
// read the artwork this produces. Write to a temporary file and copy over
// Notchshell/Resources/branding/notchshell-logo-1024.png once it looks right — passing
// the same path as source and output reads a file it is midway through writing.
//
// The plate — the black disc with its notched shoulders — is lifted from the old
// artwork rather than redrawn, so the silhouette that is part of the brand survives
// the change of mark exactly. Only the mark is replaced.
//
// The new mark looks transparent but is not: it was exported as RGB with the editor's
// checkerboard baked in, so its alpha channel is opaque everywhere and keying on alpha
// yields a solid rectangle. The ink is pure black and the checker is two light greys,
// so coverage is read from darkness instead. It is painted in the brand accent
// sampled from the old artwork.

import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 4 else {
    FileHandle.standardError.write("usage: compose-logo.swift <old-logo.png> <new-mark.png> <out.png>\n".data(using: .utf8)!)
    exit(2)
}

let canvas = 1024

/// How much of the plate's width the mark spans. The old mark is a long skull that
/// reads horizontally; this one is a compact round fruit, and a round mark inside a
/// round plate needs more clearance than a wide one to avoid looking wedged in.
let markFill: CGFloat = 0.62

/// Brand accent, measured from the old artwork.
let accent = (r: 0.0, g: 248.0, b: 136.0)

func pixels(of path: String) -> ([UInt8], Int, Int) {
    guard let image = NSImage(contentsOfFile: path),
          let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        FileHandle.standardError.write("could not read \(path)\n".data(using: .utf8)!)
        exit(1)
    }
    let w = cg.width, h = cg.height
    var buffer = [UInt8](repeating: 0, count: w * h * 4)
    CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
        .draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (buffer, w, h)
}

func smoothstep(_ t: Double) -> Double {
    let c = min(1, max(0, t))
    return c * c * (3 - 2 * c)
}

// MARK: - The plate, as coverage

// Anything that is not the white page belongs to the plate. Taking the union of disc
// and old mark this way yields the disc silhouette itself, antialiased edge included,
// without having to know where the mark ended and the disc began.
let (old, ow, oh) = pixels(of: arguments[1])
guard ow == canvas, oh == canvas else {
    FileHandle.standardError.write("expected a \(canvas)x\(canvas) plate, got \(ow)x\(oh)\n".data(using: .utf8)!)
    exit(1)
}
var plate = [Double](repeating: 0, count: canvas * canvas)
for i in 0..<(canvas * canvas) {
    let r = Double(old[i * 4]), g = Double(old[i * 4 + 1]), b = Double(old[i * 4 + 2])
    // Distance from white, normalised over the range an antialiased edge sweeps.
    let d = ((255 - r) * (255 - r) + (255 - g) * (255 - g) + (255 - b) * (255 - b)).squareRoot()
    plate[i] = smoothstep((d - 20) / 60)
}

// Plate bounding box, so the mark can be centred on the plate rather than the canvas.
var pMinX = canvas, pMaxX = -1, pMinY = canvas, pMaxY = -1
for y in 0..<canvas {
    for x in 0..<canvas where plate[y * canvas + x] > 0.5 {
        if x < pMinX { pMinX = x }; if x > pMaxX { pMaxX = x }
        if y < pMinY { pMinY = y }; if y > pMaxY { pMaxY = y }
    }
}
let plateBox = CGRect(x: pMinX, y: pMinY, width: pMaxX - pMinX + 1, height: pMaxY - pMinY + 1)

// The old mark's extent, reported so the new fill fraction can be judged against it.
var mMinX = canvas, mMaxX = -1, mMinY = canvas, mMaxY = -1
for y in 0..<canvas {
    for x in 0..<canvas {
        let i = (y * canvas + x) * 4
        let r = Int(old[i]), g = Int(old[i + 1]), b = Int(old[i + 2])
        if max(r, max(g, b)) - min(r, min(g, b)) > 60 {
            if x < mMinX { mMinX = x }; if x > mMaxX { mMaxX = x }
            if y < mMinY { mMinY = y }; if y > mMaxY { mMaxY = y }
        }
    }
}

// MARK: - The new mark, as coverage

let (markPixels, mw, mh) = pixels(of: arguments[2])

/// Ink coverage at a pixel. The checker sits at luma 220 and above and the ink at 0,
/// so the ramp between them recovers the drawing's antialiased edge without letting
/// the lighter checker square register as faint ink.
func ink(_ x: Int, _ y: Int) -> Double {
    let i = (y * mw + x) * 4
    let luma = 0.299 * Double(markPixels[i]) + 0.587 * Double(markPixels[i + 1])
             + 0.114 * Double(markPixels[i + 2])
    return 1 - smoothstep((luma - 40) / 140)
}

var markBox = (minX: mw, maxX: -1, minY: mh, maxY: -1)
for y in 0..<mh {
    for x in 0..<mw where ink(x, y) > 0.15 {
        if x < markBox.minX { markBox.minX = x }; if x > markBox.maxX { markBox.maxX = x }
        if y < markBox.minY { markBox.minY = y }; if y > markBox.maxY { markBox.maxY = y }
    }
}
guard markBox.maxX >= markBox.minX else {
    FileHandle.standardError.write("the mark has no ink\n".data(using: .utf8)!)
    exit(1)
}
let cropW = markBox.maxX - markBox.minX + 1
let cropH = markBox.maxY - markBox.minY + 1

/// The mark, cropped to its ink and painted in the accent. Alpha is carried straight
/// across, so the drawing's own antialiasing survives.
func accentMark() -> CGImage? {
    var out = [UInt8](repeating: 0, count: cropW * cropH * 4)
    for y in 0..<cropH {
        for x in 0..<cropW {
            let dst = (y * cropW + x) * 4
            let a = ink(markBox.minX + x, markBox.minY + y)
            out[dst]     = UInt8((accent.r * a).rounded())
            out[dst + 1] = UInt8((accent.g * a).rounded())
            out[dst + 2] = UInt8((accent.b * a).rounded())
            out[dst + 3] = UInt8((a * 255).rounded())
        }
    }
    return CGContext(data: &out, width: cropW, height: cropH, bitsPerComponent: 8,
                     bytesPerRow: cropW * 4, space: CGColorSpaceCreateDeviceRGB(),
                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
}
guard let mark = accentMark() else { exit(1) }

// MARK: - Draw

guard let ctx = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8,
                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.interpolationQuality = .high

// White page, then the plate painted as black at its measured coverage. Building the
// plate as an image rather than a path keeps the original's antialiased rim.
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))

var plateRGBA = [UInt8](repeating: 0, count: canvas * canvas * 4)
for i in 0..<(canvas * canvas) {
    plateRGBA[i * 4 + 3] = UInt8((plate[i] * 255).rounded())   // black, premultiplied: rgb stays 0
}
if let plateImage = CGContext(data: &plateRGBA, width: canvas, height: canvas, bitsPerComponent: 8,
                              bytesPerRow: canvas * 4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage() {
    ctx.draw(plateImage, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
}

let maxSide = plateBox.width * markFill
let scale = min(maxSide / CGFloat(cropW), maxSide / CGFloat(cropH))
let drawSize = CGSize(width: CGFloat(cropW) * scale, height: CGFloat(cropH) * scale)
// Centre on the plate. plateBox is in top-left coordinates; the context is bottom-up.
let plateCentreX = plateBox.midX
let plateCentreY = CGFloat(canvas) - plateBox.midY
ctx.draw(mark, in: CGRect(x: plateCentreX - drawSize.width / 2,
                          y: plateCentreY - drawSize.height / 2,
                          width: drawSize.width, height: drawSize.height))

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
rep.size = NSSize(width: canvas, height: canvas)
try rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: arguments[3]))

print("plate     : \(Int(plateBox.width))x\(Int(plateBox.height)) at (\(pMinX),\(pMinY))")
print("old mark  : \(mMaxX - mMinX + 1)x\(mMaxY - mMinY + 1) — \(Int(Double(mMaxX - mMinX + 1) / Double(plateBox.width) * 100))% of plate width")
print("new mark  : \(cropW)x\(cropH) of \(mw)x\(mh) → drawn at \(Int(drawSize.width))x\(Int(drawSize.height)) — \(Int(markFill * 100))% of plate width")
print("wrote     : \(arguments[3])")
