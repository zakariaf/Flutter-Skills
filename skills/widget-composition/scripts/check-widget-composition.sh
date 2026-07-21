#!/usr/bin/env bash
set -euo pipefail
# Grep-based bans for widget-composition. Flags the mechanical anti-patterns a
# reviewer should never have to catch by eye. Not exhaustive — passing this is a
# floor, not proof. Run before a PR.
#
# Usage: scripts/check-widget-composition.sh [TARGET_DIR]   (default: lib/)

TARGET="${1:-lib}"

if [ ! -d "$TARGET" ]; then
  echo "check-widget-composition: target dir '$TARGET' not found" >&2
  exit 2
fi

fail=0
report() {
  # report <label> <grep-output>
  local label="$1" hits="$2"
  if [ -n "$hits" ]; then
    echo "✗ $label"
    echo "$hits" | sed 's/^/    /'
    fail=1
  fi
}

# 1. Widget-returning helper methods: `Widget _buildX(` — extract a class instead.
report "Widget _buildX() helper method (extract a Widget class)" \
  "$(grep -rnE '\bWidget[[:space:]]+_[a-zA-Z0-9]*[Bb]uild[a-zA-Z0-9]*[[:space:]]*\(' \
      --include='*.dart' "$TARGET" || true)"

# 2. GlobalKey used for identity/lookups — lift state to the ViewModel instead.
report "GlobalKey (use ValueKey(id); lift state to the Notifier)" \
  "$(grep -rnE '\bGlobalKey\b' --include='*.dart' "$TARGET" || true)"

# 3. Eager ListView over an unbounded mapped list — use ListView.builder.
report "ListView(children: ...map(...).toList()) (use .builder)" \
  "$(grep -rnE 'ListView\([^)]*children:.*\.map\(' --include='*.dart' "$TARGET" || true)"

# 4. Wall-clock read inside a widget file — inject a clock instead.
report "DateTime.now() in the widget layer (inject a clock)" \
  "$(grep -rnE 'DateTime\.now\(\)' --include='*.dart' "$TARGET" || true)"

# 5. autofocus: true — never open the IME over primary content at cold launch.
report "autofocus: true (opens IME over content)" \
  "$(grep -rnE 'autofocus:[[:space:]]*true' --include='*.dart' "$TARGET" || true)"

# 6. Hardcoded left/right insets — use EdgeInsetsDirectional (start/end) for RTL.
report "EdgeInsets.only(left:/right:) (use EdgeInsetsDirectional start/end)" \
  "$(grep -rnE 'EdgeInsets\.only\([^)]*(left|right):' --include='*.dart' "$TARGET" || true)"

# 7. Clamping the text scaler — never; fix the layout instead.
report "TextScaler clamp (never clamp; make the layout survive scale)" \
  "$(grep -rnE 'clamp\(' --include='*.dart' "$TARGET" | grep -iE 'textscal|scalefactor' || true)"

echo
if [ "$fail" -ne 0 ]; then
  echo "check-widget-composition: FAIL — review the hits above." >&2
  exit 1
fi
echo "check-widget-composition: OK ($TARGET)"
