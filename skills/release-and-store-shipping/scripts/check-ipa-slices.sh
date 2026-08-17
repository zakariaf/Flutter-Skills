#!/usr/bin/env bash
set -euo pipefail
# Usage: check-ipa-slices.sh [IPA_PATH]
#   IPA_PATH  the .ipa to inspect (default: the newest under build/ios/ipa/)
#
# Fails if any Mach-O in the IPA carries a simulator slice, which App Store Connect
# rejects as 90087 ("unsupported architectures") or 91169 ("references an unsupported
# platform in the arm64 slice"). This happens whenever the tree was last built for the
# simulator — a screenshot run, for example — and is NOT fixable by thinning the binary:
# the device slice was never built. The fix is `flutter clean` + a release rebuild.
#
# On Apple Silicon the simulator slice is also arm64, so the load command is the real
# check; the architecture check only catches Intel-host builds.
# Requires: macOS command-line tools (lipo, otool, unzip). Exits non-zero on a bad slice.

IPA="${1:-}"
if [ -z "$IPA" ]; then
  IPA="$(ls -t build/ios/ipa/*.ipa 2>/dev/null | head -n1 || true)"
fi

if [ -z "$IPA" ] || [ ! -f "$IPA" ]; then
  echo "check-ipa-slices: no IPA found (pass a path, or build one into build/ios/ipa/)" >&2
  exit 2
fi

for tool in lipo otool unzip; do
  command -v "$tool" >/dev/null 2>&1 || { echo "check-ipa-slices: '$tool' not found (macOS only)" >&2; exit 2; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unzip -q "$IPA" -d "$WORK"

APP="$(find "$WORK/Payload" -maxdepth 1 -name '*.app' -print -quit)"
if [ -z "$APP" ]; then
  echo "check-ipa-slices: no .app inside Payload/ — is '$IPA' an IPA?" >&2
  exit 2
fi

status=0
checked=0

check_binary() {
  bin="$1"
  # Mach-O only; skip resources, plists, assets.
  file -b "$bin" | grep -q 'Mach-O' || return 0
  checked=$((checked + 1))

  archs="$(lipo -archs "$bin" 2>/dev/null || echo '')"
  case "$archs" in
    *x86_64* | *i386*)
      echo "SIMULATOR ARCH  $archs  ${bin#"$APP"/}" >&2
      status=1
      ;;
  esac

  # LC_BUILD_VERSION / LC_VERSION_MIN_* platform: device iOS is "2" (or "ios");
  # a simulator build reports platform 7 (or a name containing "simulator").
  platforms="$(otool -l "$bin" 2>/dev/null | awk '/^ *platform /{print tolower($2)}' | sort -u || true)"
  for p in $platforms; do
    case "$p" in
      2 | ios) : ;;
      *)
        echo "SIMULATOR/OTHER PLATFORM  platform=$p  ${bin#"$APP"/}" >&2
        status=1
        ;;
    esac
  done
}

# The app binary itself, plus every embedded framework and dylib.
APP_NAME="$(basename "$APP" .app)"
[ -f "$APP/$APP_NAME" ] && check_binary "$APP/$APP_NAME"
while IFS= read -r f; do
  check_binary "$f"
done < <(find "$APP/Frameworks" -type f \( -perm -u+x -o -name '*.dylib' \) 2>/dev/null || true)

if [ "$status" -ne 0 ]; then
  echo "::error::check-ipa-slices: simulator slices present — run 'flutter clean' and rebuild the IPA" >&2
  exit 1
fi

echo "check-ipa-slices: OK — $checked Mach-O binaries, device slices only ($(basename "$IPA"))"
