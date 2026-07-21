#!/usr/bin/env bash
# check_architecture.sh — grep-based architecture boundary checks for a Flutter app.
# Usage: scripts/check_architecture.sh [TARGET_DIR]   (TARGET_DIR defaults to lib/)
# Prints a PASS/FAIL line per check and exits non-zero if any hard check fails.
# Hardcodes no app-specific paths; run it from the package/app root.
set -euo pipefail

TARGET="${1:-lib}"
if [ ! -d "$TARGET" ]; then
  echo "target dir '$TARGET' not found; pass a lib/ directory" >&2
  exit 2
fi

echo "== architecture checks @ $TARGET =="
FAILED=0
pass() { echo "PASS  $1"; }
fail() { echo "FAIL  $1"; FAILED=1; }
skip() { echo "SKIP  $1"; }

# Exclude generated files from every grep.
GEN='\.g\.dart|\.freezed\.dart|\.gr\.dart|\.config\.dart'
scan() { grep -rnE "$1" "$TARGET" 2>/dev/null | grep -vE "$GEN" || true; }

# --- 1. no second DI container / service locator ---------------------------
DI_HITS="$(scan "package:get_it|package:injectable|package:provider/provider\.dart|GetIt\.")"
if [ -z "$DI_HITS" ]; then
  pass "no get_it / injectable / package:provider DI container (Riverpod is the one DI)"
else
  fail "second DI container found — use Riverpod providers as the one DI mechanism:"
  echo "$DI_HITS"
fi

# --- 2. no legacy Riverpod providers ---------------------------------------
LEGACY_HITS="$(scan "StateProvider|StateNotifierProvider|ChangeNotifierProvider|riverpod/legacy\.dart")"
if [ -z "$LEGACY_HITS" ]; then
  pass "no legacy Riverpod providers (use Notifier/AsyncNotifier)"
else
  fail "legacy Riverpod provider found — migrate to Notifier/AsyncNotifier:"
  echo "$LEGACY_HITS"
fi

# --- 3. no wall-clock reads outside an injected Clock ----------------------
CLOCK_HITS="$(scan "DateTime\.now\(\)|DateTime\.timestamp\(\)" | grep -viE 'clock|/core/' || true)"
if [ -z "$CLOCK_HITS" ]; then
  pass "no DateTime.now() outside a Clock (time is injected)"
else
  fail "wall-clock read outside an injected Clock (inject a Clock instead):"
  echo "$CLOCK_HITS"
fi

# --- 4. no silent error swallow --------------------------------------------
SWALLOW_HITS="$(scan 'catch\s*\(\s*_\s*\)\s*\{\s*\}')"
if [ -z "$SWALLOW_HITS" ]; then
  pass "no empty catch(_) {} swallow"
else
  fail "silent error swallow found (return a typed Result / rethrow instead):"
  echo "$SWALLOW_HITS"
fi

# --- 5. no cross-package src/ import (only meaningful in a workspace) -------
SRC_HITS="$(scan "import\s+'package:[a-z_]+/src/")"
if [ -z "$SRC_HITS" ]; then
  pass "no cross-package src/ imports (barrels respected — n/a for single-package apps)"
else
  fail "cross-package src/ import found (import the package barrel instead):"
  echo "$SRC_HITS"
fi

# --- 6. no _buildX widget-returning helpers --------------------------------
# Extract widget CLASSES, not private methods that return a Widget.
BUILDX_HITS="$(scan 'Widget\s+_build[A-Z][A-Za-z0-9]*\s*\(')"
if [ -z "$BUILDX_HITS" ]; then
  pass "no _buildX() widget-returning helpers (compose widget classes)"
else
  echo "WARN  _buildX() widget helper(s) found — prefer small const widget classes:"
  echo "$BUILDX_HITS"
fi

# --- 7. dart analyze (if the toolchain is present) -------------------------
if command -v dart >/dev/null 2>&1; then
  if dart analyze "$TARGET" >/tmp/arch_analyze.log 2>&1; then
    pass "dart analyze clean"
  else
    fail "dart analyze reported issues — see /tmp/arch_analyze.log"
  fi
else
  skip "dart analyze (dart not on PATH)"
fi

echo "== done =="
exit $FAILED
