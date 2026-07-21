#!/usr/bin/env bash
# Grep-based bans for widget/golden/a11y test hygiene. No lint covers any of this.
# Usage: check-test-hygiene.sh [SRC_DIR] [TEST_DIR]
#   SRC_DIR  defaults to lib/   (scanned for text-scale clamps)
#   TEST_DIR defaults to test/  (scanned for overflow suppression, deprecated
#                                matchers, and untagged goldens)
# Exits non-zero on any hard violation. Run before a PR.
set -euo pipefail

SRC_DIR="${1:-lib}"
TEST_DIR="${2:-test}"
FAIL=0

note() { printf '   %s\n' "$*"; }
head_() { printf '\n==> %s\n' "$*"; }

# Scan Dart source excluding generated files.
src_darts() {
  find "$SRC_DIR" -type f -name '*.dart' \
    ! -name '*.g.dart' ! -name '*.freezed.dart' ! -name '*.drift.dart' 2>/dev/null
}
test_darts() {
  find "$TEST_DIR" -type f -name '*.dart' 2>/dev/null
}

# --- 1. lib/ must never clamp or override text scaling -----------------------
head_ "SCAN ($SRC_DIR): text-scale clamps (violate the a11y contract)"
if [ -d "$SRC_DIR" ]; then
  CLAMP=$(src_darts | xargs grep -nE \
    'withClampedTextScaling|textScaleFactor|FittedBox' 2>/dev/null || true)
  if [ -n "$CLAMP" ]; then
    note "VIOLATION: fix the layout, do not clamp the text. Offenders:"
    printf '%s\n' "$CLAMP"; FAIL=1
  else
    note "OK: no text-scale clamps in $SRC_DIR"
  fi
else
  note "skip: $SRC_DIR not found"
fi

# --- 2. test/ must never suppress overflow -----------------------------------
head_ "SCAN ($TEST_DIR): overflow suppression (disarms the whole net)"
if [ -d "$TEST_DIR" ]; then
  SUPPRESS=$(test_darts | xargs grep -nE \
    'ignoreOverflowErrors|FlutterError\.onError\s*=' 2>/dev/null || true)
  if [ -n "$SUPPRESS" ]; then
    note "VIOLATION: never suppress a RenderFlex overflow. Offenders:"
    printf '%s\n' "$SUPPRESS"; FAIL=1
  else
    note "OK: no overflow suppression in $TEST_DIR"
  fi

  # takeException() inside a global tearDown clears the pending exception before
  # testWidgets can rethrow — a subtle way to disarm the net. Flag for review.
  head_ "SCAN ($TEST_DIR): takeException() in a tearDown (silent net removal)"
  TD=$(test_darts | xargs grep -nE 'tearDown\(' 2>/dev/null | grep -i 'takeexception' || true)
  if [ -n "$TD" ]; then
    note "WARN: takeException() near a tearDown — verify it does not clear overflow:"
    printf '%s\n' "$TD"
  else
    note "OK: no takeException() in a tearDown"
  fi

  # --- 3. Deprecated / wrong test-API usage ----------------------------------
  head_ "SCAN ($TEST_DIR): deprecated semantics matchers / finders"
  DEP=$(test_darts | xargs grep -nE \
    'containsSemantics|simulatedAccessibilityTraversal\([^)]*\bstart:|\bend:' 2>/dev/null || true)
  if [ -n "$DEP" ]; then
    note "WARN: use isSemantics (not containsSemantics) and startNode:/endNode:"
    printf '%s\n' "$DEP"
  else
    note "OK: no deprecated semantics matchers"
  fi

  head_ "SCAN ($TEST_DIR): meetsGuideline without await expectLater (asserts nothing)"
  # A meetsGuideline passed to a bare expect(...) is an async matcher discarded.
  MG=$(test_darts | xargs grep -nE 'expect\([^;]*meetsGuideline' 2>/dev/null || true)
  if [ -n "$MG" ]; then
    note "WARN: meetsGuideline is an AsyncMatcher — use 'await expectLater(...)':"
    printf '%s\n' "$MG"
  else
    note "OK: no bare expect(meetsGuideline(...))"
  fi

  # --- 4. Golden tests must carry the golden tag -----------------------------
  head_ "SCAN ($TEST_DIR): golden assertions missing @Tags(['golden'])"
  for f in $(test_darts | xargs grep -lE 'matchesGoldenFile|GoldenTestGroup|goldenTest\(' 2>/dev/null || true); do
    if ! grep -q "@Tags(\['golden'\])" "$f"; then
      note "WARN: $f has golden assertions but no @Tags(['golden'])"
    fi
  done

  # --- 5. find.byType coupling tests to the class hierarchy ------------------
  head_ "SCAN ($TEST_DIR): find.byType for behaviour/geometry (brittle)"
  BT=$(test_darts | xargs grep -nE 'find\.byType\(' 2>/dev/null || true)
  if [ -n "$BT" ]; then
    note "INFO: prefer find.bySemanticsLabel (behaviour) / find.byKey (geometry):"
    printf '%s\n' "$BT"
  else
    note "OK: no find.byType"
  fi
else
  note "skip: $TEST_DIR not found"
fi

head_ "SCAN: pumpAndSettle() as an animation wait (hangs on infinite indicators)"
PAS=$( { src_darts; test_darts; } 2>/dev/null | xargs grep -n 'pumpAndSettle(' 2>/dev/null || true)
if [ -n "$PAS" ]; then
  note "INFO: verify each pumpAndSettle waits a FINITE animation, not a spinner:"
  printf '%s\n' "$PAS"
else
  note "OK: no pumpAndSettle"
fi

if [ "$FAIL" = "0" ]; then
  head_ "OK: no hard violations"
else
  head_ "FAIL: a hard violation was found (see above)"
fi
exit "$FAIL"
