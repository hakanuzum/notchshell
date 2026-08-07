// Draw the backdrop for the installer window.
//
// Usage: swift scripts/make-dmg-background.swift <out-1x.png> <out-2x.png>
//
// The window is the whole installer: there is no wizard, no progress bar and nothing
// to click but a drag. So the backdrop has to say what to do on its own — a labelled
// slot on the left, an arrow, the Applications folder on the right.
//
// Both scales are emitted because Finder picks the backdrop's *pixel* size as its point
// size. A 1280x800 image would produce a 1280pt window rather than a crisp 640pt one;
// make-dmg.sh combines the two into a single multi-representation TIFF instead.

import AppKit

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    FileHandle.standardError.write("usage: make-dmg-background.swift <out-1x.png> <out-2x.png>\n".data(using: .utf8)!)
    exit(2)
}

/// Window content size in points. make-dmg.sh positions the two icons against these
/// same numbers, so the arrow lands between them rather than under one.
let width: CGFloat = 640
let height: CGFloat = 400

/// Where Finder is told to put the two icons, in the same coordinates.
let leftSlot = CGPoint(x: 170, y: 218)
let rightSlot = CGPoint(x: 470, y: 218)

// A light ground, not the brand's black. The app's own icon is a black squircle, and
// on a dark backdrop the two merge into one dark mass with the mark floating in it;
// against light grey the icon reads as a distinct object you can pick up and drag.
let ground = NSColor(srgbRed: 0xF6 / 255, green: 0xF8 / 255, blue: 0xFA / 255, alpha: 1)
let ink = NSColor(srgbRed: 0x1F / 255, green: 0x23 / 255, blue: 0x28 / 255, alpha: 1)
let muted = NSColor(srgbRed: 0x65 / 255, green: 0x6D / 255, blue: 0x76 / 255, alpha: 1)

/// The brand accent, darkened for the light ground. #00F888 on #F6F8FA is barely
/// above the background in luminance; the arrow has to be visible before it is on-brand.
let accent = NSColor(srgbRed: 0, green: 0.62, blue: 0.36, alpha: 1)

func render(scale: CGFloat) -> Data {
    let pixelsWide = Int(width * scale), pixelsHigh = Int(height * scale)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixelsWide, pixelsHigh: pixelsHigh,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setAllowsAntialiasing(true)

    ground.setFill()
    NSRect(x: 0, y: 0, width: width, height: height).fill()

    func draw(_ text: String, font: NSFont, colour: NSColor, centeredAt y: CGFloat, tracking: CGFloat = 0) {
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: colour, .paragraphStyle: style, .kern: tracking,
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(in: NSRect(x: 0, y: height - y - size.height, width: width, height: size.height),
                                withAttributes: attributes)
    }

    draw("Notchshell", font: .systemFont(ofSize: 30, weight: .semibold), colour: ink, centeredAt: 52)
    draw("Drag the app onto Applications to install", font: .systemFont(ofSize: 13, weight: .regular),
         colour: muted, centeredAt: 94, tracking: 0.2)

    // The arrow, spanning the gap between the two slots. Drawn as a stroked line with a
    // solid head so it stays legible at 1x, where a filled chevron closes up.
    let midY = height - leftSlot.y
    let start = CGPoint(x: leftSlot.x + 96, y: midY)
    let end = CGPoint(x: rightSlot.x - 96, y: midY)

    ctx.setStrokeColor(accent.withAlphaComponent(0.9).cgColor)
    ctx.setLineWidth(3)
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [10, 9])
    ctx.move(to: start)
    ctx.addLine(to: CGPoint(x: end.x - 14, y: end.y))
    ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])

    let head = NSBezierPath()
    head.move(to: NSPoint(x: end.x, y: end.y))
    head.line(to: NSPoint(x: end.x - 18, y: end.y + 11))
    head.line(to: NSPoint(x: end.x - 18, y: end.y - 11))
    head.close()
    accent.setFill()
    head.fill()

    // No captions over the slots: Finder already writes "Notchshell.app" and
    // "Applications" under the icons, and a second label above each just repeats it.

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

try render(scale: 1).write(to: URL(fileURLWithPath: arguments[1]))
try render(scale: 2).write(to: URL(fileURLWithPath: arguments[2]))
print("wrote \(arguments[1]) (\(Int(width))x\(Int(height))) and \(arguments[2]) (\(Int(width * 2))x\(Int(height * 2)))")
