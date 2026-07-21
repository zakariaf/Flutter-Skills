#!/usr/bin/env bash
# Usage: regen.sh [TARGET_DIR]   (TARGET_DIR default: lib/, used only for the
# post-run report). Regenerates all build_runner codegen with
# --delete-conflicting-outputs, then gen-l10n, then analyzes. Mirrors the fixed
# CI order (gen -> analyze). Run from anywhere inside the repo.
set -euo pipefail

TARGET_DIR="${1:-lib/}"

# Resolve the repo root: prefer a pub-workspace root, else the nearest pubspec.
find_root() {
  local d="$PWD"
  while [ "$d" != "/" ]; do
    if [ -f "$d/pubspec.yaml" ] && grep -q '^workspace:' "$d/pubspec.yaml"; then
      echo "$d"; return 0
    fi
    d="$(dirname "$d")"
  done
  d="$PWD"
  while [ "$d" != "/" ]; do
    if [ -f "$d/pubspec.yaml" ]; then echo "$d"; return 0; fi
    d="$(dirname "$d")"
  done
  echo "ERROR: no pubspec.yaml found above $PWD" >&2
  return 1
}

ROOT="$(find_root)"
cd "$ROOT"
echo "==> repo root: $ROOT  (report target: $TARGET_DIR)"

# Prefer FVM so the SDK matches the pin; fall back to bare dart/flutter.
if command -v fvm >/dev/null 2>&1 && [ -f "$ROOT/.fvmrc" ]; then
  DART="fvm dart"; FLUTTER="fvm flutter"
else
  DART="dart"; FLUTTER="flutter"
fi
echo "==> using: $DART / $FLUTTER"

echo "==> [1/3] build_runner build --delete-conflicting-outputs"
$DART run build_runner build --delete-conflicting-outputs

echo "==> [2/3] gen-l10n"
$FLUTTER gen-l10n || echo "   (skipped: no l10n.yaml; the l10n package may run it itself)"

echo "==> [3/3] flutter analyze --fatal-infos"
$FLUTTER analyze --fatal-infos

echo "==> OK: codegen regenerated and analysis clean"
