#!/usr/bin/env bash
# Usage: check-manifest-permissions.sh [MANIFEST_PATH]
#        (default: android/app/src/main/AndroidManifest.xml)
# Assert the AndroidManifest declares the required permissions and NEVER USE_EXACT_ALARM.
set -euo pipefail

MANIFEST="${1:-android/app/src/main/AndroidManifest.xml}"

echo "== Checking AndroidManifest permissions in $MANIFEST =="

if [ ! -f "$MANIFEST" ]; then
  echo "SKIP: $MANIFEST not found (pass the path as arg 1)."
  exit 0
fi

status=0

require() {
  if grep -q "$1" "$MANIFEST"; then
    echo "OK  : $1 present"
  else
    echo "MISS: $1 NOT declared"
    status=1
  fi
}

forbid() {
  if grep -q "$1" "$MANIFEST"; then
    echo "VIOLATION: $1 must NOT be declared (Play policy risk)"
    status=1
  else
    echo "OK  : $1 absent"
  fi
}

require "android.permission.POST_NOTIFICATIONS"
require "android.permission.RECEIVE_BOOT_COMPLETED"
require "android.permission.SCHEDULE_EXACT_ALARM"
require "ScheduledNotificationBootReceiver"
forbid  "android.permission.USE_EXACT_ALARM"

exit "$status"
