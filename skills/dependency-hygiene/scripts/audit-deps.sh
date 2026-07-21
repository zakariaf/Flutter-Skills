#!/usr/bin/env bash
set -euo pipefail
# Pre-PR dependency audit. Run from a package or workspace root.
#   usage: audit-deps.sh [PROJECT_DIR]   (default: current directory)
#
# Checks, in order:
#   1) pubspec.lock exists and is tracked by git (an app must commit its lock).
#   2) no exact version pins in pubspec.yaml dependencies (caret ranges only).
#   3) the version-pinned lint `include:` file exists in the resolved package
#      (a missing include emits include_file_not_found — fatal to default
#      analyze; where warnings are non-fatal it silently drops your ruleset's
#      added/promoted rules, though the analyzer's built-in lints keep running).
#   4) the full transitive tree contains no policy-banned package
#      (delegates to audit_deps.py next to this script).
# Exits non-zero on any failure so CI can gate on it.

DIR="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

fail=0
note() { printf '%s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fail=1; }

# 1) committed lock -----------------------------------------------------------
if [[ ! -f pubspec.lock ]]; then
  bad "pubspec.lock is missing — run 'flutter pub get' and commit it."
elif command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git check-ignore -q pubspec.lock 2>/dev/null; then
    bad "pubspec.lock is gitignored — an application must commit its lock."
  else
    note "ok    pubspec.lock present and tracked."
  fi
fi

# 2) no exact pins in pubspec.yaml -------------------------------------------
# Flags bare OR quoted version pins like `drift: 2.31.0` / `drift: '2.31.0'`.
# Allows `^`, ranges, `path:`/`git:` blocks, and the `environment:` keys
# (`sdk:`/`flutter:`, which are pinned there on purpose, not dependency pins).
if [[ -f pubspec.yaml ]]; then
  pins="$(grep -nE "^[[:space:]]{2}[a-z0-9_]+:[[:space:]]+['\"]?[0-9]+\.[0-9]+" pubspec.yaml \
            | grep -vE ":[[:space:]]+['\"]?\^" \
            | grep -vE '^[0-9]+:[[:space:]]{2}(flutter|sdk):' || true)"
  if [[ -n "$pins" ]]; then
    bad "exact version pin(s) in pubspec.yaml — use caret ranges (^x.y.z):"
    printf '        %s\n' "$pins"
  else
    note "ok    no exact version pins in pubspec.yaml."
  fi
fi

# 3) versioned lint include actually exists ----------------------------------
if [[ -f analysis_options.yaml ]]; then
  inc="$(grep -oE 'package:[a-z_]+/analysis_options\.[0-9.]+\.yaml' analysis_options.yaml || true)"
  if [[ -n "$inc" ]]; then
    pkg="${inc#package:}"; pkg="${pkg%%/*}"
    file="${inc##*/}"
    cache="${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.dev"
    # Locate the resolved package dir first. If it is absent, the cache is
    # likely relocated (PUB_CACHE unset but moved under FLUTTER_ROOT etc.) or
    # not yet resolved — degrade to a skip rather than a false 'lints off' FAIL.
    pkgdir=""
    for d in "$cache/$pkg"-*/; do
      [[ -d "$d" ]] && pkgdir="$d" && break
    done
    if [[ -z "$pkgdir" ]]; then
      note "skip  '$pkg' not found under $cache — set PUB_CACHE if the cache is relocated, then re-run."
    elif [[ -e "${pkgdir}lib/$file" ]]; then
      note "ok    lint include resolves: ${pkgdir}lib/$file"
    else
      bad "lint include '$file' not found in resolved '$pkg' — your ruleset's added/promoted rules stop applying (analyzer built-ins still run); default analyze treats include_file_not_found as fatal."
      note "      list available:  ls ${pkgdir}lib/"
    fi
  fi
fi

# 4) transitive ban audit -----------------------------------------------------
if command -v dart >/dev/null 2>&1; then
  tmp="$(mktemp)"
  if dart pub deps --json >"$tmp" 2>/dev/null; then
    if ! python3 "$SCRIPT_DIR/audit_deps.py" "$tmp"; then
      fail=1
    fi
  else
    note "skip  'dart pub deps --json' failed (run 'flutter pub get' first)."
  fi
  rm -f "$tmp"
else
  note "skip  dart not on PATH — transitive ban audit not run."
fi

exit "$fail"
