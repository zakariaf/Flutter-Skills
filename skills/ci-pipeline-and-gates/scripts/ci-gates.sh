#!/usr/bin/env bash
set -euo pipefail
# ci-gates.sh — reproduce the blocking CI gates locally before a PR.
# Usage: scripts/ci-gates.sh [TARGET_DIR]   (TARGET_DIR defaults to lib)
#
# Runs the same fail-fast checks the workflow's `verify` job runs, in the same
# order, so a red PR is caught on the laptop. Each gate is a hard failure — this
# script never blesses and never commits; it never formats-in-place and never
# updates goldens. The one thing it DOES write is the freshness step (3): it runs
# the generator, so it regenerates code on disk — the intended local behaviour,
# identical to running build_runner yourself before committing. Fix the source,
# do not silence the gate.

TARGET_DIR="${1:-lib}"

fail() { echo "::error::$*" >&2; exit 1; }
step() { echo ""; echo "==> $*"; }

# 1. Format — fail on any unformatted byte (do NOT write fixes here).
step "dart format (check only)"
dart format --output=none --set-exit-if-changed . \
  || fail "Unformatted code. Run: dart format ."

# 2. Analyze — --fatal-infos promotes analyzer infos to errors.
step "flutter analyze --fatal-infos"
flutter analyze --fatal-infos \
  || fail "Analyzer findings. Fix them; do not // ignore: a gate."

# 3. Codegen freshness — generate, then diff. A nonzero diff means stale output.
if grep -rql "part '.*\.g\.dart'" "$TARGET_DIR" 2>/dev/null \
   || grep -rql "build_runner" pubspec.yaml 2>/dev/null; then
  step "codegen freshness (build_runner + git diff)"
  dart run build_runner build --delete-conflicting-outputs
  git diff --exit-code -- '*.g.dart' '*.freezed.dart' '*.drift.dart' \
    || fail "Generated code is stale. Run build_runner and commit the result."
fi

# 4. Static greps — the invariants no lint can see.
step "static banned-string greps"
"$(dirname "$0")/banned-strings.sh" "$TARGET_DIR"

# 5. Tests — randomized order surfaces inter-test state leakage.
step "flutter test (randomized order)"
flutter test --test-randomize-ordering-seed random --reporter expanded \
  || fail "Tests failed."

echo ""
echo "All local CI gates passed. Reminder: green here proves compilation,"
echo "format, analysis, freshness, and tests — NOT audio, real-font rendering,"
echo "or on-device behaviour. Do the manual on-device pass before release."
