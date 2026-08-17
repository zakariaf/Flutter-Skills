#!/usr/bin/env bash
set -euo pipefail
# Usage: check-release-ad-ids.sh [TARGET_DIR] [INFO_PLIST]
#   TARGET_DIR   Dart sources to scan (default: lib/)
#   INFO_PLIST   iOS plist holding the ad app id (default: ios/Runner/Info.plist)
#
# Release gate for ad identifiers. Two failures it is worth never shipping:
#   1. A missing or empty GADApplicationIdentifier — the SDK reads the app id from the
#      platform manifest at init, and an absent value is a guaranteed launch crash.
#   2. An empty ad unit id constant — the SDK silently falls back to nothing, so the
#      earn control never appears and no one finds out until revenue is flat.
# It also WARNS on the network's well-known sample publisher id, which is correct during
# development (debug builds should use test units) and never correct in a release: sample
# ids serve "test ad" creatives that earn nothing and read as broken to a store reviewer.
#
# Tune SAMPLE_PUBLISHER / the unit-id name pattern to your network. Exits non-zero on a failure.

TARGET_DIR="${1:-lib/}"
INFO_PLIST="${2:-ios/Runner/Info.plist}"

# AdMob's published sample publisher. Replace for another network.
SAMPLE_PUBLISHER='ca-app-pub-3940256099942544'

status=0

# --- 1. the app id in the platform manifest -----------------------------------
if [ -f "$INFO_PLIST" ]; then
  app_id="$(/usr/libexec/PlistBuddy -c 'Print :GADApplicationIdentifier' "$INFO_PLIST" 2>/dev/null || true)"
  if [ -z "$app_id" ]; then
    echo "FAIL: $INFO_PLIST has no non-empty GADApplicationIdentifier — the app will crash at launch." >&2
    status=1
  elif [[ "$app_id" == *"$SAMPLE_PUBLISHER"* ]]; then
    echo "WARN: $INFO_PLIST carries the SAMPLE app id ($app_id) — fine in development, never in a release." >&2
  fi
else
  echo "note: $INFO_PLIST not found — skipping the app-id check." >&2
fi

# --- 2. empty unit id constants ------------------------------------------------
if [ -d "$TARGET_DIR" ]; then
  if empty_ids="$(grep -rnE "(adUnit|AdUnit|adId|AdId)[A-Za-z]*\s*=\s*(''|\"\")" "$TARGET_DIR" \
       --include='*.dart' 2>/dev/null)"; then
    echo "FAIL: empty ad unit id constant(s):" >&2
    printf '%s\n' "$empty_ids" >&2
    status=1
  fi

  # --- 3. sample ids in Dart sources (legitimate only as a debug fallback) -----
  if sample_hits="$(grep -rn "$SAMPLE_PUBLISHER" "$TARGET_DIR" --include='*.dart' 2>/dev/null)"; then
    echo "WARN: sample ad ids referenced in $TARGET_DIR — confirm they are debug-only:" >&2
    printf '%s\n' "$sample_hits" >&2
    echo "      A release build must assert its ids are real; see references/ad-unit-setup.md." >&2
  fi
else
  echo "note: $TARGET_DIR not found — skipping the Dart checks." >&2
fi

if [ "$status" -ne 0 ]; then
  echo "::error::check-release-ad-ids: ad identifiers are not release-ready" >&2
  exit 1
fi

echo "check-release-ad-ids: OK"
