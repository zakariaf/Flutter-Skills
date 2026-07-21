#!/usr/bin/env bash
set -euo pipefail

# check_adaptive.sh — flag anti-patterns that break constraint-based layout.
# Usage: scripts/check_adaptive.sh [target-dir]   (defaults to lib/)
#
# Heuristic greps, not a compiler. It flags:
#   1. Platform/device branching used to pick a LAYOUT.
#   2. MediaQuery.of(context).size — should be MediaQuery.sizeOf(context).
#   3. Locking device orientation.
# Review each hit; suppress a justified line with a trailing `// adaptive-ok`.

TARGET_DIR="${1:-lib}"

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "check_adaptive: target directory '$TARGET_DIR' not found" >&2
  exit 2
fi

status=0

# Collect Dart files, excluding generated output.
mapfile -t files < <(
  find "$TARGET_DIR" -name '*.dart' \
    ! -name '*.g.dart' \
    ! -name '*.freezed.dart' \
    ! -name '*.gr.dart'
)

if [[ ${#files[@]} -eq 0 ]]; then
  echo "check_adaptive: no Dart files under '$TARGET_DIR'"
  exit 0
fi

# grep -nH over the file list, dropping any line marked adaptive-ok.
scan() {
  local label="$1" pattern="$2"
  local hits
  hits="$(grep -nHE "$pattern" "${files[@]}" 2>/dev/null | grep -v 'adaptive-ok' || true)"
  if [[ -n "$hits" ]]; then
    echo ""
    echo "✗ $label"
    echo "$hits"
    status=1
  fi
}

echo "check_adaptive: scanning $TARGET_DIR ..."

# 1. Platform/device checks — legitimate for PLUGINS, but a smell for layout.
#    Any Platform.is* / kIsWeb near a layout file warrants a human look.
scan "Platform/device branching (adapt by size, not device)" \
  '(Platform\.(isAndroid|isIOS|isMacOS|isWindows|isLinux|isFuchsia)|\bkIsWeb\b)'

# 2. MediaQuery.of(context).size — over-subscribes; use the sizeOf aspect getter.
scan "MediaQuery.of(context).size (use MediaQuery.sizeOf)" \
  'MediaQuery\.of\(\s*context\s*\)\.(size|padding|viewInsets|viewPadding)'

# 3. Forcing orientation — breaks tablets/foldables.
scan "setPreferredOrientations (do not lock orientation)" \
  'setPreferredOrientations'

echo ""
if [[ "$status" -eq 0 ]]; then
  echo "✓ check_adaptive: no adaptive-layout anti-patterns found"
else
  echo "✗ check_adaptive: issues found — fix, or annotate a justified line with // adaptive-ok"
fi

exit "$status"
