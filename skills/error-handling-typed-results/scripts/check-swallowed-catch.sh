#!/usr/bin/env bash
# Usage: check-swallowed-catch.sh [TARGET_DIR]   (default: lib/)
# Fails on swallowed catches, stack-dropping catches, `throw e;`, and `default:`
# on a sealed Failure switch. Prints every offending file:line; exits non-zero
# if any are found. Portable to bash 3.2 (macOS default).
#
# Escape hatch: the ONE licensed swallow — the logger that runs inside the error
# handlers (see references/result-failure-spine.md) — is exempt when its `catch`
# line (or an immediately adjacent line) carries `// ignore: swallowed_catch`.
# Nothing else is exempt.
set -euo pipefail

TARGET="${1:-lib/}"
if [ ! -d "$TARGET" ]; then
  echo "==> target dir not found: $TARGET (nothing to scan)"
  exit 0
fi
echo "==> scanning under: $TARGET"

GREP="grep -rnE --include=*.dart"
# Exclude generated files and the tests that assert these very patterns.
EXCL="--exclude=*.g.dart --exclude=*.freezed.dart --exclude=*.drift.dart --exclude=*_test.dart"
# The only marker that licenses a bare catch — kept in sync with the reference.
MARKER='// ignore: swallowed_catch'

fail=0

# scan_catch PATTERN FAILMSG OKMSG
# Reports lines matching PATTERN, EXCEPT a catch line whose own line or an
# immediately adjacent line (+/-1) carries the intentional-catch MARKER.
scan_catch() {
  local pattern="$1" failmsg="$2" okmsg="$3"
  local any=0 hit file rest lineno
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    file="${hit%%:*}"
    rest="${hit#*:}"
    lineno="${rest%%:*}"
    if awk -v n="$lineno" -v m="$MARKER" '
          NR>=n-1 && NR<=n+1 && index($0, m) { found=1 }
          END { exit(found?0:1) }' "$file"; then
      continue # licensed logger catch — exempt
    fi
    echo "$hit"
    any=1
  done < <($GREP $EXCL "$pattern" "$TARGET" 2>/dev/null || true)
  if [ "$any" -ne 0 ]; then
    echo "$failmsg" >&2
    fail=1
  else
    echo "$okmsg"
  fi
}

echo "--- [1] underscore catch: catch (_) ---"
scan_catch 'catch\s*\(\s*_\s*[,)]' \
  "!! FAIL: 'catch (_)' swallows type AND stack. Log the original + return a typed Failure (or mark the one licensed logger catch with '$MARKER')." \
  "ok: no unlicensed 'catch (_)'"

echo "--- [2] stackless 'catch (e)' — no (e, st) capture ---"
# A bare catch(e) that does not also capture the stack trace loses it.
scan_catch 'catch\s*\(\s*[a-zA-Z_][a-zA-Z0-9_]*\s*\)' \
  "!! FAIL: stackless 'catch (e)' drops the trace. Use 'catch (e, st)' and log st." \
  "ok: no stackless 'catch (e)'"

echo "--- [3] 'throw e;' inside a catch (stack reset) ---"
# Heuristic: `throw <identifier>;` — rethrow preserves the original stack.
if $GREP $EXCL 'throw\s+[a-z][a-zA-Z0-9_]*\s*;' "$TARGET"; then
  echo "!! FAIL: 'throw e;' resets the stack. Use 'rethrow'." >&2
  fail=1
else
  echo "ok: no 'throw e;'"
fi

echo "--- [4] 'default:' / 'case _:' near a Failure switch ---"
# A default/wildcard defeats sealed exhaustiveness.
while IFS= read -r f; do
  if grep -qE 'switch\s*\(.*[Ff]ailure' "$f" 2>/dev/null \
     && grep -qnE '^\s*(default\s*:|case\s+_\s*(:|=>))' "$f" 2>/dev/null; then
    grep -nE '^\s*(default\s*:|case\s+_\s*(:|=>))' "$f"
    echo "   ^ in $f — a sealed Failure switch must have NO default:/case _ (defeats exhaustiveness)" >&2
    fail=1
  fi
done < <(grep -rlE --include=*.dart $EXCL '[Ff]ailure' "$TARGET" 2>/dev/null || true)
[ "$fail" -eq 0 ] && echo "ok: no default:/case _ on Failure switches"

if [ "$fail" -ne 0 ]; then
  echo "==> RESULT: violations found." >&2
  exit 1
fi
echo "==> RESULT: clean."
