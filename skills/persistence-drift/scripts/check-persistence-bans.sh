#!/usr/bin/env bash
# check-persistence-bans.sh — grep-based bans for the data layer. Catches the
# silent-corruption footguns: File.copy of a live DB, OFFSET pagination, the
# sqflite backend, and eraseDatabaseOnSchemaChange reachable in code. Also warns
# when the connection setup is missing a per-connection pragma.
#
# Usage: bash scripts/check-persistence-bans.sh [LIB_DIR]   (default: lib)
set -euo pipefail

LIB="${1:-lib}"
fail=0
bad()  { echo "FAIL  $1"; fail=1; }
warn() { echo "WARN  $1"; }
pass() { echo "PASS  $1"; }

if [ ! -d "$LIB" ]; then
  echo "SKIP  $LIB not found — nothing to check."
  exit 0
fi

DATA="$LIB/data"

# --- 1. Never File.copy a live WAL DB for a backup -----------------------------
copy_hits=$(grep -rnE "\.copy\((.*)?\)" --include='*.dart' "$LIB" 2>/dev/null \
  | grep -iE "sqlite|\.db|database" || true)
if [ -n "$copy_hits" ]; then
  bad "Possible File.copy of a live DB — use wal_checkpoint(TRUNCATE) + VACUUM INTO:"
  printf '        %s\n' "$copy_hits"
else
  pass "No File.copy of a DB file."
fi

# --- 2. OFFSET pagination degrades on large tables — use keyset ----------------
if grep -rniE "\.limit\([^)]*offset|OFFSET " --include='*.dart' "$DATA" 2>/dev/null | grep -q .; then
  bad "OFFSET pagination found — use keyset (WHERE ts < :cursor ... LIMIT n)."
  grep -rniE "\.limit\([^)]*offset|OFFSET " --include='*.dart' "$DATA" 2>/dev/null | sed 's/^/        /'
else
  pass "No OFFSET pagination."
fi

# --- 3. eraseDatabaseOnSchemaChange must never reach release -------------------
if grep -rn "eraseDatabaseOnSchemaChange" --include='*.dart' "$DATA" 2>/dev/null | grep -q .; then
  warn "eraseDatabaseOnSchemaChange present — must be DEBUG-only and never shipped:"
  grep -rn "eraseDatabaseOnSchemaChange" --include='*.dart' "$DATA" 2>/dev/null | sed 's/^/        /'
fi

# --- 4. Connection setup should assert the per-connection pragmas --------------
if [ -d "$DATA" ]; then
  for pragma in "foreign_keys" "journal_mode = WAL" "synchronous"; do
    if grep -rq "$pragma" --include='*.dart' "$DATA" 2>/dev/null; then
      pass "PRAGMA $pragma configured in the data layer."
    else
      warn "No 'PRAGMA $pragma' found in $DATA — pragmas are per-connection, set them in beforeOpen/setup."
    fi
  done
fi

exit "$fail"
