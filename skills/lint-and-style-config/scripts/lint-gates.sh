#!/usr/bin/env bash
set -euo pipefail
# lint-gates.sh — run the format/analyze gates plus grep bans that lints miss.
# Usage: scripts/lint-gates.sh [TARGET_DIR]   (TARGET_DIR defaults to lib/)
# Run before every PR. Exits non-zero on the first failing gate.

TARGET_DIR="${1:-lib}"
fail=0

echo "==> dart format (whitespace authority)"
if ! dart format --output=none --set-exit-if-changed .; then
  echo "FAIL: run 'dart format .' — the formatter is the sole whitespace authority." >&2
  fail=1
fi

echo "==> dart analyze --fatal-infos --fatal-warnings"
if ! dart analyze --fatal-infos --fatal-warnings; then
  echo "FAIL: analyzer reported infos/warnings; an info is a failure." >&2
  fail=1
fi

# --- grep bans: correctness gates the analyzer cannot express ---------------

echo "==> ban: print()/debugPrint() in shipped code (outside kDebugMode)"
if grep -rnE '\b(print|debugPrint)\(' "$TARGET_DIR" --include='*.dart' \
     | grep -v 'kDebugMode' ; then
  echo "FAIL: use a logger/report seam, not stdout, in shipped lib/." >&2
  fail=1
fi

echo "==> ban: file-scoped // ignore_for_file suppressions"
if grep -rnE '//[[:space:]]*ignore_for_file:' "$TARGET_DIR" --include='*.dart' ; then
  echo "FAIL: // ignore_for_file leaves the whole file unprotected on the next edit." >&2
  fail=1
fi

echo "==> ban: custom_lint (legacy plugin system; riverpod_lint 3.x needs none)"
if grep -rnE '^[[:space:]]*custom_lint' pubspec.yaml 2>/dev/null ; then
  echo "FAIL: remove custom_lint; riverpod_lint 3.x runs on the first-party plugin system." >&2
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "lint-gates: FAILED" >&2
  exit 1
fi
echo "lint-gates: OK"
