#!/usr/bin/env bash
set -euo pipefail
# Usage: check_test_hygiene.sh [LIB_DIR] [TEST_DIR]
# Grep-based bans that no lint catches. Prints findings and exits non-zero if any hit.
# Defaults: lib/ and test/. Hardcodes no app-specific paths.

LIB_DIR="${1:-lib}"
TEST_DIR="${2:-test}"
fail=0

note() { printf '  %s\n' "$1"; }
section() { printf '\n== %s ==\n' "$1"; }

# 1. Wall-clock / ambient entropy reachable from domain logic. Inject Clock + a seed.
section "DateTime.now() / ambient Random() in lib/ (inject clock + seed instead)"
# Flag every DateTime.now()/Random() in lib/; an injected seed passes `Random(seed)`,
# which is not matched by the bare `Random()` pattern.
if grep -rnE '\b(DateTime\.now\(\)|DateTime\.timestamp\(\)|math\.Random\(\)|Random\(\))' \
     "$LIB_DIR" --include='*.dart' 2>/dev/null \
   | grep -vE '\.g\.dart|\.freezed\.dart|\.drift\.dart'; then
  note "-> read clock.now() and pass an injected seed; pin with withClock in tests."
  fail=1
fi

# 2. A mocked DAO/database standing in for the real in-memory engine.
section "Mocked DAO / Database in tests (use NativeDatabase.memory instead)"
if grep -rnE 'class\s+\w*(Mock|Fake)\w*(Dao|Database)\b.*(extends Mock|implements .*(Dao|Database))' \
     "$TEST_DIR" --include='*.dart' 2>/dev/null; then
  note "-> a mocked DAO proves nothing about SQL/constraints; use NativeDatabase.memory()."
  fail=1
fi

# 3. pumpAndSettle() — hangs on indefinite animations; use timed pump(Duration).
section "pumpAndSettle() (use timed pump(Duration) + fakeAsync on indefinite animations)"
if grep -rnE '\bpumpAndSettle\(' "$TEST_DIR" --include='*.dart' 2>/dev/null; then
  note "-> review each; on any indefinite animation it hangs on the 10-minute timeout."
  fail=1
fi

# 4. mockito creeping in — this library standardizes on mocktail + bare fakes.
section "mockito / @GenerateMocks (standardize on mocktail + bare-implements fakes)"
if grep -rnE "package:mockito|@GenerateMocks" "$TEST_DIR" --include='*.dart' 2>/dev/null; then
  note "-> replace with mocktail (external deps) or a bare-implements fake (owned code)."
  fail=1
fi

# 5. mocktail any()/captureAny() present but no registerFallbackValue anywhere.
section "mocktail any()/captureAny() without any registerFallbackValue"
if grep -rlE '\b(any|captureAny)\(' "$TEST_DIR" --include='*.dart' 2>/dev/null | grep -q .; then
  if ! grep -rqE 'registerFallbackValue\(' "$TEST_DIR" --include='*.dart' 2>/dev/null; then
    note "-> custom types crossing any()/captureAny() throw at RUNTIME without a fallback."
    fail=1
  fi
fi

# 6. == on doubles in expect (use closeTo).
section "expect(..., equals(<double literal>)) (use closeTo for doubles)"
if grep -rnE 'equals\(\s*-?[0-9]+\.[0-9]+\s*\)' "$TEST_DIR" --include='*.dart' 2>/dev/null; then
  note "-> assert doubles with closeTo(value, 1e-9), never == ."
  fail=1
fi

if [[ "$fail" -ne 0 ]]; then
  printf '\nTest hygiene check FAILED.\n'
  exit 1
fi
printf '\nTest hygiene check passed.\n'
