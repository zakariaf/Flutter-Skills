#!/usr/bin/env bash
# Format check + static analysis for the canvas/gesture layer.
# Usage: scripts/analyze.sh [TARGET_DIR]   (default: lib/)
# Runs `dart format --set-exit-if-changed` and `flutter analyze --fatal-infos` so const/perf lints
# (very_good_analysis) that this skill relies on fail the build.
set -euo pipefail

TARGET="${1:-lib}"

if ! command -v flutter >/dev/null 2>&1; then
  echo "note — flutter not on PATH; skipping analyze"
  exit 0
fi

echo "== dart format (check only) =="
dart format --output=none --set-exit-if-changed "$TARGET"

echo "== flutter analyze --fatal-infos =="
flutter analyze --fatal-infos "$TARGET"

echo "PASS — format clean and analyze clean"
