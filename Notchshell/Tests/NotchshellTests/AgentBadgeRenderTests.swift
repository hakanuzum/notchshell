import AppKit
import SwiftUI
import Testing
@testable import Notchshell

/// Renders the real tab views to a PNG so the badge can be looked at rather than
/// reasoned about. Writes to `NOTCHSHELL_RENDER_DIR` when set; otherwise it only
/// asserts that the views lay out and that the badge takes the space it is supposed to.
@Suite("Agent badge rendering")
@MainActor
struct AgentBadgeRenderTests {
    private func image(of view: some View, size: CGSize) -> NSImage? {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)
        hosting.layoutSubtreeIfNeeded()
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            return nil
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }

    private func sampleBar(_ scheme: ColorScheme) -> some View {
        HStack(spacing: -FolderTab.slant) {
            FolderTab(
                title: "notchshell", kind: .terminal, agent: .claude, isActive: true,
                onSelect: {}, onClose: {}, height: 26
            )
            FolderTab(
                title: "api", kind: .terminal, agent: .codex, isActive: false,
                onSelect: {}, onClose: {}, height: 26
            )
            FolderTab(
                title: "web", kind: .terminal, agent: .gemini, isActive: false,
                onSelect: {}, onClose: {}, height: 26
            )
            FolderTab(
                title: "notes", kind: .terminal, agent: nil, isActive: false,
                onSelect: {}, onClose: {}, height: 26
            )
        }
        .padding(8)
        .background(FolderTabPalette.of(scheme).bar)
        .environment(\.colorScheme, scheme)
    }

    /// Both palettes, because the point of the dark one is that it is the same bar —
    /// same shape, same edge, same spacing — and only a render shows that.
    @Test(arguments: [ColorScheme.light, ColorScheme.dark])
    func rendersTheTabBar(_ scheme: ColorScheme) throws {
        let size = CGSize(width: 520, height: 44)
        let image = try #require(self.image(of: sampleBar(scheme), size: size))
        #expect(image.size == size)

        if let directory = ProcessInfo.processInfo.environment["NOTCHSHELL_RENDER_DIR"] {
            let name = scheme == .dark ? "tab-bar-dark.png" : "tab-bar-light.png"
            let url = URL(fileURLWithPath: directory).appendingPathComponent(name)
            let tiff = try #require(image.tiffRepresentation)
            let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
            try png.write(to: url)
        }
    }

    /// The two palettes have to keep the same ordering — bar behind, inactive in front
    /// of it, active furthest forward — or the bar stops reading as a folder divider.
    @Test func bothPalettesStackTheSameWay() {
        for palette in [FolderTabPalette.light, FolderTabPalette.dark] {
            let bar = brightness(palette.bar)
            let inactive = brightness(palette.inactiveTop)
            let active = brightness(palette.activeTop)
            let text = brightness(palette.activeText)
            #expect(abs(inactive - bar) > 0.04)
            #expect(abs(active - inactive) > 0.04)
            // Active text has to clear its own tab by a wide margin.
            #expect(abs(text - active) > 0.5)
        }
    }

    private func brightness(_ color: Color) -> CGFloat {
        NSColor(color).usingColorSpace(.deviceRGB)?.brightnessComponent ?? -1
    }

    @Test func rendersEveryBadge() throws {
        let grid = VStack(alignment: .leading, spacing: 6) {
            ForEach(AgentKind.allCases, id: \.self) { agent in
                HStack(spacing: 6) {
                    AgentBadge(agent: agent, size: 14)
                    Text(agent.label).font(.system(size: 11))
                }
            }
        }
        .padding(10)
        .foregroundStyle(.black)
        .background(Color.white)

        let size = CGSize(width: 220, height: 24 * CGFloat(AgentKind.allCases.count) + 20)
        let image = try #require(self.image(of: grid, size: size))
        #expect(image.size == size)

        if let directory = ProcessInfo.processInfo.environment["NOTCHSHELL_RENDER_DIR"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("badges.png")
            let tiff = try #require(image.tiffRepresentation)
            let png = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
            try png.write(to: url)
        }
    }

    /// A badge must not push the name out of a narrow tab: the bar is only as wide as
    /// the notch leaves it.
    @Test func badgeCostsAFixedWidth() throws {
        let withAgent = NSHostingView(rootView: FolderTab(
            title: "notchshell", kind: .terminal, agent: .claude, isActive: false,
            onSelect: {}, onClose: {}, height: 26
        ))
        let without = NSHostingView(rootView: FolderTab(
            title: "notchshell", kind: .terminal, agent: nil, isActive: false,
            onSelect: {}, onClose: {}, height: 26
        ))
        let delta = withAgent.fittingSize.width - without.fittingSize.width
        // The glyph is sized to the close dot (12pt), plus the HStack's 6pt spacing.
        #expect(delta == TrafficLightClose.diameter + 6)
    }
}
