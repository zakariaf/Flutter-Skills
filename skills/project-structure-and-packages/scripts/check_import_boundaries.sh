#!/usr/bin/env bash
set -euo pipefail
# Usage: scripts/check_import_boundaries.sh [TARGET_DIR]
# Enforces import-boundary discipline that pub cannot see inside one package:
#   - no relative imports mixed in (always_use_package_imports) — two paths = two runtime types
#   - no import of another package's private lib/src/
#   - pure-Dart directories (the app's lib/core/, any dir named with a *_core suffix,
#     or a PURE_DIR override) import no flutter / dart:io / dart:ui and read no wall clock.
#     lib/core/ is the sanctioned pure-foundation layer (D1) and MUST stay Flutter-free.
# Defaults TARGET_DIR to lib/. Set PURE_DIR to add an extra pure-Dart root to check.
# IMPORTANT: auto-detection matches the app's 'core' folder and any dir named *_core. A pure package
# with a plain generic name (money, scheduling) is NOT found automatically and
# MUST be passed via PURE_DIR, e.g. PURE_DIR=packages/money scripts/check_import_boundaries.sh
# — otherwise it silently escapes the Flutter/dart:io/dart:ui/wall-clock firewall.
# Hardcodes no app-specific path. Exits non-zero on any hit.

TARGET_DIR="${1:-lib}"
PURE_DIR="${PURE_DIR:-}"

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "check_import_boundaries: '$TARGET_DIR' is not a directory" >&2
  exit 2
fi

status=0

# 1. Relative imports of local .dart files (banned; use package: imports).
#    Allows relative imports of generated parts via 'part'/'part of' (not 'import').
rel="$(grep -rnE "^\s*import\s+'[^:]*\.dart'" "$TARGET_DIR" --include='*.dart' 2>/dev/null || true)"
if [[ -n "$rel" ]]; then
  echo "FAIL: relative import(s) — use package: imports (mixing paths yields two runtime types):" >&2
  echo "$rel" | sed 's/^/  /' >&2
  status=1
fi

# 2. Importing another package's private lib/src/ across a package boundary.
srcimp="$(grep -rnE "import\s+'package:[a-z0-9_]+/src/" "$TARGET_DIR" --include='*.dart' 2>/dev/null || true)"
if [[ -n "$srcimp" ]]; then
  echo "FAIL: import of another package's lib/src/ — import its public barrel instead:" >&2
  echo "$srcimp" | sed 's/^/  /' >&2
  status=1
fi

# 3. Purity of pure-Dart directories: the app's own 'core' folder, any directory whose
#    name ends in _core, plus an optional PURE_DIR override.
pure_roots="$(find "$TARGET_DIR" -type d \( -name core -o -name '*_core' \) 2>/dev/null || true)"
[[ -n "$PURE_DIR" && -d "$PURE_DIR" ]] && pure_roots="$pure_roots"$'\n'"$PURE_DIR"

while IFS= read -r root; do
  [[ -z "$root" ]] && continue
  hits="$(grep -rnE "package:flutter/|dart:io|dart:ui|DateTime\.(now|timestamp)\(" \
    "$root" --include='*.dart' 2>/dev/null || true)"
  if [[ -n "$hits" ]]; then
    echo "FAIL: pure-Dart root '$root' breaks the compile firewall (Flutter/IO/ui/wall-clock):" >&2
    echo "$hits" | sed 's/^/  /' >&2
    status=1
  fi
done <<<"$pure_roots"

if (( status == 0 )); then
  echo "check_import_boundaries: OK ($TARGET_DIR)"
fi
exit "$status"
