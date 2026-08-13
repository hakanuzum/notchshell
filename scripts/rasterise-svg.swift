// Rasterise an SVG mark into what make-brand-logo.swift reads: black ink on a white
// page, at whatever resolution you ask for.
//
// Usage: swift scripts/rasterise-svg.swift <in.svg> <out.png> [width]
//
// This is the step before make-brand-logo.swift when the new mark arrives as vector
// artwork. Render generously — 2048 is a good width for a mark that ends up ~740px on
// the plate — because make-brand-logo crops to the ink and rescales once, and a single
// downscale from a large render keeps the drawing's edges clean.
//
// Two things about the input, both of which silently produce the wrong thing:
//
// `fill="currentColor"` inherits its colour from the document that embeds the SVG, and
// there is no document here — so it is rewritten to black before rendering. Left alone,
// icon sets that use it render invisible.
//
// The page is painted white rather than left clear because coverage downstream is read
// from darkness. On a transparent page the untouched pixels are black in a premultiplied
// buffer, which reads as full ink, and the mark comes out a solid rectangle.

import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write(
        "usage: rasterise-svg.swift <in.svg> <out.png> [width]\n".data(using: .utf8)!)
    exit(2)
}
let width = arguments.count >= 4 ? (Int(arguments[3]) ?? 2048) : 2048

let source: String
do {
    source = try String(contentsOfFile: arguments[1], encoding: .utf8)
        .replacingOccurrences(of: "currentColor", with: "#000000")
} catch {
    FileHandle.standardError.write("could not read \(arguments[1])\n".data(using: .utf8)!)
    exit(1)
}

// NSImage reads SVG from data, but only when it can tell what the data is; a file
// extension is the cheapest way to say so.
let staged = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("rasterise-\(ProcessInfo.processInfo.processIdentifier).svg")
try source.write(to: staged, atomically: true, encoding: .utf8)
defer { try? FileManager.default.removeItem(at: staged) }

guard let image = NSImage(contentsOf: staged), image.size.width > 0, image.size.height > 0 else {
    FileHandle.standardError.write("could not render \(arguments[1]) as an image\n".data(using: .utf8)!)
    exit(1)
}
let box = image.size
let height = Int((CGFloat(width) * box.height / box.width).rounded())

guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                          bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.interpolationQuality = .high
ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
image.draw(in: NSRect(x: 0, y: 0, width: width, height: height),
           from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
rep.size = NSSize(width: width, height: height)
try rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: arguments[2]))

print("mark    : \(Int(box.width))x\(Int(box.height)) → \(width)x\(height)")
print("wrote   : \(arguments[2])")
