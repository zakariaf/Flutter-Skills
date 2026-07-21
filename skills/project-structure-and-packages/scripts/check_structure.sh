#!/usr/bin/env bash
set -euo pipefail
# Usage: scripts/check_structure.sh [TARGET_DIR]
# Flags structural smells in a Flutter/Dart source tree:
#   - junk-drawer folders (utils/ helpers/ common/ misc/) — NOT core/, which is the
#     sanctioned pure-foundation layer (feature-first layout; see SKILL.md)
#   - barrel files inside an app package (data.dart / features.dart siblings of a folder)
#   - MethodChannel constructed outside services/native/
# Defaults TARGET_DIR to lib/. Hardcodes no app-specific path. Exits non-zero on any hit.
# There is deliberately NO depth check: feature-first naturally nests
# (features/<f>/presentation/widgets/) — the rule is "no grab-bags", not "shallow".

TARGET_DIR="${1:-lib}"
TARGET_DIR="${TARGET_DIR%/}"   # normalize: a trailing slash would inflate base_depth

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "check_structure: '$TARGET_DIR' is not a directory" >&2
  exit 2
fi

status=0

# 1. Junk-drawer folders. 'core/' is NOT flagged — it is the sanctioned pure-foundation
#    layer. Only genuinely unnamed catch-alls are smells.
junk="$(find "$TARGET_DIR" -type d \
  \( -name utils -o -name helpers -o -name common -o -name misc \) \
  2>/dev/null || true)"
if [[ -n "$junk" ]]; then
  echo "FAIL: junk-drawer folder(s) — name every helper by its owner:" >&2
  echo "$junk" | sed 's/^/  /' >&2
  status=1
fi

# 2. Barrel files inside an app. A directory FOO/ next to FOO.dart that only exports.
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  if grep -Eq '^\s*export ' "$f" && ! grep -Eq '^\s*(class|final|sealed|abstract|enum|mixin|typedef|void|const|final|extension) ' "$f"; then
    dir="${f%.dart}"
    if [[ -d "$dir" ]]; then
      echo "FAIL: barrel file in an app package (add nothing, cost analyzer time): $f" >&2
      status=1
    fi
  fi
done < <(find "$TARGET_DIR" -type f -name '*.dart' 2>/dev/null || true)

# 3. MethodChannel outside services/native/ (or native/).
mc="$(grep -rn 'MethodChannel(' "$TARGET_DIR" --include='*.dart' 2>/dev/null \
  | grep -Ev '/(services/native|native)/' || true)"
if [[ -n "$mc" ]]; then
  echo "FAIL: MethodChannel constructed outside services/native/ (unfakeable, unreviewable):" >&2
  echo "$mc" | sed 's/^/  /' >&2
  status=1
fi

if (( status == 0 )); then
  echo "check_structure: OK ($TARGET_DIR)"
fi
exit "$status"
