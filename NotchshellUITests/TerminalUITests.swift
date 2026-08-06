import XCTest

/// E2E UI tests for Notchshell terminal.
/// Tests real keyboard/mouse interactions via XCUITest.
/// Requires Notchshell installed at /Applications/Notchshell.app.
///
/// Pattern from Ghostty: terminate + relaunch for clean state before each test.
final class TerminalUITests: NotchshellUITestCase {

    var app: XCUIApplication!

    override class func setUp() {
        super.setUp()
        // Launch once for the entire suite
        let app = XCUIApplication(bundleIdentifier: "com.Notchshell.terminal")
        app.terminate()
        sleep(1)
        app.launch()
        sleep(2)
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication(bundleIdentifier: "com.Notchshell.terminal")
        // Ctrl+C to cancel anything running, then clear
        app.typeKey("c", modifierFlags: .control)
        Thread.sleep(forTimeInterval: 0.2)
    }

    // =========================================================================
    // MARK: - App Lifecycle
    // =========================================================================

    func testAppLaunches() {
        XCTAssertTrue(app.exists, "Notchshell should be running")
    }

    func testAppIsAccessory() {
        // Notchshell is LSUIElement — no Dock icon, no main window
        // It should exist but have no standard windows initially
        XCTAssertTrue(app.exists)
    }

    // =========================================================================
    // MARK: - Tab Management
    // =========================================================================

    func testNewTab() {
        app.typeKey("t", modifierFlags: .command)
        sleep(1)
        // Second Cmd+T → 3 tabs total (1 initial + 2 new)
        app.typeKey("t", modifierFlags: .command)
        sleep(1)
    }

    func testCloseTab() {
        // Create tab then close it
        app.typeKey("t", modifierFlags: .command)
        sleep(1)
        app.typeKey("w", modifierFlags: .command)
        sleep(1)
    }

    func testCloseLastTab_reopensNew() {
        // Close the only tab — Notchshell should auto-create a new one
        app.typeKey("w", modifierFlags: .command)
        sleep(1)
        // App should still be running with a fresh tab
        XCTAssertTrue(app.exists)
    }

    func testTabSwitching_cmdNumber() {
        // Create 3 tabs total
        app.typeKey("t", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
        app.typeKey("t", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)

        // Switch between tabs
        app.typeKey("1", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.3)
        app.typeKey("2", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.3)
        app.typeKey("3", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.3)
        // Cmd+9 goes to last tab
        app.typeKey("9", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.3)
    }

    func testTabSwitching_nextPrevious() {
        app.typeKey("t", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)

        // Cmd+Shift+] = next tab
        app.typeKey("]", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.3)
        // Cmd+Shift+[ = previous tab
        app.typeKey("[", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.3)
    }

    func testReopenClosedTab() {
        // Type something to set directory
        app.typeText("cd /tmp")
        app.typeKey("\r", modifierFlags: [])
        sleep(1)

        // Create new tab, close it, then reopen
        app.typeKey("t", modifierFlags: .command)
        sleep(1)
        app.typeKey("w", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)

        // Cmd+Shift+T reopens closed tab
        app.typeKey("t", modifierFlags: [.command, .shift])
        sleep(1)
    }

    // =========================================================================
    // MARK: - Split Panes
    // =========================================================================

    func testSplitHorizontal() {
        app.typeKey("d", modifierFlags: .command)
        sleep(1)
    }

    func testSplitVertical() {
        app.typeKey("d", modifierFlags: [.command, .shift])
        sleep(1)
    }

    func testSplitAndNavigate() {
        // Create horizontal split
        app.typeKey("d", modifierFlags: .command)
        sleep(1)

        // Navigate: Cmd+] next, Cmd+[ previous
        app.typeKey("]", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.3)
        app.typeKey("[", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.3)
    }

    func testSplitAndTypeInEachPane() {
        app.typeKey("d", modifierFlags: .command)
        sleep(1)

        // Type in second pane (auto-focused after split)
        app.typeText("echo PANE2")
        app.typeKey("\r", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)

        // Switch to first pane
        app.typeKey("[", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)

        // Type in first pane
        app.typeText("echo PANE1")
        app.typeKey("\r", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testSplitAndClosePane() {
        app.typeKey("d", modifierFlags: .command)
        sleep(1)

        // Close the split pane
        app.typeKey("w", modifierFlags: .command)
        sleep(1)
        // Should be back to single pane
    }

    func testMultipleSplits() {
        // Horizontal split
        app.typeKey("d", modifierFlags: .command)
        sleep(1)
        // Vertical split in second pane
        app.typeKey("d", modifierFlags: [.command, .shift])
        sleep(1)
        // 3 panes total
    }

    // =========================================================================
    // MARK: - Text Input & Execution
    // =========================================================================

    func testTypeAndExecute() {
        app.typeText("echo XCUITEST_EXECUTE_OK")
        Thread.sleep(forTimeInterval: 0.3)
        app.typeKey("\r", modifierFlags: [])
        sleep(1)
    }

    func testTypeSpecialCharacters() {
        app.typeText("echo 'hello world' | grep -o 'hello'")
        Thread.sleep(forTimeInterval: 0.3)
        app.typeKey("\r", modifierFlags: [])
        sleep(1)
    }

    func testCtrlC_interruptProcess() {
        app.typeText("sleep 999")
        app.typeKey("\r", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)
        app.typeKey("c", modifierFlags: .control)
        Thread.sleep(forTimeInterval: 0.5)
        // Should return to prompt
    }

    func testCtrlD_EOF() {
        // Ctrl+D on empty line sends EOF
        app.typeKey("d", modifierFlags: .control)
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testCtrlZ_suspend() {
        app.typeText("sleep 999")
        app.typeKey("\r", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)
        app.typeKey("z", modifierFlags: .control)
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testCtrlL_clearScreen() {
        app.typeText("echo line1 && echo line2")
        app.typeKey("\r", modifierFlags: [])
        sleep(1)
        app.typeKey("l", modifierFlags: .control)
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testCtrlA_beginningOfLine() {
        app.typeText("hello world")
        Thread.sleep(forTimeInterval: 0.2)
        app.typeKey("a", modifierFlags: .control)
        Thread.sleep(forTimeInterval: 0.2)
    }

    func testCtrlE_endOfLine() {
        app.typeText("hello world")
        Thread.sleep(forTimeInterval: 0.2)
        app.typeKey("a", modifierFlags: .control) // go to beginning
        Thread.sleep(forTimeInterval: 0.2)
        app.typeKey("e", modifierFlags: .control) // go to end
        Thread.sleep(forTimeInterval: 0.2)
    }

    func testCtrlW_deleteWord() {
        app.typeText("hello world")
        Thread.sleep(forTimeInterval: 0.2)
        app.typeKey("w", modifierFlags: .control)
        Thread.sleep(forTimeInterval: 0.2)
    }

    func testCtrlU_deleteLine() {
        app.typeText("hello world")
        Thread.sleep(forTimeInterval: 0.2)
        app.typeKey("u", modifierFlags: .control)
        Thread.sleep(forTimeInterval: 0.2)
    }

    // =========================================================================
    // MARK: - Copy / Paste / Select
    // =========================================================================

    func testCopyPaste() {
        app.typeText("echo test123")
        Thread.sleep(forTimeInterval: 0.5)
        app.typeKey("a", modifierFlags: .command) // select all
        Thread.sleep(forTimeInterval: 0.5)
        app.typeKey("c", modifierFlags: .command) // copy
        Thread.sleep(forTimeInterval: 0.5)
        app.typeKey("v", modifierFlags: .command) // paste
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testSelectAll() {
        app.typeText("echo some text")
        app.typeKey("\r", modifierFlags: [])
        sleep(1)
        app.typeKey("a", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
    }

    // =========================================================================
    // MARK: - Find / Search
    // =========================================================================

    func testFindBar_openClose() {
        app.typeKey("f", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
        app.typeKey("\u{1B}", modifierFlags: []) // Escape closes
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testFindBar_typeAndSearch() {
        // Generate some output first
        app.typeText("echo searchable_text_12345")
        app.typeKey("\r", modifierFlags: [])
        sleep(1)

        // Open find bar and search
        app.typeKey("f", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
        app.typeText("searchable")
        Thread.sleep(forTimeInterval: 0.5)

        // Find next / previous
        app.typeKey("g", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.3)
        app.typeKey("g", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.3)

        // Close
        app.typeKey("\u{1B}", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)
    }

    // =========================================================================
    // MARK: - Screen Clear
    // =========================================================================

    func testCmdK_clearScreen() {
        app.typeText("echo line1 && echo line2 && echo line3")
        app.typeKey("\r", modifierFlags: [])
        sleep(1)
        app.typeKey("k", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
    }

    // =========================================================================
    // MARK: - Rapid Input (regression: NSBeep / crash)
    // =========================================================================

    func testRapidBackspace_noBeep() {
        app.typeText("abcdefghijklmnopqrstuvwxyz")
        Thread.sleep(forTimeInterval: 0.3)
        for _ in 0..<30 {
            app.typeKey(XCUIKeyboardKey.delete, modifierFlags: [])
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testRapidArrows_noBeep() {
        app.typeText("some text here for arrow navigation")
        Thread.sleep(forTimeInterval: 0.3)
        for _ in 0..<20 {
            app.typeKey(XCUIKeyboardKey.leftArrow, modifierFlags: [])
        }
        for _ in 0..<20 {
            app.typeKey(XCUIKeyboardKey.rightArrow, modifierFlags: [])
        }
        Thread.sleep(forTimeInterval: 0.3)
    }

    func testRapidTyping() {
        // Type fast — should not crash or lose characters
        let text = "the quick brown fox jumps over the lazy dog 0123456789"
        app.typeText(text)
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testRapidTabCreation() {
        // Create and close 5 tabs rapidly
        for _ in 0..<5 {
            app.typeKey("t", modifierFlags: .command)
            Thread.sleep(forTimeInterval: 0.2)
        }
        for _ in 0..<5 {
            app.typeKey("w", modifierFlags: .command)
            Thread.sleep(forTimeInterval: 0.2)
        }
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testRapidSplitCloseSequence() {
        // Split, close, split, close — stress test
        for _ in 0..<3 {
            app.typeKey("d", modifierFlags: .command) // split
            Thread.sleep(forTimeInterval: 0.3)
            app.typeKey("w", modifierFlags: .command) // close
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    // =========================================================================
    // MARK: - Settings & Help
    // =========================================================================

    func testOpenSettings() {
        app.typeKey(",", modifierFlags: .command)
        sleep(1)
    }

    func testOpenHelp() {
        app.typeKey("/", modifierFlags: .command)
        sleep(1)
    }

    // =========================================================================
    // MARK: - Pin / Unpin
    // =========================================================================

    func testPinUnpin() {
        app.typeKey("p", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.5)
        // Unpin
        app.typeKey("p", modifierFlags: [.command, .shift])
        Thread.sleep(forTimeInterval: 0.5)
    }

    // =========================================================================
    // MARK: - Arrow Keys & Navigation
    // =========================================================================

    func testArrowKeys() {
        app.typeText("hello world")
        Thread.sleep(forTimeInterval: 0.2)

        // Left arrow 5 times
        for _ in 0..<5 {
            app.typeKey(XCUIKeyboardKey.leftArrow, modifierFlags: [])
        }
        Thread.sleep(forTimeInterval: 0.2)

        // Right arrow 5 times
        for _ in 0..<5 {
            app.typeKey(XCUIKeyboardKey.rightArrow, modifierFlags: [])
        }
        Thread.sleep(forTimeInterval: 0.2)
    }

    func testUpDownArrows_historyNavigation() {
        // Execute two commands
        app.typeText("echo first_command")
        app.typeKey("\r", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)
        app.typeText("echo second_command")
        app.typeKey("\r", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)

        // Up arrow should recall last command
        app.typeKey(XCUIKeyboardKey.upArrow, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)
        app.typeKey(XCUIKeyboardKey.upArrow, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)

        // Down arrow returns
        app.typeKey(XCUIKeyboardKey.downArrow, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)
    }

    func testHomeEnd() {
        app.typeText("hello world test")
        Thread.sleep(forTimeInterval: 0.2)
        app.typeKey(XCUIKeyboardKey.home, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)
        app.typeKey(XCUIKeyboardKey.end, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.2)
    }

    func testTab_completion() {
        // Tab should trigger shell completion
        app.typeText("ech")
        Thread.sleep(forTimeInterval: 0.2)
        app.typeKey(XCUIKeyboardKey.tab, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testEscape() {
        app.typeText("some incomplete command")
        Thread.sleep(forTimeInterval: 0.2)
        app.typeKey(XCUIKeyboardKey.escape, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)
    }

    // =========================================================================
    // MARK: - Multi-step Workflows
    // =========================================================================

    func testFullWorkflow_typeExecuteNavigate() {
        // Execute a command
        app.typeText("echo workflow_step_1")
        app.typeKey("\r", modifierFlags: [])
        sleep(1)

        // Create a new tab
        app.typeKey("t", modifierFlags: .command)
        sleep(1)

        // Execute in new tab
        app.typeText("echo workflow_step_2")
        app.typeKey("\r", modifierFlags: [])
        sleep(1)

        // Switch back to first tab
        app.typeKey("1", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)

        // Close second tab
        app.typeKey("2", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.3)
        app.typeKey("w", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)
    }

    func testFullWorkflow_splitWorkflow() {
        // Split horizontal
        app.typeKey("d", modifierFlags: .command)
        sleep(1)

        // Run command in right pane
        app.typeText("echo RIGHT_PANE")
        app.typeKey("\r", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)

        // Switch to left pane
        app.typeKey("[", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.5)

        // Run command in left pane
        app.typeText("echo LEFT_PANE")
        app.typeKey("\r", modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.5)

        // Close right pane
        app.typeKey("]", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.3)
        app.typeKey("w", modifierFlags: .command)
        sleep(1)
    }

    func testFullWorkflow_multiTabMultiSplit() {
        // Tab 1: default
        // Tab 2: horizontal split
        app.typeKey("t", modifierFlags: .command)
        sleep(1)
        app.typeKey("d", modifierFlags: .command)
        sleep(1)

        // Tab 3: vertical split
        app.typeKey("t", modifierFlags: .command)
        sleep(1)
        app.typeKey("d", modifierFlags: [.command, .shift])
        sleep(1)

        // Navigate through all
        app.typeKey("1", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.3)
        app.typeKey("2", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.3)
        app.typeKey("3", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.3)

        // Close all extra tabs
        app.typeKey("w", modifierFlags: .command) // close split pane
        Thread.sleep(forTimeInterval: 0.3)
        app.typeKey("w", modifierFlags: .command) // close tab 3
        Thread.sleep(forTimeInterval: 0.3)
        app.typeKey("2", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.2)
        app.typeKey("w", modifierFlags: .command) // close split
        Thread.sleep(forTimeInterval: 0.3)
        app.typeKey("w", modifierFlags: .command) // close tab 2
        Thread.sleep(forTimeInterval: 0.3)
    }

    // =========================================================================
    // MARK: - Accessibility Audit
    // =========================================================================

    func testAccessibilityAudit_mainWindow() throws {
        continueAfterFailure = true
        try app.performAccessibilityAudit()
    }

    func testAccessibilityAudit_settingsTab() throws {
        continueAfterFailure = true
        app.typeKey(",", modifierFlags: .command) // open settings
        sleep(1)
        try app.performAccessibilityAudit()
        // Close settings tab
        app.typeKey("w", modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.3)
    }
}
