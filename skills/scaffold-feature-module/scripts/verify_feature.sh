#!/usr/bin/env bash
# verify_feature.sh — grep-based boundary checks for feature folders, then analyze.
#
# Usage:   scripts/verify_feature.sh [target-dir]
# Example: scripts/verify_feature.sh              # scans lib/
#          scripts/verify_feature.sh lib/features/task_list
#
# Checks (no build needed):
#   1) no cross-feature imports (a feature must never import another feature's folder)
#   2) Directional-only geometry (no EdgeInsets.left/right, Alignment.*Left/Right, TextAlign.left)
#   3) no store leak into a View/ViewModel (package:drift, Companion, secure storage, platform channel)
#   4) no DateTime.now() in feature code (inject a Clock)
#   5) no _buildX() widget-returning methods (extract widget classes)
#   6) no navigation from a *_view_model.dart (controllers publish state, the View navigates)
# Then runs `dart analyze` if the toolchain is on PATH.
set -uo pipefail

TARGET="${1:-lib}"
if [[ ! -d "$TARGET" ]]; then
  echo "usage: $(basename "$0") [target-dir]   (dir not found: $TARGET)" >&2
  exit 2
fi

status=0
fail() { echo "  FAIL: $*"; status=1; }
ok()   { echo "  OK:   $*"; }

echo "== verify_feature: $TARGET =="

echo "[1] no cross-feature imports"
# A file under features/<a>/ importing another features/<b>/ (relative or package) is a sideways dep.
XF=$(grep -rnE "import .*features/[a-z0-9_]+/" "$TARGET" --include='*.dart' 2>/dev/null \
      | awk -F: '{ path=$1; imp=$0;
          match(path, /features\/[a-z0-9_]+\//); self=substr(path, RSTART, RLENGTH);
          if (imp !~ self && imp ~ /features\/[a-z0-9_]+\//) print }' || true)
[[ -n "$XF" ]] && { fail "feature imports another feature's folder:"; printf '        %s\n' "$XF"; } || ok "none"

echo "[2] Directional-only geometry"
GEO=$(grep -rnE 'EdgeInsets\.only\([^)]*(left|right):|Alignment\.(center|top|bottom)(Left|Right)|Positioned\((left|right):|TextAlign\.(left|right)\b' \
      "$TARGET" --include='*.dart' 2>/dev/null || true)
[[ -n "$GEO" ]] && { fail "non-directional geometry (use EdgeInsetsDirectional / AlignmentDirectional):"; printf '        %s\n' "$GEO"; } || ok "none"

echo "[3] no store leak into View/ViewModel"
LEAK=$(grep -rnE 'package:drift/|[A-Za-z]+Companion\b|flutter_secure_storage|MethodChannel' \
      "$TARGET" --include='*_screen.dart' --include='*_notifier.dart' --include='*_view_model.dart' --include='*_view.dart' 2>/dev/null || true)
[[ -n "$LEAK" ]] && { fail "store/channel symbol in a View/ViewModel (go through a repository):"; printf '        %s\n' "$LEAK"; } || ok "none"

echo "[4] no DateTime.now() in feature code"
NOW=$(grep -rnE 'DateTime\.now\(\)|DateTime\.timestamp\(\)' "$TARGET" --include='*.dart' 2>/dev/null || true)
[[ -n "$NOW" ]] && { fail "DateTime.now() found (inject a Clock provider):"; printf '        %s\n' "$NOW"; } || ok "none"

echo "[5] no _buildX() widget methods"
BUILDX=$(grep -rnE '\bWidget\s+_build[A-Z][A-Za-z0-9]*\s*\(' "$TARGET" --include='*.dart' 2>/dev/null || true)
[[ -n "$BUILDX" ]] && { fail "_buildX() method returning a Widget (extract a widget class):"; printf '        %s\n' "$BUILDX"; } || ok "none"

echo "[6] no navigation from a ViewModel"
NAV=$(grep -rnE '\.go\(|\.push\(|Navigator\.' "$TARGET" --include='*_notifier.dart' --include='*_view_model.dart' 2>/dev/null || true)
[[ -n "$NAV" ]] && { fail "navigation inside a ViewModel (navigate from the View/redirect):"; printf '        %s\n' "$NAV"; } || ok "none"

echo "[7] analyze"
if command -v dart >/dev/null 2>&1; then
  dart analyze "$TARGET" || fail "dart analyze reported issues"
else
  echo "  SKIP: dart not on PATH"
fi

echo
if [[ "$status" -eq 0 ]]; then echo "verify: PASS"; else echo "verify: FAIL (see above)"; fi
exit "$status"
