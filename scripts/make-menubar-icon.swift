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

/// Thicken the alpha so the thinnest stroke still covers a whole pixel once drawn.
///
/// A template image is painted as one flat tint at the coverage its alpha reports, so
/// a stroke that lands half a pixel wide is not a thin black line — it is a grey one.
/// The mark is line art at 16pt beside system glyphs that are solid, so a mark left
/// untouched reads as disabled rather than as fine. Measured on the acoustic coupler:
/// its strokes are ~13px in the 1024 artwork, which is 0.7px at 16pt on a 2x display.
///
/// Dilation is done here, at the artwork's own resolution, because it is the last point
/// where a stroke is still many pixels wide and can be grown smoothly. The radius is
/// expressed in *drawn* pixels and converted, so it holds if the mark or the artwork
/// size changes. Fine detail merges — the coupler's coiled cord becomes a single mass —
/// which is what a 32px-tall drawing can carry anyway.
let drawnHeight = 32.0          // 16pt, on a 2x display: the smallest it is ever drawn
let growth = 0.6                // extra stroke width, in drawn pixels
let radius = Int((growth / 2 * (Double(box.height) / drawnHeight)).rounded())

/// Separable max filter. A square kernel, run once across and once down, costs r+r
/// passes per pixel instead of r², and on strokes this irregular the difference from a
/// circular kernel is not visible.
func dilated(_ image: CGImage, radius r: Int) -> CGImage? {
    guard r > 0 else { return image }
    let w = image.width, h = image.height
    var buffer = [UInt8](repeating: 0, count: w * h * 4)
    CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
        .draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

    var alpha = (0..<(w * h)).map { buffer[$0 * 4 + 3] }
    var pass = alpha
    for y in 0..<h {                                   // across
        for x in 0..<w {
            var peak: UInt8 = 0
            for k in max(0, x - r)...min(w - 1, x + r) where alpha[y * w + k] > peak {
                peak = alpha[y * w + k]
            }
            pass[y * w + x] = peak
        }
    }
    alpha = pass
    for x in 0..<w {                                   // and down
        for y in 0..<h {
            var peak: UInt8 = 0
            for k in max(0, y - r)...min(h - 1, y + r) where alpha[k * w + x] > peak {
                peak = alpha[k * w + x]
            }
            pass[y * w + x] = peak
        }
    }

    for i in 0..<(w * h) {
        buffer[i * 4] = 0; buffer[i * 4 + 1] = 0; buffer[i * 4 + 2] = 0
        buffer[i * 4 + 3] = pass[i]
    }
    return CGContext(data: &buffer, width: w, height: h, bitsPerComponent: 8,
                     bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage()
}

guard let thickened = dilated(cropped, radius: radius) else { exit(1) }

let aspect = box.width / box.height
let outputWidth = Int((CGFloat(outputHeight) * aspect).rounded())
guard let ctx = CGContext(data: nil, width: outputWidth, height: outputHeight,
                          bitsPerComponent: 8, bytesPerRow: 0,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.interpolationQuality = .high
ctx.draw(thickened, in: CGRect(x: 0, y: 0, width: outputWidth, height: outputHeight))

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
rep.size = NSSize(width: outputWidth, height: outputHeight)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: arguments[2]))

print("mark    : \(Int(box.width))x\(Int(box.height)) of \(w)x\(h) (aspect \(String(format: "%.2f", aspect)):1)")
print("dilated : radius \(radius)px — +\(String(format: "%.1f", growth))px of stroke at \(Int(drawnHeight))px tall")
print("wrote   : \(arguments[2]) at \(outputWidth)x\(outputHeight)")
