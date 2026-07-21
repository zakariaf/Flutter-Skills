#!/usr/bin/env bash
set -euo pipefail
# Usage: check-service-boundaries.sh [TARGET_DIR]   (default: lib/)
# Grep-based bans that enforce the service-boundary seam. Run before a PR.
# Exits non-zero on any violation. No app-specific paths are hardcoded.
#
# Enforces:
#   1. No DateTime.now() / DateTime.timestamp() anywhere in lib/ (use the injected
#      Clock from package:clock via clockProvider). The *clock* filename exception is a
#      harmless escape hatch; the app should have no such impl file.
#   2. No math.Random() / Random() outside a *_clock/*random* impl (entropy is injected).
#   3. Every MethodChannel(...) construction lives under a native/ directory.

TARGET="${1:-lib/}"

if [ ! -d "$TARGET" ]; then
  echo "check-service-boundaries: target dir '$TARGET' not found" >&2
  exit 2
fi

fail=0

# Collect Dart files, excluding generated output and the clock impl(s) themselves.
# Portable read loop (no `mapfile`/`readarray`, which need bash 4+; macOS ships 3.2).
dart_files=()
while IFS= read -r f; do
  dart_files+=("$f")
done < <(
  find "$TARGET" -type f -name '*.dart' \
    ! -name '*.g.dart' ! -name '*.freezed.dart' ! -name '*.gr.dart'
)

# Nothing to check (empty array is unsafe to expand under `set -u` on bash 3.2).
if [ "${#dart_files[@]}" -eq 0 ]; then
  echo "check-service-boundaries: OK ($TARGET — no Dart files)"
  exit 0
fi

# --- 1. wall clock ----------------------------------------------------------
# DateTime.now() is allowed ONLY in a file whose name contains "clock".
for f in "${dart_files[@]}"; do
  case "$(basename "$f")" in
    *clock*) continue ;;
  esac
  if grep -nE 'DateTime\.(now|timestamp)\(' "$f"; then
    echo "  ^ $f: use the injected Clock (package:clock via clockProvider), not DateTime.now()" >&2
    fail=1
  fi
done

# --- 2. ambient randomness --------------------------------------------------
# Random() is allowed ONLY in a file whose name hints it is the entropy source.
for f in "${dart_files[@]}"; do
  case "$(basename "$f")" in
    *clock*|*random*|*entropy*) continue ;;
  esac
  if grep -nE '(math\.)?Random\(' "$f"; then
    echo "  ^ $f: inject randomness through a seam, do not read it ambiently" >&2
    fail=1
  fi
done

# --- 3. MethodChannel quarantine -------------------------------------------
# Every MethodChannel/EventChannel/BasicMessageChannel construction must be under native/.
for f in "${dart_files[@]}"; do
  case "$f" in
    */native/*) continue ;;
  esac
  if grep -nE '(Method|Event|BasicMessage)Channel\(' "$f"; then
    echo "  ^ $f: platform channels live under a native/ directory only" >&2
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo "check-service-boundaries: violations found (see above)" >&2
  exit 1
fi
echo "check-service-boundaries: OK ($TARGET)"
