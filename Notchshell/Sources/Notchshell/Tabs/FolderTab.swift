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
    /// The agent CLI running in this tab, if any.
    var agent: AgentKind?
    /// Something in this tab asked for attention while you were looking elsewhere.
    var wantsAttention: Bool = false
    /// Agents that have run in this tab's directory before. Only consulted when nothing
    /// is running now — `agent` owns the slot when it is set.
    var dormantAgents: [AgentKind] = []
    /// Run a resume command in this tab.
    var onResume: (String) -> Void = { _ in }
    let isActive: Bool
    /// True when the name has been renamed by hand, so the editor opens with it rather
    /// than blank.
    var hasCustomTitle: Bool = false
    /// Double-click puts the name into an editor. Bound rather than local so only one
    /// tab in the bar can be editing at a time.
    var isEditing: Binding<Bool> = .constant(false)
    let onSelect: () -> Void
    let onClose: () -> Void
    /// Nil clears a custom name and hands the tab back to its directory.
    var onRename: (String?) -> Void = { _ in }
    /// Middle-click-to-close is driven from a window-level monitor, which needs to know
    /// which tab the pointer is over.
    var onHover: (Bool) -> Void = { _ in }

    /// Tab height. The bar is as tall as the menu bar, which differs per display, so
    /// this is passed in rather than fixed.
    let height: CGFloat

    @State private var isHovered = false
    @State private var showingResume = false
    /// When the last tap landed, so a double-click can be recognised without asking
    /// SwiftUI to delay the single one. See the tap gesture below.
    @State private var lastTapAt: Date? = nil
    @State private var editText = ""
    @FocusState private var fieldFocused: Bool

    /// Set by the bar, which resolves it from the chrome setting.
    @Environment(\.colorScheme) private var colorScheme

    private var palette: FolderTabPalette { .of(colorScheme) }

    static let slant: CGFloat = 11
    /// Bar left visible below the tabs, so the tab reads as sitting *in* the bar.
    static let barMargin: CGFloat = 6

    private var shape: FolderTabShape {
        FolderTabShape(slant: Self.slant)
    }

    /// The unread mark. Ringed in the tab's own fill so it stays legible sitting on top
    /// of an agent badge, which is the usual case.
    ///
    /// Amber rather than the system accent, and rather than red. The accent is whatever
    /// the user picked in System Settings — on a machine set to graphite this mark came
    /// out a grey smudge quieter than the close button beside it, which inverts the
    /// hierarchy: the one thing you must not miss read as less urgent than a routine
    /// control. Red is spoken for by that close button. Amber is neither, and carries
    /// "waiting on you" on its own.
    private static let attentionColor = Color(red: 0.98, green: 0.65, blue: 0.13)

    @ViewBuilder private var attentionDot: some View {
        if wantsAttention {
            Circle()
                .fill(Self.attentionColor)
                .frame(width: 6, height: 6)
                .overlay(Circle().stroke(isActive ? palette.activeTop : palette.inactiveTop,
                                         lineWidth: 1))
                .offset(x: 2.5, y: -2.5)
        }
    }

    var body: some View {
        // 6, not 4: the name needs to sit clear of the mark on its left and the close
        // dot on its right, or the three read as one run of glyphs.
        HStack(spacing: 6) {
            if kind == .settings {
                Image(systemName: "gearshape").font(.system(size: 9))
            } else if kind == .help {
                Image(systemName: "questionmark.circle").font(.system(size: 9))
            } else if let agent {
                // Matches TrafficLightClose, so the two ends of the tab weigh the same.
                AgentBadge(agent: agent, size: TrafficLightClose.diameter)
                    .overlay(alignment: .topTrailing) { attentionDot }
            } else if let dormant = dormantAgents.first {
                // The same slot, faded, and clickable — the tab remembers what worked
                // here even though nothing is running.
                //
                // A `Button` here was close to unclickable, and neither reason was the
                // button's fault. The tab carries `onTapGesture(count: 2)` for renaming,
                // so SwiftUI holds every single tap back to see whether a second one
                // follows, and a child button has to win that wait; and a 12pt circle is
                // a small thing to hit twice. So: a high-priority tap that does not
                // queue behind the parent, over a hit area padded out to a comfortable
                // target. The padding is negative-margined back out so the tab does not
                // grow around it.
                AgentBadge(agent: dormant, size: TrafficLightClose.diameter,
                           isDormant: true)
                    .overlay(alignment: .topTrailing) { attentionDot }
                    .padding(6)
                    .contentShape(Rectangle())
                    .highPriorityGesture(TapGesture().onEnded { showingResume = true })
                    .padding(-6)
                    .popover(isPresented: $showingResume, arrowEdge: .bottom) {
                        AgentResumePopover(agents: dormantAgents) { command in
                            showingResume = false
                            onResume(command)
                        }
                    }
            } else if wantsAttention {
                // No badge to hang it on, so the dot takes the slot itself. The slot is
                // reserved either way, so nothing shifts when the mark clears.
                attentionDot
                    .frame(width: TrafficLightClose.diameter,
                           height: TrafficLightClose.diameter)
            }
            if isEditing.wrappedValue {
                TextField("Tab name", text: $editText, onCommit: commitRename)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(maxWidth: 120)
                    .focused($fieldFocused)
                    .onExitCommand { isEditing.wrappedValue = false }
                    .onChange(of: fieldFocused) {
                        if !fieldFocused { commitRename() }
                    }
                    .onAppear {
                        editText = hasCustomTitle ? title : ""
                        fieldFocused = true
                    }
            } else {
                Text(title)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 120)
            }
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
        .foregroundColor(isActive ? palette.activeText : palette.inactiveText)
        // The diagonals eat into the leading and trailing edges, so the label has to
        // clear them before its own padding starts.
        .padding(.horizontal, Self.slant + 5)
        .frame(height: height)
        .background(shape.fill(fill))
        .overlay(
            FolderTabOutline(slant: Self.slant)
                .stroke(palette.border, lineWidth: 0.75)
        )
        .contentShape(shape)
        // A single tap selects; a double tap renames — but *not* through
        // `onTapGesture(count: 2)`. Declaring a double-tap makes SwiftUI hold every
        // single tap until the double-tap window closes, so switching tabs answered a
        // system double-click interval late, every time. It read as the whole tab bar
        // being sluggish, and it made anything nested inside a tab — the resume badge —
        // feel like it needed several tries.
        //
        // So the tap fires immediately and the double is recognised from the clock
        // instead. Selecting a tab twice in quick succession is harmless, which is what
        // makes this safe: the first click of a double has already done its work by the
        // time the second arrives.
        .onTapGesture {
            let now = Date()
            let isDouble = lastTapAt.map {
                now.timeIntervalSince($0) < NSEvent.doubleClickInterval
            } ?? false
            lastTapAt = isDouble ? nil : now

            if isDouble && kind == .terminal {
                isEditing.wrappedValue = true
            } else {
                onSelect()
            }
        }
        .onHover { hovering in
            isHovered = hovering
            onHover(hovering)
        }
    }

    private func commitRename() {
        guard isEditing.wrappedValue else { return }
        onRename(editText.isEmpty ? nil : editText)
        isEditing.wrappedValue = false
    }

    private var fill: LinearGradient {
        if isActive {
            return LinearGradient(
                colors: [palette.activeTop, palette.activeBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        let top = isHovered ? palette.hoverTop : palette.inactiveTop
        let bottom = isHovered ? palette.hoverBottom : palette.inactiveBottom
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }
}

/// The bar reads as a folder divider only if it is clearly *recessed* against the tabs
/// it holds: bar furthest back, inactive tabs in front of it, the active tab furthest
/// forward. That ordering is the design; the greys are only one way of expressing it.
///
/// Dark is the same ordering rebuilt from the other end rather than the light values
/// inverted. Inverting them gives an active tab at 3% white — a hole in the bar rather
/// than a tab standing in front of it — so the dark set climbs 0.13 → 0.20 → 0.31 and
/// keeps the same three steps of separation the light set has.
struct FolderTabPalette {
    let bar: Color
    let barTopEdge: Color

    let activeTop: Color
    let activeBottom: Color

    let inactiveTop: Color
    let inactiveBottom: Color

    let hoverTop: Color
    let hoverBottom: Color

    let border: Color

    let activeText: Color
    let inactiveText: Color
    /// Icons sit on the bar itself, not on a tab, so they take the bar's contrast.
    let barIcon: Color
    /// A bar icon in its on state — the accent, so an open toggle reads as engaged.
    let barIconActive: Color

    static func of(_ scheme: ColorScheme) -> FolderTabPalette {
        scheme == .dark ? .dark : .light
    }

    private static func grey(_ white: CGFloat) -> Color {
        Color(nsColor: NSColor(calibratedWhite: white, alpha: 1.0))
    }

    static let light = FolderTabPalette(
        bar: grey(0.70),
        barTopEdge: Color.black.opacity(0.22),
        activeTop: grey(1.00),
        activeBottom: grey(0.97),
        inactiveTop: grey(0.91),
        inactiveBottom: grey(0.84),
        hoverTop: grey(0.96),
        hoverBottom: grey(0.90),
        border: Color.black.opacity(0.20),
        activeText: grey(0.13),
        inactiveText: grey(0.32),
        barIcon: grey(0.24),
        barIconActive: Color(nsColor: .controlAccentColor)
    )

    static let dark = FolderTabPalette(
        bar: grey(0.13),
        barTopEdge: Color.black.opacity(0.55),
        activeTop: grey(0.31),
        activeBottom: grey(0.27),
        inactiveTop: grey(0.20),
        inactiveBottom: grey(0.17),
        hoverTop: grey(0.25),
        hoverBottom: grey(0.22),
        border: Color.black.opacity(0.55),
        activeText: grey(0.97),
        inactiveText: grey(0.62),
        barIcon: grey(0.72),
        barIconActive: Color(nsColor: .controlAccentColor)
    )
}
