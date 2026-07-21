#!/usr/bin/env bash
set -euo pipefail
# Usage: check-flavor-graph.sh 'BANNED_REGEX' [PACKAGE_DIR]
#   BANNED_REGEX  extended-regex of package names this flavor must NOT link
#                 (e.g. 'vendor_analytics|signed_cdn_config|some_heavy_sdk')
#   PACKAGE_DIR   pub package to resolve (default: current directory, i.e. '.')
#
# Proves STATICALLY that a flavor's resolved dependency graph links none of the
# banned packages. A passing user journey proves nothing — the running code merely
# never CALLED the SDK; only the graph proves the release does not LINK it.
# Run once per flavor from CI with that flavor's config. Exits non-zero on a match.

if [ "$#" -lt 1 ]; then
  echo "usage: check-flavor-graph.sh 'BANNED_REGEX' [PACKAGE_DIR]" >&2
  exit 2
fi

BANNED="$1"
PKG_DIR="${2:-.}"

if [ ! -f "$PKG_DIR/pubspec.yaml" ]; then
  echo "check-flavor-graph: no pubspec.yaml in '$PKG_DIR'" >&2
  exit 2
fi

# Resolve the (non-dev) dependency graph and scan package names.
deps="$(cd "$PKG_DIR" && flutter pub deps --style=compact --no-dev 2>/dev/null)"

if printf '%s\n' "$deps" | grep -Eiq "$BANNED"; then
  echo "check-flavor-graph: BANNED dependency reachable in the graph:" >&2
  printf '%s\n' "$deps" | grep -Ei "$BANNED" >&2
  echo "::error::this flavor must link none of: $BANNED" >&2
  exit 1
fi

echo "check-flavor-graph: OK — none of [$BANNED] reachable in $PKG_DIR"
