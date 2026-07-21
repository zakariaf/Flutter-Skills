#!/usr/bin/env bash
# Usage: check-softdelete-parity.sh [TARGET_DIR]   (default: lib/)
# Soft-delete parity: analytics / rollup / chart queries must read through the
# shared active-only filter/view, never a base table directly, or deleted rows
# silently pollute reports. Prints suspected offenders; exits non-zero on any.
# Portable to bash 3.2 (macOS default): no mapfile.
set -uo pipefail

TARGET="${1:-lib/}"
if [ ! -d "$TARGET" ]; then
  echo "==> target dir not found: $TARGET (nothing to scan)"
  exit 0
fi
echo "==> scanning analytics/rollup/chart query code under: $TARGET"

# Tables that carry is_deleted and must be read via *_active views / activeOnly.
# Neutral generic names — adjust for your schema, or override via env GUARDED.
GUARDED="${GUARDED:-orders|tasks|products|accounts|items|reminders|notes}"
# The sanctioned filtered access points.
SANCTIONED='_active|activeOnly|deletedFilter|is_deleted|isDeleted'

# Files that look like report/analytics/chart producers.
files=()
while IFS= read -r f; do files+=("$f"); done < <(
  grep -rilE --include=*.dart 'analytics|rollup|chart|projection|stat|report|dashboard' \
    "$TARGET" 2>/dev/null | grep -vE '\.g\.dart|\.drift\.dart|\.freezed\.dart|_test\.dart' || true)

if [ "${#files[@]}" -eq 0 ]; then
  echo "ok: no analytics/rollup/chart query files present yet (nothing to scan)"
  exit 0
fi

fail=0
for f in "${files[@]}"; do
  # Lines that select from / reference a guarded base table...
  hits="$(grep -nE "select\(.*($GUARDED)|from[[:space:]]+($GUARDED)|\b($GUARDED)\b" "$f" 2>/dev/null || true)"
  [ -z "$hits" ] && continue
  # ...but the file never references a sanctioned filtered access point.
  if ! grep -qE "$SANCTIONED" "$f" 2>/dev/null; then
    echo "!! $f reads a guarded table but never uses the shared active-only filter:" >&2
    echo "$hits" | sed 's/^/     /'
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "==> RESULT: possible soft-delete leaks — deleted rows may pollute analytics/charts." >&2
  echo "    Route every read through the *_active view or activeOnly() builder." >&2
  exit 1
fi
echo "==> RESULT: all analytics/rollup/chart readers reference the shared filter. clean."
