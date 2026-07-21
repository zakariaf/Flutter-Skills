#!/usr/bin/env bash
# check-drift-confinement.sh — prove package:drift / package:sqlite3 are imported
# ONLY under the data layer (lib/data/ by default). A Drift symbol anywhere else
# means the row shape has leaked past the repository boundary and everything above
# it can no longer be tested without a database.
#
# Usage: bash scripts/check-drift-confinement.sh [LIB_DIR]   (default: lib)
set -euo pipefail

LIB="${1:-lib}"
DATA_DIR="$LIB/data"
fail=0

if [ ! -d "$LIB" ]; then
  echo "SKIP  $LIB not found — nothing to check."
  exit 0
fi

# Any file importing drift/sqlite3 that is NOT under lib/data/ is a violation.
offenders=$(grep -rlE "import 'package:(drift|sqlite3)" --include='*.dart' "$LIB" 2>/dev/null \
  | grep -v "^$DATA_DIR/" || true)

if [ -n "$offenders" ]; then
  echo "FAIL  package:drift / package:sqlite3 imported outside $DATA_DIR/:"
  printf '        %s\n' $offenders
  echo "        Map rows to value objects inside a DAO/repository; do not leak Drift types."
  fail=1
else
  echo "PASS  Drift/sqlite3 imports are confined to $DATA_DIR/."
fi

# The sqflite backend forfeits in-process WAL concurrency + the FFI encryption path.
if grep -rqE "import 'package:sqflite" --include='*.dart' "$LIB" 2>/dev/null; then
  echo "FAIL  package:sqflite is used — use NativeDatabase (FFI) instead."
  fail=1
else
  echo "PASS  No sqflite backend."
fi

exit "$fail"
