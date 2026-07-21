#!/usr/bin/env bash
# Grep-based scan for value-objects-money-and-units violations.
# Usage: scripts/check-money-violations.sh [TARGET_DIR]   (default: lib/)
# Read-only; prints every offending file:line and exits non-zero on any hit,
# so it doubles as a local pre-commit / CI gate.
set -euo pipefail

TARGET="${1:-lib}"
if [ ! -d "$TARGET" ]; then
  echo "ERROR: target dir '$TARGET' not found" >&2
  exit 2
fi
echo "==> scanning money/unit violations under: $TARGET"

# Exclude generated files from every scan.
DART_FILES="$(find "$TARGET" -name '*.dart' 2>/dev/null \
  | grep -v -E '\.(g|freezed|drift|mocks)\.dart$' || true)"
if [ -z "$DART_FILES" ]; then
  echo "   (no dart files found)"; exit 0
fi

fail=0
report() { # $1 = human label; grep hits on stdin
  local label="$1" hits
  hits="$(cat)"
  if [ -n "$hits" ]; then
    echo ""; echo "VIOLATION: $label"
    echo "$hits" | sed 's/^/   /'
    fail=1
  fi
}

# 1) double / num typed money fields (double amount, num price, final double total…)
echo "$DART_FILES" | xargs grep -nE \
  '(double|num)[[:space:]]+[a-zA-Z_]*(amount|price|cost|money|total|balance|subtotal|minor|cents)' \
  2>/dev/null | report "double/num-typed money field (money must be int minor units)"

# 2) hardcoded *100 or /100 scaling next to a money word (use currency.minorPerMajor)
echo "$DART_FILES" | xargs grep -nE \
  '(amount|price|cost|money|total|minor|cents)[a-zA-Z_]*[[:space:]]*[*/][[:space:]]*100\b|[*/][[:space:]]*100[[:space:]]*[;)].*(amount|price|money|cents)' \
  2>/dev/null | report "hardcoded *100 or /100 money scaling (use currency.minorPerMajor)"

# 3) Decimal(...) constructed from a double variable (binary error; parse from String/int)
echo "$DART_FILES" | xargs grep -nE \
  'Decimal\.parse\([[:space:]]*[a-zA-Z_][a-zA-Z0-9_.]*\.toString\(\)|Decimal\([[:space:]]*[a-zA-Z_]' \
  2>/dev/null | report "Decimal built from a double (init Decimal from a String or int)"

# 4) DateTime.now() in the pure core (inject a Clock instead)
echo "$DART_FILES" | xargs grep -nE 'DateTime\.now\(\)' 2>/dev/null \
  | report "DateTime.now() (inject a Clock so time is deterministic in tests)"

# 5) Flutter / intl / dart:io imports leaking into the pure money core
echo "$DART_FILES" | xargs grep -nE \
  "import[[:space:]]+'(package:flutter/|package:intl/|dart:io)" 2>/dev/null \
  | report "Flutter/intl/dart:io import in the money core (keep it pure Dart)"

# 6) bespoke clock type instead of package:clock's Clock (does not compose with
#    withClock/clockProvider — the one time seam is package:clock)
echo "$DART_FILES" | xargs grep -nE \
  '\bClockService\b|class[[:space:]]+(System|Fake)Clock\b' 2>/dev/null \
  | report "bespoke ClockService/SystemClock/FakeClock (use package:clock's Clock)"

echo ""
if [ "$fail" -eq 0 ]; then
  echo "==> OK: no money/unit violations found"
else
  echo "==> FAIL: violations above must be fixed"
fi
exit "$fail"
