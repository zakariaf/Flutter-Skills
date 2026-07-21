#!/usr/bin/env bash
# Usage: check_raw_values.sh [target_dir]   (default: lib)
# Fails if a raw aesthetic value appears OUTSIDE a */theme/ directory. Design
# values belong in lib/theme/**; every other widget reads a ThemeExtension slot.
# A new need is a new token slot, never a // ignore.
set -euo pipefail

TARGET="${1:-lib}"
if [ ! -d "$TARGET" ]; then
  echo "note: '$TARGET' not found; nothing to scan."
  exit 0
fi

# Generated files are exempt.
GEN_RE='\.g\.dart$|\.freezed\.dart$|\.gr\.dart$'

# Banned raw-value patterns in feature/shared UI code. `Colors.`/`Curves.` are
# anchored with a non-identifier lookbehind so custom reads like `AppColors.of`
# or `MyCurves.foo` do not trip the gate.
PATTERNS='Color\(0x|Color\.fromARGB\(|Color\.fromRGBO\(|(^|[^A-Za-z0-9_])Colors\.|(^|[^A-Za-z0-9_])Curves\.|Duration\(milliseconds:|Duration\(seconds:|BorderRadius\.circular\([0-9]|Radius\.circular\([0-9]|fontSize:[[:space:]]*[0-9]'

# Legitimate exceptions. Neutralized (stripped) BEFORE the ban scan — not used to
# drop the whole line — so a banned value elsewhere on the same line still fails
# (e.g. `x ? Colors.transparent : Color(0xFFAA0000)` must not slip through).
ALLOW_STRIP='s/Colors\.transparent//g; s/Duration\.zero//g'

fail=0
while IFS= read -r -d '' f; do
  case "$f" in */theme/*) continue ;; esac
  if printf '%s\n' "$f" | grep -qE "$GEN_RE"; then continue; fi

  # sed preserves line count, so grep -n line numbers still match the source file.
  hits="$(sed -E "$ALLOW_STRIP" "$f" | grep -nE "$PATTERNS" || true)"
  if [ -n "$hits" ]; then
    echo "== $f =="
    printf '%s\n' "$hits"
    fail=1
  fi
done < <(find "$TARGET" -name '*.dart' -type f -print0)

if [ "$fail" -ne 0 ]; then
  echo "FAIL: raw aesthetic value(s) outside */theme/. Read a ThemeExtension slot, or add a token."
  exit 1
fi
echo "OK: no raw aesthetic values outside */theme/."
