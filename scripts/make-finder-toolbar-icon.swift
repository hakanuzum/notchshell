// Build the Finder extension's toolbar/menu mark from the menu-bar template image.
//
// Usage: swift scripts/make-finder-toolbar-icon.swift <menubar.png> <output.png>
//
// The menu-bar artwork is the mark cropped to its own alpha — edge to edge, and taller
// than it is wide. Finder wants a square, and it wants the mark to sit inside that
// square rather than fill it: the toolbar draws the whole image scaled into the slot,
// so how big the mark *looks* beside a system glyph is decided here, by how much of its
// canvas it covers. Filling the canvas came out visibly heavier than everything next to
// it; 72% is where it sits level.
//
// The output is deliberately larger in pixels than it is ever drawn — the extension
// gives it a small logical size (see `FinderSync.swift`), which leaves the extra pixels
// as retina detail rather than as size.

import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(
        "usage: make-finder-toolbar-icon.swift <menubar.png> <output.png>\n".data(using: .utf8)!)
    exit(2)
}

/// Rendered edge, in pixels. Eight times the ~16pt Finder draws the mark at, so even a
/// 2x display resamples down.
let side = 128
/// Share of the canvas the mark's taller side covers.
let fill = 0.72

guard let image = NSImage(contentsOfFile: arguments[1]),
      let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("could not read \(arguments[1])\n".data(using: .utf8)!)
    exit(1)
}

let markHeight = (Double(side) * fill).rounded()
let markWidth = (markHeight * Double(source.width) / Double(source.height)).rounded()

guard let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8,
                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.interpolationQuality = .high
ctx.draw(source, in: CGRect(x: (Double(side) - markWidth) / 2,
                            y: (Double(side) - markHeight) / 2,
                            width: markWidth, height: markHeight))

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
rep.size = NSSize(width: side, height: side)
guard let data = rep.representation(using: .png, properties: [:]) else { exit(1) }
try data.write(to: URL(fileURLWithPath: arguments[2]))

print("mark    : \(Int(markWidth))x\(Int(markHeight)) inside \(side)x\(side)")
print("wrote   : \(arguments[2])")
