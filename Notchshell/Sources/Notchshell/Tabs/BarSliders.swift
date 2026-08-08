import SwiftUI

/// A vertical slider, because the controls that open it hang off a bar at the bottom
/// of the screen and a horizontal popover would run off the edge.
///
/// Not a rotated `Slider`: rotation leaves the hit area in the pre-rotation orientation,
/// so the thing you can drag is not the thing you can see.
struct VerticalSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    /// `true` while dragging, `false` once on release. Callers throttle on the first
    /// and always act on the second.
    var onEditingChanged: (Bool) -> Void = { _ in }

    var height: CGFloat = 132
    var trackWidth: CGFloat = 7
    /// The knob is a capsule elongated *along* the track, not a circle. Turned
    /// vertical that means taller than it is wide — a circle is the one shape that
    /// looks identical whichever way the slider runs, which is why it reads as wrong.
    var knobWidth: CGFloat = 21
    var knobHeight: CGFloat = 29

    private var fraction: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return min(max((value - range.lowerBound) / span, 0), 1)
    }

    /// Distance the knob's centre can travel. The knob has to stay inside the track,
    /// so the ends are half a knob short of the full height.
    private var travel: CGFloat { max(height - knobHeight, 1) }

    private var knobCentreY: CGFloat {
        knobHeight / 2 + travel * (1 - fraction)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(Self.trackColor)
                .frame(width: trackWidth, height: height)

            // Filled portion runs from the knob down, so "more" reads as "fuller".
            Capsule()
                .fill(Self.fillColor)
                .frame(width: trackWidth, height: max(height - knobCentreY, 0))
                .offset(y: knobCentreY)

            Capsule()
                .fill(Color.white)
                .shadow(color: .black.opacity(0.22), radius: 3, y: 1.5)
                .frame(width: knobWidth, height: knobHeight)
                .offset(y: knobCentreY - knobHeight / 2)
        }
        .frame(width: max(knobWidth, trackWidth) + 14, height: height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    setFromPoint(drag.location.y)
                    onEditingChanged(true)
                }
                .onEnded { drag in
                    setFromPoint(drag.location.y)
                    onEditingChanged(false)
                }
        )
    }

    private static let trackColor = Color(nsColor: NSColor(calibratedWhite: 0.89, alpha: 1))
    /// A literal blue rather than `controlAccentColor`: a dynamic system colour stored
    /// in a `static let` resolves once, outside any appearance context, and came back
    /// grey. The slider is drawn on the app's own light chrome either way.
    private static let fillColor = Color(red: 0.13, green: 0.48, blue: 0.97)

    private func setFromPoint(_ y: CGFloat) {
        let clamped = min(max(y - knobHeight / 2, 0), travel)
        let newFraction = 1 - Double(clamped / travel)
        value = range.lowerBound + newFraction * (range.upperBound - range.lowerBound)
    }
}

/// The popover a bar icon opens: a caption, a vertical slider, and the value.
struct BarSliderPopover: View {
    let title: String
    /// Drawn at the top and bottom of the slider to say which end is which.
    let maxIcon: String
    let minIcon: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String
    let onEditingChanged: (Bool) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)

            Image(systemName: maxIcon)
                .font(.system(size: 10))
                .foregroundColor(.secondary)

            VerticalSlider(
                value: $value,
                range: range,
                onEditingChanged: onEditingChanged
            )

            Image(systemName: minIcon)
                .font(.system(size: 9))
                .foregroundColor(.secondary)

            Text(format(value))
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(width: 92)
    }
}

/// The macOS window close button, borrowed for tabs.
///
/// macOS shows the glyph only while the pointer is over the window's controls and
/// greys the lights out when the window is not in front; both are reproduced here
/// against the tab's own hover and active state, or it reads as a red dot.
struct TrafficLightClose: View {
    let isTabHovered: Bool
    let isTabActive: Bool
    let action: () -> Void

    /// Also the size of the agent mark at the other end of a tab, so the two balance.
    static let diameter: CGFloat = 12

    private static let liveRed = Color(red: 1.0, green: 0.37, blue: 0.34)
    private static let dormant = Color(nsColor: NSColor(calibratedWhite: 0.76, alpha: 1))

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isTabHovered || isTabActive ? Self.liveRed : Self.dormant)
                Circle()
                    .strokeBorder(Color.black.opacity(0.16), lineWidth: 0.5)
                // Always drawn, not only on hover. Hiding it made the dot ambiguous —
                // a coloured circle on a tab could be a status light as easily as a
                // control, and you had to hover to find out which.
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .heavy))
                    .foregroundColor(Color.black.opacity(isTabHovered ? 0.7 : 0.5))
            }
            .frame(width: Self.diameter, height: Self.diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Close Tab")
    }
}
