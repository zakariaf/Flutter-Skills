---
name: state-management-riverpod
description: Enforces feature state as one Notifier/AsyncNotifier/StreamNotifier ViewModel over an immutable state value with value equality, private mutable state mutated only through intent methods, derive-don't-store, a single write path through a repository, and unidirectional data flow; Riverpod 3.x is DI (providers-as-collaborators, ProviderScope overrides per flavor, throwing seams), reads split ref.watch/.select for display vs ref.read(p.notifier) in callbacks vs ref.listen for side effects, async modeled as AsyncValue, per-entity state family-keyed + autoDispose, and stale-closure captures / legacy StateProvider-StateNotifierProvider-ChangeNotifierProvider / get_it / package:provider are banned. Use when adding state to a screen, writing a feature controller/ViewModel, wiring providers or DI, deriving a read model from a stream, or reviewing rebuild/state-leak/disposal/write-path issues.
---

# State management (Riverpod)

State and dependency injection are one mechanism: Riverpod 3.x. Each feature has one `Notifier`/`AsyncNotifier`/`StreamNotifier` ViewModel that exposes an **immutable** state value; dumb `ConsumerWidget`s read it. Widgets hold only ephemeral UI state; every durable mutation routes through one repository (the single write path). This skill covers the state-agnostic core first, then the Riverpod "how", then a Provider/ChangeNotifier appendix for the official Flutter-guide stack.

Read the reference for the task at hand:

- `references/ownership-and-lifecycle.md` — the ownership table (which provider shape), family/autoDispose/onDispose rules, composition-root DI.
- `references/reads-and-side-effects.md` — watch vs read vs listen vs select, the stale-closure hole, `void` action methods, `ref.mounted`/`BuildContext` guards.
- `references/riverpod3-api-and-testing.md` — Riverpod 3.x API shifts (legacy moves, `overrideWithValue`, retry, `ProviderContainer.test`), what 2023 tutorials get wrong, and testing seams.

Run `scripts/ban-legacy-providers.sh` before a PR.

## Non-negotiable rules

These hold regardless of the state library.

1. **One ViewModel per feature over one immutable state value.** The state is a value type with value equality (`freezed`/sealed + `copyWith`), never a mutable field bag. Cross-feature/shared state lives in a repository, not a ViewModel — two ViewModels owning the same fact is two facts that will disagree.
2. **State is private; mutate only through intent methods.** No widget reaches into the state to poke a field. A view calls `notifier.rename(id, name)`; it never sets state. This is the one door through which state changes, so every change is reviewable in one place.
3. **Every transition assigns a *new* value.** Value-equality listeners diff by value — a mutated-in-place instance reassigned to the same reference is missed and the UI silently stales. Always `copyWith` into a new instance.
4. **Derive, don't store.** A value computable from existing state (a total, a filtered count, a streak) is a getter or a stream projection, never a second stored field — a stored derivation is a second source of truth that drifts out of sync.
5. **Single write path.** Every durable mutation is one repository method that persists transactionally and returns **only after commit**; the UI updates because a stream re-emits, not because you optimistically republished. Persist-before-publish makes crash-safety structural, not a matter of discipline.
6. **Unidirectional data flow.** Intent → ViewModel → repository/service → new state → view. The view never mutates data it reads and never short-circuits back up the chain. Data flows down; events flow up.
7. **Depend on abstractions, injected — never constructed.** A ViewModel receives its repositories/services/clock; it never `new`s a live collaborator and never holds a `BuildContext`. This is what makes it testable with fakes and swappable per flavor.
8. **Model async as an explicit state, not loose flags.** One `AsyncValue` (or a status enum + data + error) rendered exhaustively — never scattered `isLoading`/`hasError` booleans that can encode a half-set, impossible state.
9. **Cascade-clean references on delete.** Deleting an entity must drop every reference to it (assignments, foreign keys, selection) — an item left pointing at a deleted parent is a latent crash. Never silently drop the orphan; re-home or unassign it explicitly.
10. **No `DateTime.now()` in state logic.** "Now" enters through an injected `Clock` (from `package:clock`) exposed as `clockProvider`, so time-dependent behaviour is deterministic in tests (`clockProvider.overrideWithValue(Clock.fixed(t))`). Never `DateTime.now()`, never a bespoke `ClockService`. `service-boundary-and-native` owns the `clockProvider` seam.

## Riverpod: pick the right shape

Match the provider shape to what it owns (full table in `references/ownership-and-lifecycle.md`):

| Owns | Shape |
|---|---|
| Per-feature presentation state over a live query | `StreamNotifier` whose `build()` returns the repository stream |
| Per-feature presentation state, non-stream | `Notifier` / `AsyncNotifier` over one immutable value |
| A reactive projection of the DB | `StreamProvider` over a repository/DAO stream (never stored) |
| An injected collaborator (repo, service, `Clock`) | plain `Provider` (DI) |
| Per-entity/per-session state | `Notifier`/`AsyncNotifier`/`StreamNotifier` `.family` + `.autoDispose` |

Default to **hand-written providers** (`StreamNotifierProvider`/`AsyncNotifierProvider(...)`, `.autoDispose`/`.family` modifiers). `@riverpod` codegen is an optional convenience, not the default (see the reference). Riverpod 3.0 API only — base classes `Notifier`/`AsyncNotifier`/`StreamNotifier`; `autoDispose`/`family` are provider modifiers, never `AutoDispose*`/`*Family` base classes (removed in 3.0).

```dart
// features/task — one StreamNotifier ViewModel: build() returns the LIVE repo stream,
// so a committed write re-emits and the UI updates with no manual republish (D6).
class TaskListNotifier extends StreamNotifier<TaskListState> {
  @override
  Stream<TaskListState> build() {
    final filter = ref.watch(taskFilterProvider);          // in-session filter, its own Notifier
    return ref.watch(taskRepositoryProvider).watchAll()    // the live source of truth
        .map((tasks) => TaskListState(tasks: tasks, filter: filter));
  }

  // Durable act routes through the single write path. void so the call site never drops
  // the Future; no `state = ...` — the committed write makes watchAll() re-emit.
  void complete(TaskId id) =>
      unawaited(ref.read(taskRepositoryProvider).markComplete(id).catchError(_report));

  void _report(Object error, StackTrace stack) {/* surface via a logger — never swallow */}
}

final taskListNotifierProvider =
    StreamNotifierProvider.autoDispose<TaskListNotifier, TaskListState>(
        TaskListNotifier.new);

// The reversible in-session filter is its own tiny Notifier (manual NotifierProvider).
class TaskFilterNotifier extends Notifier<TaskFilter> {
  @override
  TaskFilter build() => TaskFilter.all;
  void set(TaskFilter f) => state = f; // watched by build() above; re-projects the stream
}

final taskFilterProvider =
    NotifierProvider<TaskFilterNotifier, TaskFilter>(TaskFilterNotifier.new);
```

## Riverpod: providers are DI (throwing seams)

A ViewModel reads collaborators from providers; the composition root wires the live impls once. A placeholder seam **throws** until overridden, so an un-wired dependency fails loudly at first read instead of silently constructing a real service inside a test.

```dart
// A seam: throws until a flavor main() overrides it. One live impl per flavor.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('override databaseProvider in main()'),
);

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => TaskRepository(ref.watch(databaseProvider)), // inject, never `new` a live DB here
);
```

```dart
// main.dart — the ONLY place live collaborators are constructed.
void main() {
  final db = AppDatabase.open();
  runApp(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const App(),
  ));
}
```

Before adding a provider, ask whether a **constructor argument** would do. Provider count going up is a smell, not progress — reach for `family`/scoping/codegen only when a plain provider genuinely cannot express the need.

## Riverpod: reads — watch / read / listen

Full rationale in `references/reads-and-side-effects.md`.

- `ref.watch(p)` / `ref.watch(p.select((s) => s.field))` — in `build()`, for display. `.select` narrows the rebuild to one field. Never `watch` a whole controller at the top of a large widget.
- `ref.read(p.notifier)` — in callbacks (`onTap`, `onPressed`). A `read` of a value in `build()` freezes on stale data; a `watch` in a callback rebuilds unexpectedly.
- `ref.listen(p, ...)` — in `build()`, for side effects (navigate, snackbar) on change. Never fire a side effect directly from `build()`.

```dart
class TaskCounter extends ConsumerWidget {
  const TaskCounter({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(taskListNotifierProvider.select((s) => s.value?.openCount ?? 0));
    return Text('$n');
  }
}
```

**The stale-closure hole:** never capture a `ref.watch`ed value into an `onTap` closure — pass a stable key and resolve at tap time via `ref.read`. A captured value silently acts on the *previous* entity after a fast re-tap, and no lint catches it.

```dart
// WRONG — acts on a stale item after a re-render.
onTap: () => ref.read(p.notifier).complete(task),
// RIGHT — id is stable; resolve now.
onTap: () => ref.read(p.notifier).complete(task.id),
```

**Action-path methods return `void`.** An arrow closure `onTap: () => notifier.doThing()` that "returns" a `Future` satisfies neither `discarded_futures` nor `unawaited_futures` (target type is `VoidCallback`), so the Future *and its error* are dropped. A `void` intent method makes the hole unreachable; kick off async inside it with `unawaited(_run().catchError(_report))`. See `async-safety`.

## Riverpod: lifecycle & disposal

- Per-entity/per-session state is `.family`-keyed by a **stable equatable value** (an id or a `@freezed` args record), never a mutable object, and `.autoDispose` so heavy session state dies on unmount.
- App-scope singletons (database, engine, services) are plain `Provider` — never `autoDispose`.
- Guard writes after an `await` with `ref.mounted` (the Riverpod analogue of `use_build_context_synchronously`).
- Release owned resources in `ref.onDispose` (streams, controllers, native handles). Riverpod owns a `StreamProvider`'s subscription, so don't hand-manage it.

## Riverpod: accessibility state does NOT go through providers

Read `MediaQuery.boldTextOf(context)` / `.textScalerOf(context)` / `.highContrastOf(context)` **at build time in the widget**, never via a provider. `MediaQuery` is already an `InheritedWidget` with correct-by-construction invalidation; routing it through a provider means either a `BuildContext` in a provider body or a one-frame-stale hand-sync. App/domain state via Riverpod; platform/a11y state via `BuildContext`. See `accessibility-as-code`.

## Anti-patterns

- **Legacy providers** — `StateProvider` / `StateNotifierProvider` / `ChangeNotifierProvider` (moved to `flutter_riverpod/legacy.dart`), or adding `get_it` / `package:provider` / Bloc alongside Riverpod. Two DI/state mechanisms is strictly worse than one.
- **Business logic in a provider body.** A provider is a thin wire; logic lives in the ViewModel, engine, and repository.
- **Mutating the state value in place** and reassigning the same instance — value-equality listeners won't see it.
- **`ref.watch` at the top of a big widget** rebuilding the whole subtree on any field change. Use `.select` or a leaf `ConsumerWidget`.
- **App/domain state in `setState()`.** `setState`/local `State` is for ephemeral UI only (a toggle, an in-flight animation flag).
- **Optimistic republish before commit** — a crash between republish and commit shows a fact the disk never held.
- **A ViewModel that `new`s its collaborators, holds a `BuildContext`, navigates, or shows snackbars.** Inject; publish state; let the view (or a router redirect) react.
- **`family`-keying on a mutable object**, or `autoDispose` on an app-scope singleton, or `keepAlive()` to undo an `autoDispose` you shouldn't have added.

## Definition of done

- [ ] Feature state is one `Notifier`/`AsyncNotifier`/`StreamNotifier` over an immutable value; widgets hold only ephemeral UI state.
- [ ] State is private; every mutation goes through an intent method that assigns a new value; no in-place mutation.
- [ ] Derived values are getters/stream projections, not stored fields.
- [ ] Async is one `AsyncValue`/status rendered exhaustively; no loose loading/error booleans.
- [ ] Every durable mutation is a repository method that commits before returning; no optimistic pre-commit republish.
- [ ] Reads use `ref.watch`/`.select` for display, `ref.read(p.notifier)` in callbacks, `ref.listen` for side effects; no broad top-level watch; no captured-value closures.
- [ ] Collaborators injected via providers; seams throw until overridden; live impls wired once per flavor in `main`; no `BuildContext`/`DateTime.now()` in the ViewModel.
- [ ] Per-entity providers are `family`-keyed by a stable value and `autoDispose`d; app singletons are plain providers; resources released in `ref.onDispose`.
- [ ] No `legacy.dart`, `get_it`, `package:provider`, or Bloc import (`scripts/ban-legacy-providers.sh` passes).

## Related skills

- `flutter-architecture` — where ViewModels, repositories, and the write path sit in the feature-first DAG.
- `error-handling-typed-results` — the Result/Failure spine a repository method returns instead of throwing.
- `async-safety` — the Future-drop hole, `mounted` guards, subscription/timer disposal.
- `persistence-drift` — the Drift streams the `StreamProvider`s project and the one-transaction-per-mutation write path.
- `service-boundary-and-native` — the throwing-seam provider pattern for every side effect and native channel; owns the `clockProvider` (`package:clock`) seam these ViewModels read instead of `DateTime.now()`.
- `widget-composition` — the dumb `ConsumerWidget` Views that read this state.
- `accessibility-as-code` — the split this skill co-owns: app/domain state via Riverpod, platform/a11y state read from `MediaQuery`/`BuildContext`, never a provider.
- `value-objects-money-and-units` — value types that take a `Clock` param for deterministic time.
- `app-startup-and-bootstrap` — the composition root where `ProviderScope` overrides are wired.

## References

- [Riverpod docs](https://riverpod.dev)
- [Riverpod — Migrating to 3.0](https://riverpod.dev/docs/3.0_migration)
- [Flutter — App architecture guide (MVVM)](https://docs.flutter.dev/app-architecture/guide)
- [Flutter — Simple app state management](https://docs.flutter.dev/data-and-backend/state-mgmt/simple)

## Provider / ChangeNotifier appendix

For the official Flutter-guide stack (`package:provider` + `ChangeNotifier`), the same ten rules hold; only the mechanism changes.

- **ViewModel** = `ChangeNotifier`; **new state** = `notifyListeners()` after all fields are set (exactly once per logical change, never mid-update or in a loop).
- **Private state, exposed immutably.** Fields are `_private`; expose read-only getters; return `List.unmodifiable(...)` — never hand out a mutable collection.
- **DI** = constructor injection of abstractions, wired with `Provider`/`ProxyProvider` above the screen (auto-disposed on pop). Do not use `get_it` as the container.
- **Reads** = `context.select`/`Consumer`/`Selector` for display, `context.read` in callbacks. Read in `didChangeDependencies` or callbacks, never `initState`.
- **Guards** = check a `_disposed` flag before `notifyListeners()` after an `await`; cancel subscriptions and dispose owned controllers in `dispose()`.

```dart
enum ViewStatus { idle, loading, ready, error }

class TaskListViewModel extends ChangeNotifier {
  TaskListViewModel(this._repo);            // injected abstraction
  final TaskRepository _repo;

  ViewStatus _status = ViewStatus.idle;
  ViewStatus get status => _status;
  List<Task> _tasks = const [];
  List<Task> get tasks => List.unmodifiable(_tasks); // immutable view
  int get openCount => _tasks.where((t) => !t.done).length; // derive, don't store

  Future<void> load() async {
    _status = ViewStatus.loading; notifyListeners();
    try {
      _tasks = await _repo.load();
      _status = ViewStatus.ready;
    } catch (_) {
      _status = ViewStatus.error;
    }
    notifyListeners();                        // exactly one, after all fields set
  }

  Future<void> complete(TaskId id) async {
    await _repo.markComplete(id);             // single write path
    _tasks = [for (final t in _tasks) t.id == id ? t.copyWith(done: true) : t];
    notifyListeners();
  }
}
```
