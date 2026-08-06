import XCTest

/// Base class for Notchshell UI tests.
/// Skips in CI — only runs manually in Xcode IDE.
/// Launches Notchshell from build/Notchshell.app with clean state.
class NotchshellUITestCase: XCTestCase {

    override class var defaultTestSuite: XCTestSuite {
        // Only run when launched from Xcode IDE
        if ProcessInfo.processInfo.environment["IDE_DISABLED_OS_ACTIVITY_DT_MODE"] != nil {
            return XCTestSuite(forTestCaseClass: Self.self)
        } else {
            return XCTestSuite(name: "Skipping \(className()) — run from Xcode IDE")
        }
    }

    func notchshellApp() -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: "com.Notchshell.terminal")
        app.launchArguments.append(contentsOf: ["-ApplePersistenceIgnoreState", "YES"])
        return app
    }

    /// Wait for a condition with timeout.
    func waitFor(_ condition: @autoclosure () -> Bool, timeout: TimeInterval = 3, message: String = "") {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(condition(), message)
    }
}
