#!/usr/bin/env bash
# Usage: check_font_bundling.sh [target_dir]   (default: lib)
# Bans runtime font fetching and silently no-op font variations:
#   - package:google_fonts ships an HTTP code path; bundle the font instead.
#   - FontVariation('opsz'|'ital', ...) no-ops silently on a font without the axis.
set -euo pipefail

TARGET="${1:-lib}"
if [ ! -d "$TARGET" ]; then
  echo "note: '$TARGET' not found; nothing to scan."
  exit 0
fi

fail=0

gf="$(grep -rnE "package:google_fonts/" --include='*.dart' "$TARGET" || true)"
if [ -n "$gf" ]; then
  echo "== google_fonts import (bundle the font in pubspec.yaml instead) =="
  printf '%s\n' "$gf"
  fail=1
fi

fv="$(grep -rnE "FontVariation\([[:space:]]*'(opsz|ital)'" --include='*.dart' "$TARGET" || true)"
if [ -n "$fv" ]; then
  echo "== FontVariation('opsz'|'ital') — verify the font actually ships that axis, or it no-ops silently =="
  printf '%s\n' "$fv"
  fail=1
fi

if [ "$fail" -ne 0 ]; then
  echo "FAIL: font bundling / variation issue(s) above."
  exit 1
fi
echo "OK: fonts bundled; no silent no-op font variations."
