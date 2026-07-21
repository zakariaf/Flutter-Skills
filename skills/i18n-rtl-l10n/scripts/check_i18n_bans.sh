#!/usr/bin/env bash
# check_i18n_bans.sh — grep gate for the i18n/RTL discipline. Flags physical-side
# geometry, non-adaptive directional icons, raw-ASCII-digit interpolation, legacy bidi
# embeddings, and runtime font fetch. Prints offenders; exits non-zero on any hit.
#
# Usage: scripts/check_i18n_bans.sh [target-dir]
#   target-dir defaults to lib/. Excludes generated files (*.g.dart, *.freezed.dart,
#   app_localizations*.dart) since those are not hand-authored.
set -euo pipefail

TARGET="${1:-lib}"
if [[ ! -d "$TARGET" ]]; then
  echo "FAIL: target dir not found: $TARGET" >&2
  exit 2
fi

status=0

# Run a banned-pattern scan. $1 = label, $2 = extended-regex.
scan() {
  local label="$1" pattern="$2"
  local hits
  hits="$(grep -rnE "$pattern" "$TARGET" --include='*.dart' 2>/dev/null \
    | grep -vE '\.(g|freezed)\.dart:' \
    | grep -vE 'app_localizations.*\.dart:' || true)"
  if [[ -n "$hits" ]]; then
    status=1
    echo "== BANNED: $label =="
    echo "$hits"
    echo
  fi
}

# 1. Physical-side geometry — bypasses RTL mirroring. Use *Directional / start / end.
scan "physical-side geometry (EdgeInsets.only left/right, Alignment.centerLeft/Right, Positioned left/right, TextAlign.left/right)" \
  'EdgeInsets\.only\([^)]*(left|right):|Alignment\.center(Left|Right)|Positioned\((.*,)?[[:space:]]*(left|right):|TextAlign\.(left|right)|BorderRadius\.only\([^)]*(topLeft|topRight|bottomLeft|bottomRight):'

# 2. Non-adaptive directional icons — use Icons.adaptive.arrow_*.
scan "non-adaptive directional icons (Icons.arrow_back / arrow_forward)" \
  'Icons\.arrow_(back|forward)([^_]|$)'

# 3. Number spliced into a string via .toString() — route through numberFormatFor + ICU.
#    (A precise "$var inside a literal" check needs a Dart parser; this catches the common
#    concatenation smell without false-positiving every interpolation.)
scan "number splice (' + n.toString()') — use numberFormatFor + ICU placeholder" \
  '\+[[:space:]]*[A-Za-z_][A-Za-z0-9_.]*\.toString\(\)'

# 4. Legacy bidi embeddings — use isolate controls (FSI/LRI/RLI/PDI), not LRE/RLE/LRO/RLO.
scan "legacy bidi embeddings (U+202A..U+202E) — use isolates instead" \
  $'‪|‫|‬|‭|‮'

# 5. Runtime font fetch — bundle fonts with fallback instead in an offline/no-telemetry app.
scan "runtime font fetch (google_fonts)" \
  'package:google_fonts/'

if [[ "$status" -eq 0 ]]; then
  echo "i18n bans: PASS"
else
  echo "i18n bans: FAIL (see above)"
fi
exit "$status"
