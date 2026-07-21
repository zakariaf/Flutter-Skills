#!/usr/bin/env bash
# Fails if banned state/DI patterns appear in the source tree.
# Bans: Riverpod legacy providers, competing DI/state libraries, and the
# raw-clock call that breaks deterministic time in state logic.
# This gate assumes the Riverpod path — it bans package:provider outright. A
# project that deliberately adopts the SKILL's Provider/ChangeNotifier appendix
# stack instead should NOT run this gate.
# Usage: scripts/ban-legacy-providers.sh [target_dir]   (default: lib/)
set -euo pipefail

TARGET="${1:-lib/}"

if [ ! -d "$TARGET" ]; then
  echo "ban-legacy-providers: target dir '$TARGET' not found" >&2
  exit 2
fi

fail=0

# Grep helper: prints matches and flags failure. Skips generated files.
scan() {
  local label="$1" pattern="$2"
  local hits
  hits="$(grep -rnE "$pattern" "$TARGET" \
    --include='*.dart' \
    | grep -v '\.g\.dart:' \
    | grep -v '\.freezed\.dart:' || true)"
  if [ -n "$hits" ]; then
    echo "BANNED — $label:"
    echo "$hits"
    echo
    fail=1
  fi
}

# Riverpod legacy providers (moved to flutter_riverpod/legacy.dart in 3.x).
scan "flutter_riverpod/legacy.dart import" \
  "import[[:space:]]+'package:flutter_riverpod/legacy\.dart'"
scan "legacy StateProvider/StateNotifierProvider/ChangeNotifierProvider" \
  "\b(StateProvider|StateNotifierProvider|ChangeNotifierProvider)\b"

# Competing DI / state libraries alongside Riverpod.
scan "get_it (use providers-as-DI)" \
  "package:get_it/|\bGetIt\b"
scan "package:provider (this gate assumes the Riverpod path; use Riverpod)" \
  "import[[:space:]]+'package:provider/"
scan "package:injectable" \
  "package:injectable"
scan "Bloc/Cubit (this library standardizes on Riverpod)" \
  "package:flutter_bloc/|package:bloc/"

# Bespoke clock types — the ONE time seam is package:clock's Clock via clockProvider
# (rule #10). A hand-rolled ClockService/SystemClock/FakeClock does not compose with
# Clock.fixed/withClock; ban it. service-boundary-and-native owns the clockProvider seam.
scan "bespoke clock (use package:clock's Clock via clockProvider)" \
  "\b(ClockService|SystemClock|FakeClock)\b"

# Raw wall clock in state logic — inject the Clock (package:clock) instead. With
# package:clock there is no sanctioned DateTime.now() in app source; the sole rare
# platform adapter may carry a trailing `// ignore: clock-adapter` to pass.
scan_clock() {
  local hits
  hits="$(grep -rnE "DateTime\.now\(\)" "$TARGET" \
    --include='*.dart' \
    | grep -v '\.g\.dart:' \
    | grep -v '\.freezed\.dart:' \
    | grep -v '// ignore: clock-adapter' || true)"
  if [ -n "$hits" ]; then
    echo "BANNED — DateTime.now() (inject package:clock's Clock via clockProvider; use Clock.fixed(...) in tests):"
    echo "$hits"
    echo
    fail=1
  fi
}
scan_clock

if [ "$fail" -ne 0 ]; then
  echo "ban-legacy-providers: banned patterns found." >&2
  exit 1
fi

echo "ban-legacy-providers: clean."
