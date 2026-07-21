#!/usr/bin/env bash
# Usage: check-scheduler-purity.sh [TARGET_DIR]   (default: lib/)
# Flag impurity in the pure scheduler/recurrence math: wall-clock reads, plugin
# imports, or IO. All time must come from an injected Clock (package:clock).
set -euo pipefail

ROOT="${1:-lib}"

echo "== Checking purity of scheduler / recurrence math under $ROOT =="

# The pure files, by convention. Adjust the name globs to your layout if needed.
mapfile -t FILES < <(
  find "$ROOT" -type f -name '*.dart' \
    \( -name 'reminder_scheduler.dart' \
       -o -name 'recurrence_rule.dart' \
       -o -path '*/core/notifications/*' \
       -o -path '*/scheduler/*' \
       -o -path '*/recurrence/*' \) 2>/dev/null | sort -u
)

if [ "${#FILES[@]}" -eq 0 ]; then
  echo "OK: no pure-scheduler files present yet (nothing to check)."
  exit 0
fi

status=0
check() {
  local pat="$1" reason="$2"
  for f in "${FILES[@]}"; do
    if grep -nE "$pat" "$f" >/dev/null 2>&1; then
      echo "VIOLATION [$reason] in $f:"
      grep -nE "$pat" "$f"
      status=1
    fi
  done
}

check 'DateTime\.now\(\)' 'use injected Clock.now(), never DateTime.now()'
check 'package:flutter_local_notifications' 'no plugin imports in pure math'
check 'dart:io|package:drift|package:sqflite|package:sqlite3|rootBundle|File\(' 'no IO in pure math'

if [ "$status" -eq 0 ]; then
  echo "OK: scheduler/recurrence are pure (no DateTime.now, no plugin, no IO)."
fi
exit "$status"
