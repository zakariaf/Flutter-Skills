#!/usr/bin/env bash
set -euo pipefail
# Usage: check-release-hygiene.sh [PROJECT_DIR]
#   PROJECT_DIR   Flutter app root containing pubspec.yaml (default: '.')
#
# Static pre-release gate for the mistakes that are unrecoverable once shipped:
# signing material tracked by git, a malformed or missing build number, a release
# build type still wired to the debug signing config, and debug-only affordances
# reachable in lib/. Fast, offline, and safe to run in CI on every PR — none of it
# needs a build. Exits non-zero listing every failure (it does not stop at the first).

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR"

if [ ! -f pubspec.yaml ]; then
  echo "check-release-hygiene: no pubspec.yaml in '$PROJECT_DIR'" >&2
  exit 2
fi

fail=0
report() { echo "check-release-hygiene: FAIL — $1" >&2; fail=1; }

# 1. Signing material must never be tracked. History is forever; a scrub is not a fix.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  tracked_secrets="$(git ls-files \
    | grep -Ei '(^|/)key\.properties$|\.(jks|keystore|p12|p8|mobileprovision)$|(^|/)[^/]*service[-_]account[^/]*\.json$' \
    || true)"
  if [ -n "$tracked_secrets" ]; then
    report "signing/store credentials are tracked by git:"
    printf '  %s\n' $tracked_secrets >&2
  fi
else
  echo "check-release-hygiene: not a git work tree — skipping the tracked-secrets check" >&2
fi

# 2. version: x.y.z+N — the single source of versionName/versionCode.
version_line="$(grep -E '^version:' pubspec.yaml | head -n1 || true)"
if ! printf '%s' "$version_line" | grep -Eq '^version:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+[[:space:]]*$'; then
  report "pubspec version must be 'x.y.z+N' (build number required), found: ${version_line:-<none>}"
fi

# 3. The release build type must not sign with the debug config (the Flutter template
#    default). A debug-signed artifact is rejected by the store — or worse, installed.
for gradle in android/app/build.gradle android/app/build.gradle.kts; do
  [ -f "$gradle" ] || continue
  if awk '/(buildTypes|release)/,0' "$gradle" | grep -Eq 'signingConfigs?[.[:space:]]*(getByName\()?["'"'"']?debug'; then
    report "$gradle signs a release build with the debug signing config"
  fi
done

# 4. Debug-only affordances must be unreachable in shipped code.
if [ -d lib ]; then
  banned='eraseDatabaseOnSchemaChange|DevMenu|devMenu|seedFixtures|debugPrintRebuildDirtyWidgets|debugDefaultTargetPlatformOverride'
  hits="$(grep -rnE "$banned" lib || true)"
  if [ -n "$hits" ]; then
    report "debug-only affordances referenced in lib/ (must be compiled out of the store flavor):"
    printf '  %s\n' "$hits" >&2
  fi
fi

# 5. .gitignore should already exclude the credentials in check 1 (advisory, not fatal).
if [ -f .gitignore ] && ! grep -Eq 'key\.properties|\*\.jks|\*\.p8' .gitignore; then
  echo "check-release-hygiene: note — .gitignore lists none of key.properties / *.jks / *.p8" >&2
fi

if [ "$fail" -ne 0 ]; then
  echo "::error::release hygiene gate failed — see the FAIL lines above" >&2
  exit 1
fi

version="$(printf '%s' "$version_line" | sed -E 's/^version:[[:space:]]*//; s/[[:space:]]*$//')"
echo "check-release-hygiene: OK — no tracked credentials, version '$version', no debug signing or debug affordances"
