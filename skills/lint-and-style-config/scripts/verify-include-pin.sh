#!/usr/bin/env bash
set -euo pipefail
# verify-include-pin.sh — catch the silent include_file_not_found trap, where a
# missing pinned include disables every rule while the build stays green.
# Usage: scripts/verify-include-pin.sh [ANALYSIS_OPTIONS]
#        (defaults to ./analysis_options.yaml)

OPTS_FILE="${1:-analysis_options.yaml}"

if [ ! -f "$OPTS_FILE" ]; then
  echo "FAIL: $OPTS_FILE not found." >&2
  exit 1
fi

include_line="$(grep -E '^[[:space:]]*include:[[:space:]]*package:' "$OPTS_FILE" || true)"
if [ -z "$include_line" ]; then
  echo "FAIL: no 'include: package:...' line in $OPTS_FILE." >&2
  exit 1
fi

# Warn (do not fail) if the include is the bare, unversioned file — a pub
# upgrade could then silently change what counts as an error.
if echo "$include_line" | grep -qE 'analysis_options\.yaml[[:space:]]*$'; then
  echo "WARN: include points at the bare analysis_options.yaml; pin the" >&2
  echo "      version-numbered file (e.g. analysis_options.10.3.0.yaml)." >&2
fi

# Resolve the referenced file: package:<pkg>/<path-under-lib>.
ref="$(echo "$include_line" | sed -E 's/.*package:([^[:space:]]+).*/\1/')"
pkg="${ref%%/*}"
rel="${ref#*/}"

found=0
for base in "$HOME/.pub-cache/hosted/pub.dev/${pkg}-"* ; do
  [ -e "$base/lib/$rel" ] || continue
  echo "OK: resolved $ref -> $base/lib/$rel"
  found=1
  break
done

if [ "$found" -ne 1 ]; then
  echo "FAIL: '$ref' does not resolve in the pub cache. The analyzer would emit" >&2
  echo "      a single include_file_not_found warning and run with ZERO rules." >&2
  echo "      Run 'dart pub get' and confirm the pinned VGA version exists." >&2
  exit 1
fi

echo "verify-include-pin: OK (also confirm a known violation still errors)"
