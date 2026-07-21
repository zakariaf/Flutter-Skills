#!/usr/bin/env bash
# Usage: check-codegen-hygiene.sh [TARGET_DIR]   (TARGET_DIR default: lib/).
# Grep-based parity checks for the codegen policy. Prints findings; exits
# non-zero on any violation. Does NOT run build_runner. Run before a PR.
#
# Checks:
#   1. No hand-edit markers inside generated files.
#   2. Every EMITTED generated suffix (files exist on disk or tracked in git) is
#      present in analysis_options.yaml excludes. Suffixes the tree never produces
#      are reported informationally and do not fail the check.
#   3. Commit-policy parity: generated files are EITHER all gitignored OR the
#      repo carries a .gitattributes marking them linguist-generated (committed
#      strategy). A mix (tracked in git AND no .gitattributes) is flagged.
set -uo pipefail

TARGET_DIR="${1:-lib/}"

find_root() {
  local d="$PWD"
  while [ "$d" != "/" ]; do
    if [ -f "$d/pubspec.yaml" ]; then echo "$d"; return 0; fi
    d="$(dirname "$d")"
  done
  return 1
}

ROOT="$(find_root)" || { echo "ERROR: no pubspec.yaml found" >&2; exit 2; }
cd "$ROOT"
FAIL=0
echo "==> repo root: $ROOT  (scan target: $TARGET_DIR)"

SUFFIXES='\.(g|freezed|drift|mocks)\.dart$'

echo "==> [1] no hand-edit markers inside generated files"
GEN_FILES="$(find "$TARGET_DIR" -type f 2>/dev/null | grep -E "$SUFFIXES" || true)"
if [ -n "$GEN_FILES" ]; then
  HITS="$(echo "$GEN_FILES" | xargs grep -lE 'TODO|FIXME|HACK|hand-edit' 2>/dev/null || true)"
  if [ -n "$HITS" ]; then
    echo "   VIOLATION: edit markers inside generated files (never hand-edit):"
    echo "$HITS" | sed 's/^/     /'; FAIL=1
  fi
fi

echo "==> [2] emitted generated suffixes excluded from analysis_options.yaml"
AO="analysis_options.yaml"
# Only a suffix that is ACTUALLY emitted (files exist on disk or are tracked in
# git) needs an exclude. A repo that uses only json_serializable + riverpod (both
# *.g.dart, no freezed/drift) must not fail for the suffixes it never produces.
EMITTED="$(
  { find "$TARGET_DIR" -type f 2>/dev/null; git ls-files 2>/dev/null; } \
    | grep -E "$SUFFIXES" || true
)"
if [ -f "$AO" ]; then
  for suf in 'g.dart' 'freezed.dart' 'drift.dart' 'mocks.dart'; do
    if echo "$EMITTED" | grep -q "\.$suf$"; then
      # Suffix is emitted: a missing analyzer exclude is a real violation.
      if ! grep -q "\*\.$suf" "$AO"; then
        echo "   VIOLATION: *.$suf files exist but are not excluded in $AO"
        FAIL=1
      fi
    else
      # Suffix not produced in this tree: informational only, never a failure.
      echo "   NOTE: no *.$suf files present; analyzer exclude not required"
    fi
  done
else
  echo "   NOTE: no analysis_options.yaml at repo root"
fi

echo "==> [3] commit-policy parity (all-gitignored OR .gitattributes present)"
TRACKED_GEN="$(git ls-files 2>/dev/null | grep -E "$SUFFIXES" || true)"
if [ -n "$TRACKED_GEN" ]; then
  # Committed strategy: require a .gitattributes marking generated files.
  if [ ! -f ".gitattributes" ] || ! grep -q 'linguist-generated' ".gitattributes"; then
    echo "   VIOLATION: generated files are committed but .gitattributes does"
    echo "     not mark them linguist-generated. Either gitignore them or add"
    echo "     the marker AND a CI freshness (git diff --exit-code) gate."
    FAIL=1
  else
    echo "   committed strategy detected; ensure CI runs the freshness diff gate."
  fi
else
  echo "   gitignore strategy detected; ensure codegen runs FIRST in CI."
fi

if [ "$FAIL" -eq 0 ]; then
  echo "==> OK: codegen hygiene checks pass"
else
  echo "==> FAILED: fix the violations above" >&2
fi
exit "$FAIL"
