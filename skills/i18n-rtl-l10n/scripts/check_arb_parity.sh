#!/usr/bin/env bash
# check_arb_parity.sh — verify every locale ARB has the same message keys and the same
# placeholder names as the template (app_en.arb). Prints findings; exits non-zero on mismatch.
#
# Usage: scripts/check_arb_parity.sh [arb-dir]
#   arb-dir defaults to lib/l10n. jq is used when present (needed for placeholder diffing).
set -euo pipefail

ARB_DIR="${1:-lib/l10n}"
TEMPLATE="app_en.arb"

if [[ ! -d "$ARB_DIR" ]]; then
  echo "FAIL: arb dir not found: $ARB_DIR" >&2
  exit 2
fi
cd "$ARB_DIR"
if [[ ! -f "$TEMPLATE" ]]; then
  echo "FAIL: template not found: $ARB_DIR/$TEMPLATE" >&2
  exit 2
fi

# Discover locale ARBs (every app_*.arb except the template).
LOCALE_FILES=()
for f in app_*.arb; do
  [[ "$f" == "$TEMPLATE" ]] && continue
  LOCALE_FILES+=("$f")
done
if [[ ${#LOCALE_FILES[@]} -eq 0 ]]; then
  echo "FAIL: no locale ARB files (app_*.arb) beside the template" >&2
  exit 2
fi

# Message keys = top-level keys not starting with '@'.
keys_of() {
  if command -v jq >/dev/null 2>&1; then
    jq -r 'keys[] | select(startswith("@") | not)' "$1" | sort
  else
    grep -oE '"[^"@][^"]*"[[:space:]]*:' "$1" \
      | sed -E 's/^"//; s/"[[:space:]]*:$//' | sort -u
  fi
}

# Sorted placeholder names declared in the template's @key metadata for a given key.
placeholders_of() {
  if command -v jq >/dev/null 2>&1; then
    jq -r --arg k "@$2" '.[$k].placeholders // {} | keys | sort | join(" ")' "$1"
  else
    echo "" # placeholder diffing requires jq
  fi
}

status=0
TEMPLATE_KEYS="$(keys_of "$TEMPLATE")"
TCOUNT="$(printf '%s\n' "$TEMPLATE_KEYS" | grep -c . || true)"
echo "== ARB parity check =="
echo "template: $TEMPLATE ($TCOUNT keys)"
echo

for f in "${LOCALE_FILES[@]}"; do
  loc="${f#app_}"; loc="${loc%.arb}"
  LKEYS="$(keys_of "$f")"

  missing="$(comm -23 <(printf '%s\n' "$TEMPLATE_KEYS") <(printf '%s\n' "$LKEYS") || true)"
  extra="$(comm -13 <(printf '%s\n' "$TEMPLATE_KEYS") <(printf '%s\n' "$LKEYS") || true)"

  loc_status="OK"
  if [[ -n "$missing" ]]; then
    loc_status="FAIL"; status=1
    echo "[$loc] MISSING keys:"; printf '    %s\n' $missing
  fi
  if [[ -n "$extra" ]]; then
    loc_status="FAIL"; status=1
    echo "[$loc] EXTRA keys (not in template):"; printf '    %s\n' $extra
  fi

  # Placeholder parity: the locale message must reference every placeholder the template declares.
  if command -v jq >/dev/null 2>&1; then
    while IFS= read -r key; do
      [[ -z "$key" ]] && continue
      want="$(placeholders_of "$TEMPLATE" "$key")"
      [[ -z "$want" ]] && continue
      val="$(jq -r --arg k "$key" '.[$k] // ""' "$f")"
      for name in $want; do
        if [[ "$val" != *"{$name"* ]]; then
          loc_status="FAIL"; status=1
          echo "[$loc] key '$key' does not use placeholder {$name}"
        fi
      done
    done <<< "$TEMPLATE_KEYS"
  fi

  echo "[$loc] $loc_status"
done

echo
if [[ "$status" -eq 0 ]]; then
  echo "ARB parity: PASS"
else
  echo "ARB parity: FAIL (see above)"
fi
exit "$status"
