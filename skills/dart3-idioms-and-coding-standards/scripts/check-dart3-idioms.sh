#!/usr/bin/env bash
set -euo pipefail
# check-dart3-idioms.sh — grep-based Dart 3 idiom gate. Run before a PR.
# Usage: scripts/check-dart3-idioms.sh [TARGET_DIR]   (TARGET_DIR defaults to lib/)
#
# HARD failures (exit 1): banned packages and experiment flags — never justified.
# ADVISORIES (reported, non-fatal): constructs that need a same-line justification
#   or reviewer eyes (default:/case _:, late, `!`, Map<String,dynamic>, SCREAMING_CAPS).
# Generated files (*.g.dart / *.freezed.dart / *.drift.dart) are skipped.

TARGET_DIR="${1:-lib}"
if [[ ! -d "$TARGET_DIR" ]]; then
  echo "check-dart3-idioms: target dir '$TARGET_DIR' not found" >&2
  exit 2
fi

# Collect Dart sources, excluding generated output (portable to bash 3.2).
FILES=()
while IFS= read -r f; do
  FILES+=("$f")
done < <(
  find "$TARGET_DIR" -type f -name '*.dart' \
    ! -name '*.g.dart' ! -name '*.freezed.dart' ! -name '*.drift.dart'
)
if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "check-dart3-idioms: no Dart files under '$TARGET_DIR'"
  exit 0
fi

hard_fail=0
advisory=0

hard() {  # description, extended-regex
  local hits
  hits="$(grep -nHE -e "$2" "${FILES[@]}" || true)"
  if [[ -n "$hits" ]]; then
    echo "HARD  $1"
    echo "$hits" | sed 's/^/      /'
    hard_fail=1
  fi
}

warn() {  # description, extended-regex
  local hits
  hits="$(grep -nHE -e "$2" "${FILES[@]}" || true)"
  if [[ -n "$hits" ]]; then
    echo "WARN  $1"
    echo "$hits" | sed 's/^/      /'
    advisory=1
  fi
}

echo "== HARD bans =="
hard "banned model/error packages (equatable/fpdart/dartz) — freezed is allowed for non-trivial value types" \
  "^\s*import\s+'package:(equatable|fpdart|dartz)/"
hard "experiment flag reference (--enable-experiment)" \
  "--enable-experiment"

echo "== Advisories (justify in review or refactor) =="
warn "default:/case _: — banned on a sealed type or enum switch (verify the subject)" \
  "^\s*(default:|case\s+_\s*(when|=>|:))"
warn "late field — allowed ONLY for a genuinely once-initialized field, with a comment" \
  "^\s*late\s+"
warn "Map<String, dynamic> — parse into a typed model at the boundary" \
  "Map<\s*String\s*,\s*dynamic\s*>"
warn "SCREAMING_CAPS constant — constants are lowerCamelCase" \
  "^\s*(static\s+)?const\s+[A-Z][A-Z0-9]*(_[A-Z0-9]+)+\b"

echo
if [[ $hard_fail -ne 0 ]]; then
  echo "FAIL: hard bans present."
  exit 1
fi
if [[ $advisory -ne 0 ]]; then
  echo "OK with advisories: review each WARN above (each may need a justification comment)."
  exit 0
fi
echo "OK: no idiom violations found."
