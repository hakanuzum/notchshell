import Foundation

/// Polls the process tree for agent CLIs and reports which tab each one is in.
///
/// Only while the panel is on screen. This is the same lesson `setSurfacesVisible`
/// records: a dropped panel is meant to cost nothing, and a timer that keeps walking
/// the process table would quietly give some of that back. The last result is kept
/// across a hide, so re-opening shows the badges immediately rather than blank for a
/// tick.
@MainActor
final class AgentMonitor {
    /// Slow enough to be free, fast enough that starting `claude` badges the tab
    /// before you have finished reading its banner.
    static let interval: TimeInterval = 2.0

    private let scanner = AgentScanner()
    private var timer: Timer?
    private var scanInFlight = false

    private(set) var agents: [String: AgentKind] = [:]
    var onChange: (([String: AgentKind]) -> Void)?

    func setActive(_ active: Bool) {
        guard active else {
            timer?.invalidate()
            timer = nil
            return
        }
        guard timer == nil else { return }
        tick()
        let timer = Timer(timeInterval: Self.interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // `.common` so a tracking loop — dragging the panel edge, scrolling the tab
        // bar — does not stall the badges.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        guard !scanInFlight else { return }
        scanInFlight = true
        let rootPID = getpid()
        Task { [scanner] in
            let result = await scanner.scan(rootPID: rootPID)
            await MainActor.run {
                self.scanInFlight = false
                guard result != self.agents else { return }
                self.agents = result
                self.onChange?(result)
            }
        }
    }

    deinit {
        timer?.invalidate()
    }
}
