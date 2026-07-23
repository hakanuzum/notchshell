#!/bin/bash
# Run all hakuke tests: unit tests (SPM) + E2E tests (Socket API).
# XCUITests run separately from Xcode IDE.
#
# Usage:
#   scripts/test-all.sh          # run all
#   scripts/test-all.sh unit     # unit tests only
#   scripts/test-all.sh e2e      # E2E tests only (requires running hakuke)

set -uo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-all}"
EXIT=0

if [ "$MODE" = "all" ] || [ "$MODE" = "unit" ]; then
    echo "=== Unit Tests (SPM) ==="
    bash scripts/run-tests.sh
    if [ $? -ne 0 ]; then EXIT=1; fi
fi

if [ "$MODE" = "all" ] || [ "$MODE" = "e2e" ]; then
    echo ""
    echo "=== E2E Tests (Socket API) ==="
    if [ -S /tmp/hakuke.sock ]; then
        python3 scripts/e2e-test.py
        if [ $? -ne 0 ]; then EXIT=1; fi
    else
        echo "  SKIP — hakuke not running (no /tmp/hakuke.sock)"
        echo "  Start hakuke and enable API in Settings first."
    fi
fi

echo ""
echo "=== XCUITests ==="
echo "  Run from Xcode: open Hakuke.xcodeproj → Cmd+U"
echo ""

exit $EXIT
