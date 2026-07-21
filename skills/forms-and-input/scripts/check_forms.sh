#!/usr/bin/env bash
set -euo pipefail

# check_forms.sh — static guards for the forms-and-input skill.
#
# Fails on:
#   1. A TextEditingController or FocusNode created in a file that has no
#      dispose() override (likely a leak — dispose it or hold it in a Notifier).
#   2. A validator returning a hardcoded string literal (must be localized via
#      AppLocalizations, per i18n-rtl-l10n).
#   3. An async validator (validator: ... async) — async validation belongs in a
#      Notifier, never in the sync FormFieldValidator.
#
# Usage: scripts/check_forms.sh [target-dir]   (default: lib)

TARGET_DIR="${1:-lib}"

if [ ! -d "$TARGET_DIR" ]; then
  echo "check_forms: target dir '$TARGET_DIR' not found" >&2
  exit 2
fi

fail=0

# Collect Dart files, skipping generated artifacts.
mapfile -t dart_files < <(
  find "$TARGET_DIR" -name '*.dart' \
    ! -name '*.g.dart' \
    ! -name '*.freezed.dart' \
    ! -name '*.gr.dart' \
    ! -name '*.mocks.dart'
)

# ---- Check 1: controllers / focus nodes created without a dispose() ----------
echo "==> Checking TextEditingController / FocusNode disposal"
for f in "${dart_files[@]}"; do
  if grep -Eq '(TextEditingController|FocusNode)\(' "$f"; then
    if ! grep -Eq 'void[[:space:]]+dispose\(\)' "$f"; then
      echo "LEAK: $f creates a controller/FocusNode but has no dispose() override" >&2
      echo "      -> dispose it in State.dispose(), or hold the value in a Notifier" >&2
      fail=1
    fi
  fi
done

# ---- Check 2: async validators -----------------------------------------------
echo "==> Checking for async validators (must be sync)"
if grep -REn 'validator:[^,]*async' "$TARGET_DIR" \
    --include='*.dart' \
    --exclude='*.g.dart' --exclude='*.freezed.dart'; then
  echo "ASYNC VALIDATOR: a FormFieldValidator cannot be async." >&2
  echo "      -> move availability/uniqueness checks into a debounced Notifier" >&2
  fail=1
fi

# ---- Check 3: hardcoded validator return strings -----------------------------
# Heuristic: a `return '...';` on a line inside/near a validator context.
# We flag any `return 'literal';` in a file that declares a validator, since a
# localized message returns AppLocalizations.of(context).<key>, not a literal.
echo "==> Checking for hardcoded validator messages"
for f in "${dart_files[@]}"; do
  if grep -Eq 'validator:' "$f"; then
    # Match `return 'text';` or `? 'text' :` style literals that are not null.
    if grep -Enq "return[[:space:]]+['\"][^'\"]" "$f" \
       || grep -Enq "\?[[:space:]]*['\"][A-Za-z][^'\"]*['\"][[:space:]]*:" "$f"; then
      hits=$(grep -En "return[[:space:]]+['\"][^'\"]|\?[[:space:]]*['\"][A-Za-z][^'\"]*['\"][[:space:]]*:" "$f" || true)
      echo "HARDCODED MESSAGE in $f:" >&2
      echo "$hits" >&2
      echo "      -> return AppLocalizations.of(context).<key>, not a literal" >&2
      fail=1
    fi
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "" >&2
  echo "check_forms: FAILED" >&2
  exit 1
fi

echo "check_forms: OK"
