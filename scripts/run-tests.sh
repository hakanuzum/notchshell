#!/bin/bash
# Run test suites sequentially to avoid AppKit resource exhaustion.
# Usage: scripts/run-tests.sh [suite_name]

set -uo pipefail
cd "$(dirname "$0")/.."
source "$(dirname "$0")/_toolchain.sh"

# Build once
echo "=== Building tests ==="
swift build --build-tests 2>&1 | tail -3

SUITES=(
    HorizontalEdgeTests
    PanelStateTests
    ScreenInfoTests
    TerminalThemeTests
    AppIdentityTests
    ManagedConfigTests
    GhosttyThemeCatalogTests
    ThemeCatalogPerformanceTests
    ThemeSelectionTests
    GhosttyConfigProbeTests
    ScreenDetectorTests
    TabTests
    NotificationTests
    HorizontalEdgeExtendedTests
    TabKindTests
    BackendTypeTests
    GhosttyAppTests
    ControlServerAccessTests
    TerminalThemeExtendedTests
    MouseDownNSViewTests
    MouseDownNSViewExtendedTests
    DoubleClickCatcherTests
    TerminalBackendProtocolTests
    TerminalInstanceTests
    PaneNodeTests
    TabModelExtendedTests
    KeyboardFocusTests
    PaneManagementTests
    PaneManagerAdvancedTests
    TabManagerTests
    TabManagerAdvancedTests
    PanelWindowStateTests
    TerminalPanelTests
    ScreenDetectorExtendedTests
    WindowControllerResizeTests
    WindowControllerLifecycleTests
    UIComponentTests/
    WindowControllerSettingsHelpTests
    TabCloseEdgeCaseTests
    TabReorderingTests
    TabStatePersistenceTests
    CloseConfirmationTests
    PinnedWindowVisibilityTests
    TabManagerTerminalIntegrationTests
    WindowControllerTabManagerIntegrationTests
    NotchshellE2ETests
)

PASSED=0
FAILED=0
SKIPPED=0
FAILED_NAMES=()

# If a specific suite is given, only run that one
if [ -n "${1:-}" ]; then
    SUITES=("$1")
fi

for suite in "${SUITES[@]}"; do
    echo -n "  $suite ... "
    if command -v timeout &>/dev/null; then
        OUTPUT=$(timeout 60 swift test --skip-build --filter "$suite" 2>&1); EXIT_CODE=$?
    elif command -v gtimeout &>/dev/null; then
        OUTPUT=$(gtimeout 60 swift test --skip-build --filter "$suite" 2>&1); EXIT_CODE=$?
    else
        OUTPUT=$(swift test --skip-build --filter "$suite" 2>&1); EXIT_CODE=$?
    fi

    # How many tests actually ran. A filter matching nothing still exits 0, so
    # without this a stale or misspelled name in SUITES reads as a pass — which is
    # how a failing E2E suite stayed hidden here behind a name that no longer
    # existed. Both runners are counted: swift-testing reports "Test run with N
    # tests", XCTest reports "Executed N tests", and a swift-testing-only suite
    # always prints "Executed 0 tests" for the empty XCTest half.
    RAN_TESTING=$(echo "$OUTPUT" | grep -oE 'Test run with [0-9]+ test' | grep -oE '[0-9]+' | head -1)
    RAN_XCTEST=$(echo "$OUTPUT" | grep -oE 'Executed [0-9]+ test' | grep -oE '[0-9]+' | head -1)
    RAN=$(( ${RAN_TESTING:-0} + ${RAN_XCTEST:-0} ))

    if echo "$OUTPUT" | grep -q 'disabled'; then
        echo "SKIP (disabled)"
        SKIPPED=$((SKIPPED + 1))
    elif [ "$RAN" -eq 0 ] && [ $EXIT_CODE -eq 0 ]; then
        echo "NO MATCH (suite name wrong?)"
        FAILED=$((FAILED + 1))
        FAILED_NAMES+=("$suite")
    elif [ $EXIT_CODE -eq 0 ] && echo "$OUTPUT" | grep -q "passed"; then
        TESTS=$(echo "$OUTPUT" | grep -c '✔ Test' || true)
        echo "OK ($TESTS tests)"
        PASSED=$((PASSED + 1))
    elif [ $EXIT_CODE -eq 124 ]; then
        echo "TIMEOUT (60s)"
        FAILED=$((FAILED + 1))
        FAILED_NAMES+=("$suite")
    else
        echo "FAIL (exit $EXIT_CODE)"
        FAILED=$((FAILED + 1))
        FAILED_NAMES+=("$suite")
        # Show failure details
        echo "$OUTPUT" | grep -E '✘|Issue|error:' | head -5
    fi
done

echo ""
echo "=== Results ==="
echo "  Passed:  $PASSED"
echo "  Failed:  $FAILED"
echo "  Skipped: $SKIPPED"
if [ ${#FAILED_NAMES[@]} -gt 0 ]; then
    echo "  Failed suites: ${FAILED_NAMES[*]}"
    exit 1
fi
