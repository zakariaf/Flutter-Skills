#!/usr/bin/env bash
# Analyze and unit-test the pure money/units core. The value-object core carries
# the highest-leverage tests in the app, so this is the fast pre-PR gate.
# Usage: scripts/verify-core.sh [TARGET_DIR]   (default: lib/)
set -euo pipefail

TARGET="${1:-lib}"
if [ ! -d "$TARGET" ]; then
  echo "ERROR: target dir '$TARGET' not found" >&2
  exit 2
fi

# The core is pure Dart (no flutter/*; deps only decimal + clock), so it must be
# analyzed and tested with the Dart toolchain — `flutter test` errors on a
# Flutter-free package. Prefer FVM if the repo pins an SDK; else the bare tool.
if command -v fvm >/dev/null 2>&1 && [ -f ".fvmrc" ]; then
  DART="fvm dart"
else
  DART="dart"
fi
echo "==> using: $DART"

echo "==> [1/2] analyze --fatal-infos ($TARGET)"
$DART analyze --fatal-infos "$TARGET"

echo "==> [2/2] unit tests + coverage"
$DART test --coverage=coverage

LCOV="coverage/lcov.info"
# `dart test --coverage=<dir>` emits raw hitmaps; fold them into lcov (best-effort).
if [ -d coverage ] && [ ! -f "$LCOV" ]; then
  $DART run coverage:format_coverage --lcov --in=coverage --out="$LCOV" \
    --report-on="$TARGET" >/dev/null 2>&1 || true
fi
if [ -f "$LCOV" ]; then
  total="$(grep -c '^DA:' "$LCOV" || echo 0)"
  hit="$(grep '^DA:' "$LCOV" | grep -vE ',0$' | wc -l | tr -d ' ')"
  echo "==> coverage: $hit/$total lines hit"
fi

echo "==> OK: core analyzed and tested"
