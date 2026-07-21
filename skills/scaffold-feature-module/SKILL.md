---
name: scaffold-feature-module
description: Stands up one navigable feature the same way every time — a fixed lib/features/<feature>/presentation/ folder (dumb View + one 1:1 Notifier/AsyncNotifier ViewModel + widgets/ + scoped <feature>_providers.dart), downward-only dependencies with no cross-feature imports, reactive reads as scoped StreamProviders over a repository .watch(), every mutation through one repository single-write-path method, typed Result/Failure surfaced as AsyncValue, a typed go_router route carrying identity in path params, ARB parity across locales, family+autoDispose keying, and EdgeInsetsDirectional-only geometry. Use when adding a screen, tab, or feature folder; wiring a feature Notifier/ViewModel or a scoped stream provider; registering a route; adding ARB keys for a new screen; splitting an over-grown feature; or adding a persisted record its View reads.
---

# Scaffold a feature module

Stand up one feature the **same way every time**: a folder `lib/features/<feature>/` whose
`presentation/` holds a dumb View, its 1:1 Notifier/AsyncNotifier ViewModel, leaf `widgets/`, and
scoped providers (feature-local models live in an optional `domain/`). A feature is a folder, not a
package. It reads shared repositories from `lib/data/` and shared foundation from `lib/core/`, routes
every write through them, and depends only *downward* — never sideways into another feature.
(The single-package tree is owned by `project-structure-and-packages`.)

Agnostic core (holds under any state library): the View is dumb; one ViewModel per feature owns
private mutable state and exposes intent methods that assign a new immutable value; reads derive from
the repository (the single source of truth), writes go through one repository method (the single write
path, persist-before-publish); the feature depends on abstractions and navigates by route ID. The
Riverpod-first "how" below wires that with Notifiers, scoped StreamProviders, and providers-as-DI.

Read the reference for the task at hand:
- `references/anatomy-and-wiring.md` — the fixed folder shape, the Notifier + scoped stream, watch/read/listen, family+autoDispose vs keepAlive, the single write path, and the ViewModel test.
- `references/routing-and-l10n.md` — typed go_router registration (path params, not `state.extra`) and the ARB parity workflow.
- `references/add-persisted-record.md` — the optional model → table → DAO → repository chain when the feature reads a brand-new record (defers to `persistence-drift`).

Run `scripts/scaffold_feature.sh <feature>` to generate the skeleton, then `scripts/verify_feature.sh` before a PR.

## Non-negotiable rules

1. **A feature is a FOLDER, never a new package.** `lib/features/<feature>/`, `lower_snake_case`, named
   for the screen (`tasks`, `task_detail`, `settings`, `onboarding`). A new folder is a normal
   addition; a new package is a deliberate boundary decision (see `project-structure-and-packages`).
   Do not invent numbered-folder or fixed-package-count conventions. The app package does **not** use
   `lib/src/` — that is a multi-package convention (see `project-structure-and-packages`).
2. **Fixed anatomy, one primary public type per file.** Under `lib/features/<feature>/presentation/`:
   `<feature>_screen.dart` (the dumb View), `<feature>_notifier.dart` (the 1:1 Notifier/AsyncNotifier
   ViewModel — file name = its primary declaration, per `naming-conventions`), `widgets/` (leaf views),
   and `<feature>_providers.dart` (providers scoped to this feature, never global). A feature-local
   model lives in an optional `domain/<feature>.dart`. Predictable shape = a reviewer finds any piece
   in one second.
3. **The View is dumb; the ViewModel is 1:1.** The View reads exactly one controller and renders —
   only show/hide `if`s, layout, animation, and navigation. No repository call, no `try/catch`
   business logic, no unit math or formatting in `build()`. Logic lives in the ViewModel.
4. **A feature NEVER imports another feature.** Share via a foundation layer (core/data), or navigate
   by route **ID**. Dependencies point *down* only — a lint/grep gate fails a cross-feature import.
   Sideways coupling turns two features into one un-deletable knot.
5. **Read the store only through repository providers; wrap `.watch()` in a scoped StreamProvider.**
   Never touch Drift, secure storage, or a platform channel from a widget or ViewModel. Scope the
   stream by its key (an owner/parent id, a time window) so one write never re-emits app-wide.
6. **`ref.watch` in `build`, `ref.read` in callbacks, `ref.listen` for one-shot effects** (SnackBar,
   navigate). Watching in a callback re-subscribes; reading in `build` misses rebuilds. (See
   `state-management-riverpod` for the full split.)
7. **Per-key state is `family` + `autoDispose`; singletons are `keepAlive`.** Any provider scoped to a
   specific entity/session is `family`-keyed on a stable equatable value and `autoDispose`d so it
   dies with its screen. Never an un-keyed "current thing" provider; never `autoDispose` the
   app-scope db/service singletons.
8. **Every mutation is one repository method — the single write path, persist-before-publish.** A
   command on the ViewModel calls a named repository method that commits, *then* the stream re-emits
   and the UI rebuilds. No optimistic republish, no `setState`, no manual cache poke, no "save later".
9. **Derive, don't store.** Counts, totals, filtered lists, streaks are computed from the source of
   truth (a derived/stream provider), never a second stored counter that drifts out of sync.
10. **Repositories map rows → value objects; the ViewModel passes value objects.** A Drift row,
    companion, or `Map` never reaches a ViewModel or widget. Measured quantities are value objects
    (see `value-objects-money-and-units`) — never a bare `double` for money.
11. **Errors are typed values surfaced as `AsyncValue`.** Repositories return a sealed `Result`/
    `Failure`; the ViewModel maps it to `AsyncData`/`AsyncError`; the View `switch`es exhaustively and
    **localizes the Failure at the presentation edge** — never a raw exception string. (See
    `error-handling-typed-results`.)
12. **Register in the ONE go_router with a typed route; identity rides in path params.** Add a
    `TypedGoRoute`/`GoRouteData`; carry deep-linkable identity in path params (`:taskId`), never
    `state.extra` (null on cold start/OS restore). Full-screen add/edit flows set
    `parentNavigatorKey: rootNavigatorKey`. The router itself — shell/branch structure, redirect/auth
    guards, deep links, transitions — is owned by `navigation-and-routing`; this feature only
    registers its route into it.
13. **Navigate from the View or a router redirect — never from the ViewModel.** The controller
    publishes state; the View or a `redirect` decides what is on screen. A controller that pushes a
    route couples logic to navigation and breaks headless tests.
14. **Inject "now"; never call `DateTime.now()` in a feature.** The ViewModel reads a `Clock`
    provider so a whole flow is assertable with a pinned fake clock. (See `async-safety`.)
15. **Directional geometry and localized strings only.** `EdgeInsetsDirectional`/`AlignmentDirectional`
    — never `.left/.right`, `Alignment.centerLeft`, or `TextAlign.left`. Every user-facing string comes
    from gen-l10n across all locale ARBs with key + placeholder parity. (See `i18n-rtl-l10n`.)
16. **Test the ViewModel by faking the repository, not the Notifier.** `ProviderContainer.test()` +
    `overrideWith` a fake repository and `clockProvider.overrideWithValue(Clock.fixed(t))`; no widget
    pump; verify wiring and UI-state mapping only. (See `testing-strategy`.)

## The canonical Notifier + scoped stream

Default to **hand-written providers** (`state-management-riverpod` owns the discipline; `@riverpod`
codegen is an optional alternative, not the default). Colocate the scoped stream and the command
Notifier in `<feature>_providers.dart` / `<feature>_notifier.dart`. Full file:
`examples/tasks_notifier.dart`.

```dart
// features/tasks/presentation/tasks_providers.dart — reactive backbone, scoped so one write is not app-wide.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app/core/result.dart';          // Result, Ok, Err, Failure (shared foundation, lib/core/)
import 'package:app/data/task_repository.dart';  // taskRepositoryProvider (keepAlive; lives in lib/data/)
import '../domain/task.dart';                     // feature-local immutable model (value objects, not rows)

/// Wrap the repository's scoped `.watch()` in a family StreamProvider, keyed by projectId.
/// `.autoDispose` frees the subscription when the screen unmounts. The repository maps rows ->
/// domain models at the boundary; this never sees a Drift row.
final taskListProvider =
    StreamProvider.autoDispose.family<List<Task>, String>((ref, projectId) =>
        ref.watch(taskRepositoryProvider).watchTasks(projectId));
```

```dart
// features/tasks/presentation/tasks_notifier.dart — the 1:1 ViewModel: command state + writes.
final tasksNotifierProvider =
    AsyncNotifierProvider.autoDispose<TasksNotifier, void>(TasksNotifier.new);

class TasksNotifier extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {} // no synchronous heavy work here

  /// A command the View binds. The write goes through ONE repository method (single write path);
  /// the typed Result is mapped to AsyncValue for the View to switch on exhaustively.
  Future<void> add(Task draft) async {
    state = const AsyncLoading();
    final Result<void, Failure> result =
        await ref.read(taskRepositoryProvider).addTask(draft);
    state = switch (result) {
      Ok() => const AsyncData(null),
      Err(:final failure) => AsyncError(failure, StackTrace.current),
    };
    // No manual republish: the committed write makes the Drift stream re-emit and the list rebuilds.
  }
}
```

## The dumb View

The View watches the scoped stream, renders inside `.when`, and calls `ref.read(...notifier)` from
callbacks. It `ref.listen`s the controller for one-shot effects. Full file: `examples/tasks_screen.dart`.

```dart
class TasksScreen extends ConsumerWidget {
  const TasksScreen({required this.projectId, super.key});
  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    ref.listen(tasksNotifierProvider, (prev, next) {             // one-shot effects only
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizeFailure(l10n, error))), // typed Failure -> localized text
        );
      }
    });

    final async = ref.watch(taskListProvider(projectId));        // watch in build
    return Scaffold(
      appBar: AppBar(title: Text(l10n.tasksTitle)),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => FailureView(message: localizeFailure(l10n, e)),
        data: (tasks) => tasks.isEmpty
            ? EmptyState(title: l10n.tasksEmptyTitle)
            : ListView.builder(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 8),
                itemCount: tasks.length,
                itemBuilder: (context, i) => TaskTile(
                  task: tasks[i],
                  onTap: () => TaskDetailRoute(               // navigate by ID, from the View
                    projectId: projectId,
                    taskId: tasks[i].id,
                  ).go(context),
                ),
              ),
      ),
    );
  }
}
```

## The two manual steps the generator can't do

1. **Register the route** in the single go_router (`TypedGoRoute`, path-param identity,
   `parentNavigatorKey: rootNavigatorKey` for full-screen flows), then regenerate typed routes with
   build_runner. See `references/routing-and-l10n.md`.
2. **Add the strings** to the template ARB first, then mirror into every locale ARB with identical
   placeholder names and ICU structure. Run the parity check, then codegen, then analyze.

## Optional: the feature reads a brand-new persisted record

If the screen needs a record that does not exist yet, add the chain **before** wiring the feature:
an immutable value type (pure, no store import) → a Drift table with schema invariants → a DAO that
maps rows to the value type → a repository method that opens one transaction. Then the feature reads
its scoped `.watch()` stream as usual. The full ritual lives in `persistence-drift` and `run-migration`;
`references/add-persisted-record.md` is the short bridge.

## Anti-patterns

- **A new package when you only need a screen.** A screen is a folder; a package is a boundary decision.
- **Two primary types in one file, naming the ViewModel `<feature>_view_model.dart`/`*Controller` on the Riverpod path, or naming the View `<feature>_view.dart` when the convention is `_screen.dart`.** One primary public type per file, file name = its declaration (`naming-conventions`); the Riverpod ViewModel is `<feature>_notifier.dart` → `<Feature>Notifier`.
- **Repository/engine calls or `try/catch` business logic in `build()`.** The View reads one controller and renders; logic lives in the ViewModel.
- **Touching Drift/secure-storage/a platform channel from a widget or ViewModel.** Reads go through a repository provider; the row shape is a data-layer secret.
- **Optimistic republish before commit, `setState`, a manual cache poke, or a debounced "save later".** Every write is one repository method that persists, then the stream re-emits.
- **A stored counter trusted as truth.** Derive counts/totals/streaks from the source of truth on read.
- **An un-keyed "current entity" provider, or `autoDispose` on app-scope singletons.** Per-key state is `family` + `autoDispose`; singletons are `keepAlive`.
- **`DateTime.now()` in a feature.** Read an injected `Clock` provider so flows are assertable.
- **`state.extra` for deep-linkable identity, or `Navigator.push` of a primary flow.** Path params + a typed `GoRoute`; the View/redirect decides navigation, not the controller.
- **Importing another feature's folder.** Depend down, never sideways.
- **Hard-coded left/right geometry or an inline UI literal.** `EdgeInsetsDirectional` + strings from gen-l10n.
- **Mocking the `Notifier` in tests instead of faking the repository.** Fake the seam; test the wiring.

## Definition of done

- [ ] Feature is a folder `lib/features/<feature>/` with the fixed anatomy under `presentation/`: `<feature>_screen.dart` (dumb View), `<feature>_notifier.dart` (1:1 Notifier/AsyncNotifier), `widgets/`, scoped `<feature>_providers.dart`.
- [ ] The View reads exactly one controller and renders; no repository call or business `try/catch` in `build()`; `.when` surfaces a calm error.
- [ ] Dependencies point down only; no import of another feature's folder; no Drift/DAO/secure-storage/platform-channel import in the feature.
- [ ] Reads are scoped StreamProviders over a repository `.watch()`; per-key providers are `family`-keyed on a stable value and `autoDispose`d; singletons are `keepAlive`.
- [ ] Every mutation routes through one named repository method (single write path), committing before republishing; derived state is computed on read, never stored.
- [ ] The ViewModel passes value objects; no Drift row/companion/`Map` reaches a widget; money is not a bare `double`.
- [ ] Errors are a sealed `Result`/`Failure` mapped to `AsyncValue`; the View switches exhaustively and localizes the Failure at the edge.
- [ ] "Now" comes from an injected `Clock`; no `DateTime.now()` in the feature.
- [ ] A typed `GoRoute` is registered in the single router; identity in path params; full-screen flows set `parentNavigatorKey`; no navigation from the ViewModel.
- [ ] Strings come from gen-l10n with template-first + parity; geometry is `Directional`-only.
- [ ] ViewModel tested with `ProviderContainer.test()` + a fake repository and a fixed `Clock` (`clockProvider.overrideWithValue(Clock.fixed(t))`, not a mocked Notifier).
- [ ] `dart format` + `dart analyze --fatal-infos` clean; `scripts/verify_feature.sh` passes.

## Related skills

- `flutter-architecture` — the layer model and downward-only DAG this scaffold obeys.
- `state-management-riverpod` — the Notifier/AsyncNotifier discipline, watch/read/listen, family+autoDispose, manual-providers-first.
- `navigation-and-routing` — owns the single go_router this feature registers its typed route into.
- `forms-and-input` — the Form/validation/focus discipline for the add/edit flow this feature launches.
- `widget-composition` — dumb Views, small const widget classes, structural layout.
- `error-handling-typed-results` — the sealed `Result`/`Failure` spine surfaced as `AsyncValue`.
- `persistence-drift` and `run-migration` — the repository/DAO/table/migration ritual behind a new record.
- `i18n-rtl-l10n` — the ARB parity + Directional-geometry contract.
- `value-objects-money-and-units` — the canonical value objects the ViewModel passes.
- `testing-strategy` — faking the repository (and `clockProvider`) to test the ViewModel headlessly.
- `project-structure-and-packages` — owns the single-package tree; when a foundation genuinely earns a package instead of a folder.

## References

- Flutter — Guide to app architecture: https://docs.flutter.dev/app-architecture
- Riverpod 3.x: https://riverpod.dev
- go_router — typed routes: https://pub.dev/documentation/go_router/latest/topics/Type-safe%20routes-topic.html
- Flutter — Internationalization (gen-l10n): https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization

## Provider / ChangeNotifier appendix

Using the official Flutter-guide stack (`package:provider` + `ChangeNotifier`)? The rules are
identical; only the wiring changes:

- The ViewModel is a `ChangeNotifier`; intent methods mutate private fields and call
  `notifyListeners()` once at the end (still one immutable state snapshot's worth of change per call).
- Provide it with `ChangeNotifierProvider` at the feature route; the View reads it with
  `context.watch<TasksViewModel>()` in `build` and `context.read<TasksViewModel>()` in callbacks —
  the same watch-in-build / read-in-callbacks split as Riverpod.
- Reactive reads: expose a repository `Stream` and fold it with a `StreamProvider` (the `provider`
  package's `StreamProvider`, or `StreamBuilder`) — do **not** cache a mutable copy in the ViewModel;
  derive on emit.
- Per-screen scoping replaces `family`+`autoDispose`: create the `ChangeNotifierProvider` at the
  screen so it disposes with the route; keep app-scope services in a root provider.
- Dispose controllers/subscriptions in `ChangeNotifier.dispose()`.

Everything else — dumb View, single write path, typed `Result`/`Failure`, path-param routing,
injected clock, ARB parity, Directional geometry, faking the repository in tests — is unchanged.
