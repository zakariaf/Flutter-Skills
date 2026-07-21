#!/usr/bin/env bash
# Usage: check-adhoc-schedule-calls.sh [TARGET_DIR]   (default: lib/features)
# Fail if feature code calls gateway.schedule()/cancel() directly instead of
# routing every change through the single syncNotifications() reconcile entrypoint.
set -euo pipefail

ROOT="${1:-lib/features}"

echo "== Checking for ad-hoc gateway.schedule/cancel calls under $ROOT =="

if [ ! -d "$ROOT" ]; then
  echo "SKIP: $ROOT not found."
  exit 0
fi

hits="$(grep -rnE '\.(schedule|cancel|cancelAll)\(' "$ROOT" --include='*.dart' \
  | grep -iE 'gateway|notification' || true)"

if [ -n "$hits" ]; then
  echo "VIOLATION: schedule/cancel called outside syncNotifications():"
  echo "$hits"
  echo "Route all scheduling changes through syncNotifications()."
  exit 1
fi

echo "OK: no ad-hoc gateway scheduling calls in feature code."
