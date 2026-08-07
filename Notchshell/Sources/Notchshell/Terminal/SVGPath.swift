import CoreGraphics
import SwiftUI

/// Turns an SVG `d` attribute into a `Path`.
///
/// Small on purpose: it exists so the agent marks can be vectors rather than bitmaps —
/// one string per icon, sharp at any size, tinted by whatever foreground style the tab
/// is using. It covers the whole path grammar because `simple-icons` uses all of it,
/// arcs included.
enum SVGPath {
    /// Parse `data` in its own `viewBox` and scale it to fit `rect`, preserving aspect
    /// ratio and centring what is left over.
    static func path(from data: String, fitting rect: CGRect, viewBox: CGSize = CGSize(width: 24, height: 24)) -> Path {
        let raw = parse(data)
        guard viewBox.width > 0, viewBox.height > 0 else { return raw }
        let scale = min(rect.width / viewBox.width, rect.height / viewBox.height)
        let size = CGSize(width: viewBox.width * scale, height: viewBox.height * scale)
        let transform = CGAffineTransform(
            translationX: rect.minX + (rect.width - size.width) / 2,
            y: rect.minY + (rect.height - size.height) / 2
        )
        .scaledBy(x: scale, y: scale)
        return raw.applying(transform)
    }

    /// Parse in the source coordinate system, untransformed.
    static func parse(_ data: String) -> Path {
        var scanner = Scanner(data)
        var path = Path()

        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        /// Reflected by `S`/`s` and `T`/`t`. Nil unless the previous command was of the
        /// matching kind — the spec says the control point coincides with the current
        /// point otherwise.
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?

        while let command = scanner.nextCommand() {
            let relative = command.isLowercase
            var isFirstRepetition = true

            repeat {
                // A `moveto` with extra coordinate pairs continues as `lineto`; every
                // other command simply repeats.
                let effective: Character
                if !isFirstRepetition, command == "M" { effective = "L" }
                else if !isFirstRepetition, command == "m" { effective = "l" }
                else { effective = command }

                func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                    relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
                }

                switch Character(effective.lowercased()) {
                case "m":
                    guard let x = scanner.nextNumber(), let y = scanner.nextNumber() else { return path }
                    current = point(x, y)
                    subpathStart = current
                    path.move(to: current)
                    lastCubicControl = nil
                    lastQuadControl = nil

                case "l":
                    guard let x = scanner.nextNumber(), let y = scanner.nextNumber() else { return path }
                    current = point(x, y)
                    path.addLine(to: current)
                    lastCubicControl = nil
                    lastQuadControl = nil

                case "h":
                    guard let x = scanner.nextNumber() else { return path }
                    current = CGPoint(x: relative ? current.x + x : x, y: current.y)
                    path.addLine(to: current)
                    lastCubicControl = nil
                    lastQuadControl = nil

                case "v":
                    guard let y = scanner.nextNumber() else { return path }
                    current = CGPoint(x: current.x, y: relative ? current.y + y : y)
                    path.addLine(to: current)
                    lastCubicControl = nil
                    lastQuadControl = nil

                case "c":
                    guard let x1 = scanner.nextNumber(), let y1 = scanner.nextNumber(),
                          let x2 = scanner.nextNumber(), let y2 = scanner.nextNumber(),
                          let x = scanner.nextNumber(), let y = scanner.nextNumber() else { return path }
                    let control1 = point(x1, y1)
                    let control2 = point(x2, y2)
                    current = point(x, y)
                    path.addCurve(to: current, control1: control1, control2: control2)
                    lastCubicControl = control2
                    lastQuadControl = nil

                case "s":
                    guard let x2 = scanner.nextNumber(), let y2 = scanner.nextNumber(),
                          let x = scanner.nextNumber(), let y = scanner.nextNumber() else { return path }
                    let control1 = reflect(lastCubicControl, about: current)
                    let control2 = point(x2, y2)
                    current = point(x, y)
                    path.addCurve(to: current, control1: control1, control2: control2)
                    lastCubicControl = control2
                    lastQuadControl = nil

                case "q":
                    guard let x1 = scanner.nextNumber(), let y1 = scanner.nextNumber(),
                          let x = scanner.nextNumber(), let y = scanner.nextNumber() else { return path }
                    let control = point(x1, y1)
                    current = point(x, y)
                    path.addQuadCurve(to: current, control: control)
                    lastQuadControl = control
                    lastCubicControl = nil

                case "t":
                    guard let x = scanner.nextNumber(), let y = scanner.nextNumber() else { return path }
                    let control = reflect(lastQuadControl, about: current)
                    current = point(x, y)
                    path.addQuadCurve(to: current, control: control)
                    lastQuadControl = control
                    lastCubicControl = nil

                case "a":
                    guard let rx = scanner.nextNumber(), let ry = scanner.nextNumber(),
                          let rotation = scanner.nextNumber(),
                          let largeArc = scanner.nextFlag(), let sweep = scanner.nextFlag(),
                          let x = scanner.nextNumber(), let y = scanner.nextNumber() else { return path }
                    let end = point(x, y)
                    appendArc(
                        to: &path, from: current, to: end,
                        rx: rx, ry: ry, rotationDegrees: rotation,
                        largeArc: largeArc, sweep: sweep
                    )
                    current = end
                    lastCubicControl = nil
                    lastQuadControl = nil

                case "z":
                    path.closeSubpath()
                    current = subpathStart
                    lastCubicControl = nil
                    lastQuadControl = nil

                default:
                    return path
                }

                isFirstRepetition = false
                // `z` takes no parameters, so it never repeats.
            } while Character(command.lowercased()) != "z" && scanner.peekIsNumber()
        }

        return path
    }

    private static func reflect(_ control: CGPoint?, about point: CGPoint) -> CGPoint {
        guard let control else { return point }
        return CGPoint(x: 2 * point.x - control.x, y: 2 * point.y - control.y)
    }

    // MARK: - Arcs

    /// Endpoint parameterisation → centre parameterisation → cubic segments, following
    /// the implementation notes in the SVG specification (F.6.5).
    private static func appendArc(
        to path: inout Path,
        from start: CGPoint, to end: CGPoint,
        rx rxIn: CGFloat, ry ryIn: CGFloat,
        rotationDegrees: CGFloat, largeArc: Bool, sweep: Bool
    ) {
        // "If the endpoints are identical, this is equivalent to omitting the segment";
        // a zero radius degenerates to a straight line.
        guard start != end else { return }
        var rx = abs(rxIn)
        var ry = abs(ryIn)
        guard rx > 0, ry > 0 else {
            path.addLine(to: end)
            return
        }

        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        let dx2 = (start.x - end.x) / 2
        let dy2 = (start.y - end.y) / 2
        let x1p = cosPhi * dx2 + sinPhi * dy2
        let y1p = -sinPhi * dx2 + cosPhi * dy2

        // Scale the radii up if they are too small to span the endpoints (F.6.6).
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let scale = sqrt(lambda)
            rx *= scale
            ry *= scale
        }

        let sign: CGFloat = largeArc == sweep ? -1 : 1
        let numerator = max(0, rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p)
        let denominator = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        let coefficient = denominator == 0 ? 0 : sign * sqrt(numerator / denominator)
        let cxp = coefficient * rx * y1p / ry
        let cyp = -coefficient * ry * x1p / rx

        let cx = cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2

        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy
            let length = sqrt(ux * ux + uy * uy) * sqrt(vx * vx + vy * vy)
            guard length > 0 else { return 0 }
            let value = acos(min(1, max(-1, dot / length)))
            return (ux * vy - uy * vx) < 0 ? -value : value
        }

        let startAngle = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var sweepAngle = angle(
            (x1p - cxp) / rx, (y1p - cyp) / ry,
            (-x1p - cxp) / rx, (-y1p - cyp) / ry
        )
        if !sweep, sweepAngle > 0 { sweepAngle -= 2 * .pi }
        if sweep, sweepAngle < 0 { sweepAngle += 2 * .pi }

        // A cubic approximates a circular arc well up to about 90°; beyond that the
        // error becomes visible, so the sweep is split.
        let segments = max(1, Int(ceil(abs(sweepAngle) / (.pi / 2))))
        let delta = sweepAngle / CGFloat(segments)
        let alpha = 4.0 / 3.0 * tan(delta / 4)

        var theta = startAngle
        for _ in 0..<segments {
            let next = theta + delta
            let cosTheta = cos(theta), sinTheta = sin(theta)
            let cosNext = cos(next), sinNext = sin(next)

            func map(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                CGPoint(
                    x: cosPhi * rx * x - sinPhi * ry * y + cx,
                    y: sinPhi * rx * x + cosPhi * ry * y + cy
                )
            }

            let end2 = map(cosNext, sinNext)
            let control1 = map(cosTheta - alpha * sinTheta, sinTheta + alpha * cosTheta)
            let control2 = map(cosNext + alpha * sinNext, sinNext - alpha * cosNext)
            path.addCurve(to: end2, control1: control1, control2: control2)
            theta = next
        }
    }

    // MARK: - Tokeniser

    /// Numbers in path data run together — `1.5.3` is two of them, and `-` doubles as a
    /// separator — so this cannot be a `split` on whitespace.
    private struct Scanner {
        private let characters: [Character]
        private var index: Int = 0

        init(_ string: String) {
            characters = Array(string)
        }

        private mutating func skipSeparators() {
            while index < characters.count, characters[index] == " " || characters[index] == ","
                || characters[index] == "\n" || characters[index] == "\t" || characters[index] == "\r" {
                index += 1
            }
        }

        mutating func nextCommand() -> Character? {
            skipSeparators()
            guard index < characters.count else { return nil }
            let character = characters[index]
            guard character.isLetter else { return nil }
            index += 1
            return character
        }

        mutating func peekIsNumber() -> Bool {
            skipSeparators()
            guard index < characters.count else { return false }
            let character = characters[index]
            return character.isNumber || character == "-" || character == "+" || character == "."
        }

        mutating func nextNumber() -> CGFloat? {
            skipSeparators()
            guard index < characters.count else { return nil }
            var text = ""
            if characters[index] == "-" || characters[index] == "+" {
                text.append(characters[index])
                index += 1
            }
            var sawDot = false
            while index < characters.count {
                let character = characters[index]
                if character.isNumber {
                    text.append(character)
                    index += 1
                } else if character == ".", !sawDot {
                    sawDot = true
                    text.append(character)
                    index += 1
                } else if character == "e" || character == "E" {
                    // Exponent, with its own optional sign.
                    var lookahead = index + 1
                    if lookahead < characters.count,
                       characters[lookahead] == "-" || characters[lookahead] == "+" {
                        lookahead += 1
                    }
                    guard lookahead < characters.count, characters[lookahead].isNumber else { break }
                    text.append(contentsOf: characters[index..<lookahead])
                    index = lookahead
                    while index < characters.count, characters[index].isNumber {
                        text.append(characters[index])
                        index += 1
                    }
                    break
                } else {
                    break
                }
            }
            guard let value = Double(text) else { return nil }
            return CGFloat(value)
        }

        /// Arc flags are single digits and may be written without any separator, as in
        /// `a1 1 0 0117 5` — reading them as ordinary numbers would swallow the
        /// coordinate that follows.
        mutating func nextFlag() -> Bool? {
            skipSeparators()
            guard index < characters.count else { return nil }
            let character = characters[index]
            guard character == "0" || character == "1" else { return nil }
            index += 1
            return character == "1"
        }
    }
}

/// One agent mark, as a `Shape` so it fills with the surrounding foreground style and
/// stays sharp at any size.
struct AgentGlyphShape: Shape {
    let pathData: String

    func path(in rect: CGRect) -> Path {
        SVGPath.path(from: pathData, fitting: rect)
    }
}
