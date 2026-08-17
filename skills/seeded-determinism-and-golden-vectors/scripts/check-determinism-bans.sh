#!/usr/bin/env bash
set -euo pipefail
# Usage: check-determinism-bans.sh [TARGET_DIR]
#   TARGET_DIR  the generator's package or directory (default: lib/core/)
#
# Proves that nothing on the generation path can introduce a second source of entropy.
# One ambient Random(), one DateTime.now(), or one ordering derived from identityHashCode
# is enough to make output irreproducible on another device — and none of them fail a test
# that only ever runs once per process. Point this at the Flutter-free package or directory
# that holds the generator, and run it in CI.
#
# A hit is not automatically a defect: it is a place a decision must exist. Move the call to
# the composition root, thread the seed through, or narrow TARGET_DIR — never blanket-ignore.
# Exits non-zero on a hit.

TARGET_DIR="${1:-lib/core/}"

if [ ! -d "$TARGET_DIR" ]; then
  echo "check-determinism-bans: '$TARGET_DIR' not found" >&2
  exit 2
fi

status=0

report() {
  # $1 = human-readable rule, $2 = extended regex
  # grep output is path:line:content — strip rows whose CONTENT starts a comment.
  if hits="$(grep -rnE "$2" "$TARGET_DIR" --include='*.dart' 2>/dev/null \
      | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(//|\*|/\*)')"; then
    echo "FAIL: $1" >&2
    printf '%s\n' "$hits" >&2
    status=1
  fi
}

report "wall-clock read on the generation path — inject the key instead" \
  'DateTime\.now\(|clock\.now\(|DateTime\.timestamp\('

report "ambient randomness — draw from the injected seeded generator instead" \
  '\bRandom\(|Random\.secure\('

report "identity-hash ordering is not reproducible — sort by an explicit key first" \
  '\bidentityHashCode\b|\.hashCode\s*\.\s*compareTo|sort\(\(.*hashCode'

report "platform I/O in a pure generator" \
  "import\s+'dart:(io|ui)'"

report "Flutter import in a pure generator" \
  "import\s+'package:flutter/"

if [ "$status" -ne 0 ]; then
  echo "::error::check-determinism-bans: the generation path has more than one entropy source" >&2
  exit 1
fi

echo "check-determinism-bans: OK — $TARGET_DIR has a single, seeded entropy source"
