#!/usr/bin/env bash
set -euo pipefail
# banned-strings.sh — grep-based invariant gate over Dart source.
# Usage: scripts/banned-strings.sh [TARGET_DIR]   (TARGET_DIR defaults to lib)
#
# The shell twin of test/policy/*: for invariants that are textually decidable,
# silent when broken, and one line to break. It strips // line comments before
# matching (a rule's own explanation contains its needle), anchors each needle to
# a structure, ACCUMULATES every offender, and fails ONCE with the full list.
#
# Edit the RULES table to fit the app. Every entry is a promise kept forever —
# do not add taste (a widget modifier, a `default:` on a sealed type); false
# positives get the gate deleted. Architecture-only bans belong in a dep review.

TARGET_DIR="${1:-lib}"
[ -d "$TARGET_DIR" ] || { echo "::error::no such dir: $TARGET_DIR" >&2; exit 1; }

# Comment-stripped view of a Dart file (line comments only; keeps it dependency-free).
# sed runs per line, so `.*` eats the rest of the line after `//`. Caveat: this
# also strips `//` inside a string literal (e.g. a URL) — never ban a needle that
# can legitimately live inside a URL-shaped string.
strip_comments() { sed -E 's,//.*,,' "$1"; }

# Each rule: "REGEX|human reason". REGEX is matched against comment-stripped source.
# Anchor to a structure: an import line, a symbol — never a bare word.
RULES=(
  "^[[:space:]]*import[[:space:]]+['\"]package:http/|package:http breaks the no-network promise"
  "^[[:space:]]*import[[:space:]]+['\"]package:dio/|package:dio breaks the no-network promise"
  "^[[:space:]]*import[[:space:]]+['\"]package:sentry_flutter/|a crash reporter phones home; the crash log stays on-device"
  "\bHttpClient\b|dart:io HttpClient has no legitimate use in this layer"
  "\bwithClampedTextScaling\b|clamping text scale silently defeats the large-text a11y matrix"
  "\btextScaleFactor\b|textScaleFactor is deprecated and clamps scale; use TextScaler"
)

offenders=""
while IFS= read -r -d '' file; do
  # Skip generated output — nobody hand-edits it; scanning it invites false positives.
  case "$file" in *.g.dart|*.freezed.dart|*.drift.dart) continue;; esac
  stripped="$(strip_comments "$file")"
  for rule in "${RULES[@]}"; do
    regex="${rule%%|*}"
    reason="${rule#*|}"
    while IFS= read -r line; do
      [ -n "$line" ] && offenders+="  ${file}: ${line} — ${reason}"$'\n'
    done < <(printf '%s\n' "$stripped" | grep -nE "$regex" || true)
  done
done < <(find "$TARGET_DIR" -name '*.dart' -type f -print0)

if [ -n "$offenders" ]; then
  echo "::error::banned-string gate found forbidden source (fix the code, not the gate):" >&2
  printf '%s' "$offenders" >&2
  exit 1
fi

echo "banned-strings: $TARGET_DIR is clean."
