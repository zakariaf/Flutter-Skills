#!/usr/bin/env bash
set -euo pipefail

# check_routing.sh — static guardrails for navigation-and-routing.
#
# Enforces:
#   1. Exactly ONE GoRouter(...) construction in the tree.
#   2. That single GoRouter lives under a routing/ directory.
#   3. No imperative string-route navigation mixed in (Navigator.pushNamed / of(context).push).
#   4. No domain identity smuggled through state.extra (extra as <NonNull>, extra! reads).
#
# Usage: scripts/check_routing.sh [TARGET_DIR]   (defaults to lib/)

TARGET_DIR="${1:-lib}"

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "check_routing: target dir '$TARGET_DIR' not found" >&2
  exit 2
fi

fail=0
note() { echo "  - $1"; }

dart_files() {
  find "$TARGET_DIR" -name '*.dart' \
    ! -name '*.g.dart' ! -name '*.freezed.dart' -print0
}

# --- 1 & 2: exactly one GoRouter, and it is under routing/ --------------------
router_hits="$(grep -rEln 'GoRouter\s*\(' "$TARGET_DIR" \
  --include='*.dart' 2>/dev/null | grep -v '.g.dart' || true)"
router_count="$(printf '%s' "$router_hits" | grep -c . || true)"

if [[ "$router_count" -eq 0 ]]; then
  echo "FAIL: no GoRouter(...) found under $TARGET_DIR — the app must have one router."
  fail=1
elif [[ "$router_count" -gt 1 ]]; then
  echo "FAIL: found $router_count GoRouter(...) constructions — there must be exactly ONE:"
  printf '%s\n' "$router_hits" | while read -r f; do note "$f"; done
  fail=1
else
  if ! printf '%s' "$router_hits" | grep -q '/routing/'; then
    echo "FAIL: the single GoRouter is not under a routing/ directory:"
    note "$router_hits"
    fail=1
  else
    echo "OK: exactly one GoRouter, under routing/."
  fi
fi

# --- 3: no string-route imperative navigation --------------------------------
named_hits="$(grep -rEn \
  'Navigator\.(of\([^)]*\)\.)?push(Named|ReplacementNamed)|Navigator\.pushNamed' \
  "$TARGET_DIR" --include='*.dart' 2>/dev/null | grep -v '.g.dart' || true)"
if [[ -n "$named_hits" ]]; then
  echo "FAIL: imperative string-route navigation mixed with go_router — use context.go/push:"
  printf '%s\n' "$named_hits" | while read -r l; do note "$l"; done
  fail=1
else
  echo "OK: no Navigator.pushNamed / string routes."
fi

# --- 4: no identity via state.extra ------------------------------------------
# A non-null cast of extra, or extra!, means identity depends on a live object
# that is null on cold start / after process death. Identity belongs in path params.
# The trailing [^?A-Za-z0-9_] forces the whole type identifier to be consumed
# (no backtracking) so a nullable cast `extra as Item?` (the allowed fast-path)
# is NOT flagged, while a non-null `extra as Item` (required identity) IS.
extra_hits="$(grep -rEn \
  '\.extra\s+as\s+[A-Z][A-Za-z0-9_]*[^?A-Za-z0-9_]|\.extra!' \
  "$TARGET_DIR" --include='*.dart' 2>/dev/null | grep -v '.g.dart' || true)"
if [[ -n "$extra_hits" ]]; then
  echo "FAIL: state.extra used as required identity (null on deep link / restart) — put the id in path params:"
  printf '%s\n' "$extra_hits" | while read -r l; do note "$l"; done
  fail=1
else
  echo "OK: no required-identity reads of state.extra."
fi

if [[ "$fail" -ne 0 ]]; then
  echo
  echo "check_routing: FAILED"
  exit 1
fi

echo
echo "check_routing: PASSED"
