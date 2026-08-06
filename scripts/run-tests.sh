#!/bin/bash
# Run the test suites one at a time.
#
# Sequentially, because running everything in one process exhausts AppKit resources
# and produces failures that have nothing to do with the code.
#
# The suite list is derived from the built test binary rather than maintained by
# hand. It used to be a literal array, and it had drifted badly: 46 of the 92 suites
# were missing from it, and one name in it no longer existed — a filter matching
# nothing exits 0, so that read as a pass and hid a suite that was failing.
#
# Usage: scripts/run-tests.sh [suite_name]

set -uo pipefail
cd "$(dirname "$0")/.."
source "$(dirname "$0")/_toolchain.sh"

echo "=== Building tests ==="
swift build --build-tests 2>&1 | tail -3

if [ -n "${1:-}" ]; then
    SUITES=("$1")
else
    # "Target.Suite/test()" -> "Suite". Built with a read loop rather than mapfile,
    # which macOS's bundled bash 3.2 does not have.
    SUITES=()
    while IFS= read -r name; do
        [ -n "$name" ] && SUITES+=("$name")
    done < <(swift test list 2>/dev/null \
        | grep -oE '^[A-Za-z0-9_]+\.[A-Za-z0-9_]+/' \
        | cut -d. -f2 | tr -d '/' | sort -u)
    if [ ${#SUITES[@]} -eq 0 ]; then
        echo "Could not enumerate suites — is the test target built?" >&2
        exit 1
    fi
    echo "=== ${#SUITES[@]} suites ==="
fi

PASSED=0
FAILED=0
SKIPPED=0
FAILED_NAMES=()

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
    # without this a stale name reads as a pass. Both runners are counted:
    # swift-testing reports "Test run with N tests", XCTest reports "Executed N
    # tests", and a swift-testing-only suite always prints "Executed 0 tests" for
    # the empty XCTest half.
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
        echo "OK ($RAN tests)"
        PASSED=$((PASSED + 1))
    elif [ $EXIT_CODE -eq 124 ]; then
        echo "TIMEOUT (60s)"
        FAILED=$((FAILED + 1))
        FAILED_NAMES+=("$suite")
    else
        echo "FAIL (exit $EXIT_CODE)"
        FAILED=$((FAILED + 1))
        FAILED_NAMES+=("$suite")
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
