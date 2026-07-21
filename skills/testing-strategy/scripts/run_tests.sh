#!/usr/bin/env bash
set -euo pipefail
# Usage: run_tests.sh [LIB_DIR]
# Mirror the CI test lane locally: analyze, run the suite with coverage, fix the
# coverage-lies-upward gap (include untested files), and strip generated code.
# Defaults LIB_DIR to lib/. Hardcodes no app-specific paths.

LIB_DIR="${1:-lib}"

echo "== flutter analyze (fatal on infos) =="
flutter analyze --fatal-infos --fatal-warnings

echo "== flutter test --coverage (randomized ordering) =="
flutter test --coverage --test-randomize-ordering-seed random

# Fix the coverage-lies-upward gap: flutter test omits files no test imports, so the
# raw percentage overstates safety. Include untested files if dlcov is available.
if command -v dlcov >/dev/null 2>&1; then
  echo "== dlcov: include untested files in the denominator =="
  dlcov --include-untested-files=true --lib-dir "$LIB_DIR"
else
  echo "NOTE: dlcov not found — the coverage number omits untested files and lies UPWARD."
  echo "      Install dlcov or generate test/coverage_helper_test.dart importing all of $LIB_DIR."
fi

# Strip generated code so it does not inflate or dilute the report.
if command -v lcov >/dev/null 2>&1 && [[ -f coverage/lcov.info ]]; then
  echo "== strip generated code from lcov.info =="
  lcov --remove coverage/lcov.info \
    "$LIB_DIR/**/*.g.dart" \
    "$LIB_DIR/**/*.freezed.dart" \
    "$LIB_DIR/**/*.drift.dart" \
    -o coverage/lcov.info \
    --ignore-errors unused   # lcov 2.x errors on patterns that match nothing
fi

echo "== done. Coverage report at coverage/lcov.info =="
echo "   Gate the unrecoverable-bug FILES at 100% (migrations, allocate, wire-format parser);"
echo "   publish the rest as a ratcheting report, not a global percentage gate."
