import SwiftUI

/// Manila-folder tab geometry, for a tab bar docked to the *bottom* of the panel.
///
/// The wide edge is the top one, because that is the edge that meets the terminal.
/// Browser tabs sit above their content and so flare downward; these hang below it
/// and flare upward. The shape is the vertical mirror of the familiar one, and
/// getting that backwards reads as a tooltip rather than a folder.
///
/// `slant` is the horizontal run of the diagonal. Tabs are laid out overlapping by
/// exactly that much, so one tab's right diagonal lands on its neighbour's left
/// diagonal and the pair share a single edge.
struct FolderTabShape: Shape {
    var slant: CGFloat = 11
    var cornerRadius: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        appendOutline(to: &path, in: rect)
        path.closeSubpath()
        return path
    }

    /// The three sides that are actually drawn. The top edge is left out: it is where
    /// the tab meets the terminal, and a line there would undo the join.
    func appendOutline(to path: inout Path, in rect: CGRect) {
        let w = rect.width
        let h = rect.height
        // Two slants plus two corner radii have to fit, however narrow the tab gets.
        let s = min(slant, w / 2)
        let r = min(cornerRadius, max(0, (w - 2 * s) / 2), h / 2)

        let topLeft = CGPoint(x: rect.minX, y: rect.minY)
        let bottomLeft = CGPoint(x: rect.minX + s, y: rect.maxY)
        let bottomRight = CGPoint(x: rect.maxX - s, y: rect.maxY)
        let topRight = CGPoint(x: rect.maxX, y: rect.minY)

        let downSlant = unitVector(from: topLeft, to: bottomLeft)
        let upSlant = unitVector(from: bottomRight, to: topRight)

        path.move(to: topLeft)
        path.addLine(to: CGPoint(
            x: bottomLeft.x - downSlant.dx * r,
            y: bottomLeft.y - downSlant.dy * r
        ))
        path.addQuadCurve(
            to: CGPoint(x: bottomLeft.x + r, y: bottomLeft.y),
            control: bottomLeft
        )
        path.addLine(to: CGPoint(x: bottomRight.x - r, y: bottomRight.y))
        path.addQuadCurve(
            to: CGPoint(x: bottomRight.x + upSlant.dx * r, y: bottomRight.y + upSlant.dy * r),
            control: bottomRight
        )
        path.addLine(to: topRight)
    }

    private func unitVector(from a: CGPoint, to b: CGPoint) -> CGVector {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let length = max(sqrt(dx * dx + dy * dy), 0.0001)
        return CGVector(dx: dx / length, dy: dy / length)
    }
}

/// `FolderTabShape` with the top edge left open, so stroking it draws a border down
/// one diagonal, along the bottom and back up the other — and never across the join.
struct FolderTabOutline: Shape {
    var slant: CGFloat = 11
    var cornerRadius: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        FolderTabShape(slant: slant, cornerRadius: cornerRadius)
            .appendOutline(to: &path, in: rect)
        return path
    }
}

/// One folder tab in the bottom bar.
struct FolderTab: View {
    let title: String
    let kind: Tab.TabKind
    let isActive: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    /// Middle-click-to-close is driven from a window-level monitor, which needs to know
    /// which tab the pointer is over.
    var onHover: (Bool) -> Void = { _ in }

    /// Tab height. The bar is as tall as the menu bar, which differs per display, so
    /// this is passed in rather than fixed.
    let height: CGFloat

    @State private var isHovered = false

    static let slant: CGFloat = 11
    /// Bar left visible below the tabs, so the tab reads as sitting *in* the bar.
    static let barMargin: CGFloat = 6

    private var shape: FolderTabShape {
        FolderTabShape(slant: Self.slant)
    }

    var body: some View {
        HStack(spacing: 4) {
            if kind == .settings {
                Image(systemName: "gearshape").font(.system(size: 9))
            } else if kind == .help {
                Image(systemName: "questionmark.circle").font(.system(size: 9))
            }
            Text(title)
                .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 120)
            // Reserve the slot rather than inserting on hover: a tab that changes
            // width under the pointer shifts every tab after it.
            TrafficLightClose(
                isTabHovered: isHovered,
                isTabActive: isActive,
                action: onClose
            )
            .opacity(isHovered || isActive ? 1 : 0)
            .allowsHitTesting(isHovered || isActive)
        }
        .foregroundColor(isActive ? FolderTabPalette.activeText : FolderTabPalette.inactiveText)
        // The diagonals eat into the leading and trailing edges, so the label has to
        // clear them before its own padding starts.
        .padding(.horizontal, Self.slant + 5)
        .frame(height: height)
        .background(shape.fill(fill))
        .overlay(
            FolderTabOutline(slant: Self.slant)
                .stroke(FolderTabPalette.border, lineWidth: 0.75)
        )
        .contentShape(shape)
        .onTapGesture(perform: onSelect)
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)
        }
    }

    private var fill: LinearGradient {
        if isActive {
            return LinearGradient(
                colors: [FolderTabPalette.activeTop, FolderTabPalette.activeBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        let top = isHovered ? FolderTabPalette.hoverTop : FolderTabPalette.inactiveTop
        let bottom = isHovered ? FolderTabPalette.hoverBottom : FolderTabPalette.inactiveBottom
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }
}

/// The bar reads as a folder divider only if it is clearly darker than the tabs it
/// holds. These values are the reference's relationship — mid-grey bar, light tabs,
/// near-white active — rather than its exact greys.
enum FolderTabPalette {
    static let bar = Color(nsColor: NSColor(calibratedWhite: 0.70, alpha: 1.0))
    static let barTopEdge = Color.black.opacity(0.22)

    static let activeTop = Color(nsColor: NSColor(calibratedWhite: 1.00, alpha: 1.0))
    static let activeBottom = Color(nsColor: NSColor(calibratedWhite: 0.97, alpha: 1.0))

    static let inactiveTop = Color(nsColor: NSColor(calibratedWhite: 0.91, alpha: 1.0))
    static let inactiveBottom = Color(nsColor: NSColor(calibratedWhite: 0.84, alpha: 1.0))

    static let hoverTop = Color(nsColor: NSColor(calibratedWhite: 0.96, alpha: 1.0))
    static let hoverBottom = Color(nsColor: NSColor(calibratedWhite: 0.90, alpha: 1.0))

    static let border = Color.black.opacity(0.20)

    static let activeText = Color(nsColor: NSColor(calibratedWhite: 0.13, alpha: 1.0))
    static let inactiveText = Color(nsColor: NSColor(calibratedWhite: 0.32, alpha: 1.0))
    /// Icons sit on the bar itself, not on a tab, so they need the darker bar's contrast.
    static let barIcon = Color(nsColor: NSColor(calibratedWhite: 0.24, alpha: 1.0))
}
