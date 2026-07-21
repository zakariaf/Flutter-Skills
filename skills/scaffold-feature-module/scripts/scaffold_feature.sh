#!/usr/bin/env bash
# scaffold_feature.sh — generate one feature folder with the fixed anatomy.
#
# Usage:   scripts/scaffold_feature.sh <feature-name-snake> [lib-dir]
# Example: scripts/scaffold_feature.sh task_list          # -> lib/features/task_list/presentation/
#          scripts/scaffold_feature.sh settings apps/my_app/lib
#
# Creates <lib-dir>/features/<feature>/presentation/{<feature>_screen.dart, <feature>_notifier.dart,
# <feature>_providers.dart, widgets/} with compiling placeholders (hand-written Riverpod providers —
# the default), then prints the two manual steps it cannot do (register the go_router route, add the
# ARB strings). The single-package tree (lib/features/, no lib/src/) is owned by
# project-structure-and-packages. No app paths hardcoded.
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $(basename "$0") <feature-name-snake> [lib-dir]" >&2
  exit 2
fi

FEATURE="$1"
LIB_DIR="${2:-lib}"

if ! [[ "$FEATURE" =~ ^[a-z][a-z0-9_]*$ ]]; then
  echo "FAIL: feature-name must be lower_snake_case (e.g. task_list), got '$FEATURE'" >&2
  exit 2
fi

# Derive UpperCamel type prefix and lowerCamel identifier prefix from the snake name.
PASCAL=""
IFS='_' read -ra WORDS <<< "$FEATURE"
for w in "${WORDS[@]}"; do
  PASCAL+="$(tr '[:lower:]' '[:upper:]' <<< "${w:0:1}")${w:1}"
done
CAMEL="$(tr '[:upper:]' '[:lower:]' <<< "${PASCAL:0:1}")${PASCAL:1}"

DEST="$LIB_DIR/features/$FEATURE/presentation"
if [[ -e "$DEST" ]]; then
  echo "FAIL: feature folder already exists: $DEST" >&2
  exit 1
fi

echo "== scaffold-feature-module =="
echo "feature: $FEATURE   type prefix: $PASCAL   dest: $DEST"
mkdir -p "$DEST/widgets"

cat > "$DEST/${FEATURE}_providers.dart" <<EOF
// $DEST/${FEATURE}_providers.dart — providers SCOPED to this feature (never global).
// The reactive read wraps a repository .watch(); keep it family-keyed + .autoDispose.
// Hand-written providers are the default (see state-management-riverpod).
import 'package:flutter_riverpod/flutter_riverpod.dart';

// TODO: import your repository provider and domain model, then wrap the scoped .watch():
// final ${CAMEL}ListProvider =
//     StreamProvider.autoDispose.family<List<${PASCAL}Item>, String>((ref, parentId) =>
//         ref.watch(${CAMEL}RepositoryProvider).watch${PASCAL}Items(parentId));
EOF

cat > "$DEST/${FEATURE}_notifier.dart" <<EOF
// $DEST/${FEATURE}_notifier.dart — the 1:1 ViewModel: command state + writes.
// Reads repositories; NEVER touches the store/DAO directly. Every mutation is one repository
// method (single write path). .autoDispose (per-screen) unless the state must outlive the route.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

final ${CAMEL}NotifierProvider =
    AsyncNotifierProvider.autoDispose<${PASCAL}Notifier, void>(${PASCAL}Notifier.new);

class ${PASCAL}Notifier extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {
    // No synchronous heavy work here.
  }

  // TODO: a command the View binds. Route the write through ONE repository method; map the
  // typed Result to AsyncValue. No optimistic republish, no setState, no store access here.
  // Future<void> add(/* draft */) async {
  //   state = const AsyncLoading();
  //   state = switch (await ref.read(${CAMEL}RepositoryProvider).add(/* draft */)) {
  //     Ok() => const AsyncData(null),
  //     Err(:final failure) => AsyncError(failure, StackTrace.current),
  //   };
  // }
}
EOF

cat > "$DEST/${FEATURE}_screen.dart" <<EOF
// $DEST/${FEATURE}_screen.dart — the navigable entry View: a DUMB ConsumerWidget.
// Reads one controller/stream and renders. Only show/hide ifs, layout, animation, navigation.
// Directional geometry + gen-l10n strings only. Navigate BY ID from here, never from the ViewModel.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '${FEATURE}_notifier.dart';

class ${PASCAL}Screen extends ConsumerWidget {
  const ${PASCAL}Screen({required this.parentId, super.key});

  final String parentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // final l10n = AppLocalizations.of(context); // no hardcoded UI literals
    // ref.listen(${CAMEL}NotifierProvider, (prev, next) { /* one-shot effects */ });
    // final async = ref.watch(${CAMEL}ListProvider(parentId));
    return Scaffold(
      // appBar: AppBar(title: Text(l10n.${CAMEL}Title)),
      body: const Center(child: Text('TODO: ${FEATURE} screen')),
    );
  }
}
EOF

touch "$DEST/widgets/.gitkeep"
echo "  wrote $DEST/${FEATURE}_providers.dart"
echo "  wrote $DEST/${FEATURE}_notifier.dart"
echo "  wrote $DEST/${FEATURE}_screen.dart"
echo "  created $DEST/widgets/"

echo
echo "== NEXT — two manual steps the generator cannot do =="
echo "1) REGISTER THE ROUTE in the single go_router:"
echo "     @TypedGoRoute<${PASCAL}Route>(path: '/.../:parentId/${FEATURE}')  — identity in PATH PARAMS."
echo "     Full-screen add/edit -> parentNavigatorKey: rootNavigatorKey. Then run build_runner."
echo "2) ADD STRINGS to the template ARB FIRST (with @metadata), then mirror to every locale ARB"
echo "     with identical placeholders + ICU structure. Run the ARB parity check."
echo
echo "Then: dart run build_runner build --delete-conflicting-outputs && dart analyze"
echo "      scripts/verify_feature.sh $LIB_DIR"
