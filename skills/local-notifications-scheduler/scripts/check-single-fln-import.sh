#!/usr/bin/env bash
# Usage: check-single-fln-import.sh [TARGET_DIR]   (default: lib/)
# Fail if flutter_local_notifications is imported anywhere except the single
# approved adapter file. The plugin must live behind the NotificationGateway port.
set -euo pipefail

ROOT="${1:-lib}"
ALLOWED="fln_notification_gateway.dart"

echo "== Checking single flutter_local_notifications import under $ROOT =="

if command -v rg >/dev/null 2>&1; then
  GREP() { rg -l --glob '*.dart' "$1" "$2" 2>/dev/null || true; }
else
  GREP() { grep -rEl "$1" "$2" --include='*.dart' 2>/dev/null || true; }
fi

hits="$(GREP "package:flutter_local_notifications" "$ROOT")"

violations=""
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    */"$ALLOWED") ;;                 # allowed
    *) violations="${violations}${f}"$'\n' ;;
  esac
done <<< "$hits"

if [ -n "${violations//[$'\n ']/}" ]; then
  echo "VIOLATION: flutter_local_notifications imported outside $ALLOWED:"
  echo "$violations"
  exit 1
fi

echo "OK: flutter_local_notifications is imported only in $ALLOWED (or not yet present)."
