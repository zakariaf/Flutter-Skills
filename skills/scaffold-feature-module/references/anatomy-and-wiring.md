# Feature folder anatomy & Riverpod wiring

The fixed shape of one feature, the providers it owns, and how the ViewModel is wired and tested.

## The folder

```
lib/features/<feature>/
├── presentation/
│   ├── <feature>_screen.dart        # the navigable entry View — a dumb ConsumerWidget
│   ├── <feature>_notifier.dart      # the 1:1 ViewModel: a Notifier / AsyncNotifier
│   ├── <feature>_providers.dart     # this screen's providers, SCOPED to the feature (never global)
│   └── widgets/                     # leaf views (tiles, sheets, forms) — one primary type per file
├── application/                     # (optional) use-cases, ONLY when logic spans repositories
└── domain/
    └── <feature>.dart               # (optional) the feature-local immutable domain model
```

Every file is `lower_snake_case`, named after its single primary public type (see `naming-conventions`).
Small features may colocate the scoped stream inside `<feature>_notifier.dart` and skip a separate
`_providers.dart`; the split is a size call, not a mandate. A feature usually has **no** `data/` folder
— it reads shared repositories from `lib/data/` — and **no** per-feature router: routes live in the one
app router (owned by `navigation-and-routing`). The single-package tree (`lib/core/`, `lib/data/`,
`lib/services/`, `lib/features/`, no `lib/src/`) is owned by `project-structure-and-packages`.

### When multi-package (workspace)

In a Dart pub workspace / Melos monorepo, a *portfolio-wide* screen may live in a shared UI package
(`packages/<shared_ui>/lib/src/features/<feature>/`) and an *app-specific* screen under `apps/<app>/lib/`.
The presentation/application/domain anatomy above is unchanged; only the home differs, and `lib/src/`
is a **package**-only convention (see `project-structure-and-packages`). A shared-package feature must
stay app-agnostic — it depends on injected seams, never a concrete app service. For a **single-package
app (the default)** every feature is a folder under the app's own `lib/features/`; do not split
packages to get this shape.

## The three provider kinds a feature owns

1. **A scoped reactive read** — a `StreamProvider` (usually `family` + `autoDispose`) wrapping a
   repository `.watch(key)`. This is the backbone the View renders.
2. **The command ViewModel** — a `Notifier`/`AsyncNotifier` holding UI/command state and exposing
   intent methods that call repository write methods.
3. **(Optional) derived read providers** — pure projections of (1) via `ref.watch(...).select(...)`
   or a small computed provider. Derive; never store a second copy.

App-scope singletons (the db, repositories, services, clock) are **not** owned by the feature — they
live in the data/composition layer as `keepAlive` providers the feature `ref.watch`es.

## watch / read / listen

| Call | Where | Why |
| --- | --- | --- |
| `ref.watch(p)` | inside `build` | subscribe + rebuild on change |
| `ref.read(p.notifier)` | inside a callback | fire a command without subscribing |
| `ref.listen(p, cb)` | inside `build` (top) | one-shot effects: SnackBar, navigate, dialog |
| `ref.watch(p.select(f))` | inside `build` | rebuild only when the selected slice changes |

Watching in a callback re-subscribes on every tap; reading in `build` silently misses rebuilds. See
`state-management-riverpod` for the complete discipline.

## family + autoDispose vs keepAlive

- **`family`** keys a provider on a stable **equatable** value — an id string, an enum, a small
  `@freezed` args record. Never key on a heavy mutable object (a whole list, a controller).
- **`autoDispose`** disposes the provider when its last listener unmounts — the default for anything
  scoped to a screen or session, so a navigation-away frees its state and a re-entry re-resolves.
- **`keepAlive`** (a provider **without** the `.autoDispose` modifier, or `ref.keepAlive()`) is for
  app-scope singletons and the occasional expensive derived value that must survive a route pop. Never
  `autoDispose` the db/service/repository singletons.
- Free resources in `ref.onDispose(...)` (subscriptions, controllers, timers).

```dart
final taskListProvider =
    StreamProvider.autoDispose.family<List<Task>, String>((ref, projectId) {
  final sub = ref.watch(taskRepositoryProvider).watchTasks(projectId);
  ref.onDispose(() {/* any per-key cleanup */});
  return sub;                               // freed when the last listener unmounts
});
```

## The single write path

Every mutation is one command method on the ViewModel that calls **one** named repository method. The
repository commits (one transaction where the store supports it) and *then* the reactive stream
re-emits — the UI rebuilds itself. There is no second place to update.

```dart
Future<void> complete(String taskId) async {
  // repository opens ONE transaction, commits, THEN the watch stream re-emits — no manual republish.
  final Result<void, Failure> r =
      await ref.read(taskRepositoryProvider).markComplete(taskId);
  if (r case Err(:final failure)) {
    state = AsyncError(failure, StackTrace.current);  // typed failure, localized in the View
  }
}
```

Never: optimistic republish before commit, `setState`, a manual cache poke, or a debounced
"save later" for a durable act. Reversible in-session edits (an undo buffer, a draft being typed)
stay in the ViewModel's state and only the final commit crosses the write path.

## Surfacing a typed Result as AsyncValue

Repositories return a sealed `Result<T, Failure>`. Map it to `AsyncValue` so the View switches
exhaustively and localizes the failure at the edge:

```dart
state = switch (await ref.read(repo).save(draft)) {
  Ok(:final value) => AsyncData(value),
  Err(:final failure) => AsyncError(failure, StackTrace.current),
};
```

The View never sees a raw exception string; it maps `Failure` → a localized message. See
`error-handling-typed-results`.

## Testing the ViewModel

Fake the **repository** (and the clock), never the Notifier. No widget pump; runs in milliseconds.

```dart
class _FakeTaskRepository extends Fake implements TaskRepository {
  @override
  Stream<List<Task>> watchTasks(String projectId) =>
      Stream.value([
        Task(
          id: '1',
          projectId: 'p1',
          title: 'a',
          status: TaskStatus.open,
          createdAtUtc: _fixedInstant,
        ),
      ]);
}

void main() {
  test('taskList maps the repository stream to UI state', () async {
    final container = ProviderContainer.test(overrides: [
      taskRepositoryProvider.overrideWithValue(_FakeTaskRepository()),
      clockProvider.overrideWithValue(Clock.fixed(_fixedInstant)), // package:clock, never DateTime.now()
    ]);
    final tasks = await container.read(taskListProvider('p1').future);
    expect(tasks, hasLength(1));           // verify WIRING + mapping, not domain math
  });
}
```

`ProviderContainer.test()` auto-disposes at test end. Verify wiring and UI-state mapping; leave pure
domain math to the domain layer's own tests. See `testing-strategy`.
