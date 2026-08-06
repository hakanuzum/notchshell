// Build the menu-bar template image from the app artwork.
//
// Usage: swift scripts/make-menubar-icon.swift <source.png> <output.png>
//
// The menu bar is the app's most-seen surface — it is an LSUIElement app, so there is
// no Dock tile — and it renders template images as a flat tint that follows light and
// dark, the accent colour and the highlight state. Only alpha survives, so this
// discards colour entirely and keeps the mark's silhouette.
//
// Isolating that silhouette cannot be done by brightness: the artwork is a coloured
// mark on a black disc on a white page, and the antialiased rim between disc and page
// is mid-grey, which any luminance threshold picks up as if it were content. Chroma
// separates them cleanly instead — disc, page and rim are all neutral, and only the
// mark carries saturation.
//
// The output is deliberately larger than it will be drawn. AppKit downsamples a
// high-resolution representation smoothly, so one file stays crisp on both 1x and 2x
// displays without shipping a @2x variant.

import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write("usage: make-menubar-icon.swift <source.png> <output.png>\n".data(using: .utf8)!)
    exit(2)
}

/// Rendered height. Four times the ~16pt the menu bar draws it at, so 2x displays
/// still resample down rather than up.
let outputHeight = 64

guard let image = NSImage(contentsOfFile: arguments[1]),
      let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("could not read \(arguments[1])\n".data(using: .utf8)!)
    exit(1)
}

let w = source.width, h = source.height
var pixels = [UInt8](repeating: 0, count: w * h * 4)
CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
    .draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))

/// Black pixels whose alpha is the mark's chroma, plus the mark's bounding box.
func silhouette() -> (CGImage, CGRect)? {
    var out = [UInt8](repeating: 0, count: w * h * 4)
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w {
            let i = (y * w + x) * 4
            let r = Double(pixels[i]), g = Double(pixels[i+1]), b = Double(pixels[i+2])
            let chroma = max(r, max(g, b)) - min(r, min(g, b))
            let t = min(1.0, max(0.0, (chroma - 25) / 55))
            let alpha = t * t * (3 - 2 * t)   // smoothstep, so edges stay soft
            out[i] = 0; out[i+1] = 0; out[i+2] = 0
            out[i+3] = UInt8(alpha * 255)
            if alpha > 0.15 {
                if x < minX { minX = x }; if x > maxX { maxX = x }
                if y < minY { minY = y }; if y > maxY { maxY = y }
            }
        }
    }
    guard maxX >= minX, maxY >= minY else { return nil }
    guard let full = CGContext(data: &out, width: w, height: h, bitsPerComponent: 8,
                               bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
    else { return nil }
    return (full, CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
}

guard let (mask, box) = silhouette(), let cropped = mask.cropping(to: box) else {
    FileHandle.standardError.write("no saturated mark found in \(arguments[1])\n".data(using: .utf8)!)
    exit(1)
}

let aspect = box.width / box.height
let outputWidth = Int((CGFloat(outputHeight) * aspect).rounded())
guard let ctx = CGContext(data: nil, width: outputWidth, height: outputHeight,
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.interpolationQuality = .high
ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
rep.size = NSSize(width: outputWidth, height: outputHeight)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: arguments[2]))

print("mark    : \(Int(box.width))x\(Int(box.height)) of \(w)x\(h) (aspect \(String(format: "%.2f", aspect)):1)")
print("wrote   : \(arguments[2]) at \(outputWidth)x\(outputHeight)")
