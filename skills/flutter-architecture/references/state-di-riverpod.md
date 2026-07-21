# State + DI with Riverpod 3.x — the context-free wiring

Riverpod is the single mechanism for **both** dependency injection and state. No second DI container
(`get_it`/`injectable`/`package:provider`), no global singletons. This reference covers the wiring the
architecture depends on; for the day-to-day API discipline (watch/read/listen, `.select`, stale
closures) see `state-management-riverpod`.

## Why context-free DI is load-bearing

Real apps do work **outside the widget tree**: a notification callback, a background isolate re-arming
reminders, a warm-up task. Riverpod resolves dependencies without a `BuildContext`, so the *same*
repositories and services are reachable from a screen, a callback, and an isolate — **one wiring,
several call sites.** That is precisely why a `BuildContext`-bound DI container is disqualifying here.

## The layered provider graph (a DAG)

```text
infra (placeholder → overridden at bootstrap)   appDatabaseProvider, appDirsProvider, clockProvider
        ▼
repositories (single source of truth)           taskRepositoryProvider, accountRepositoryProvider …
        ▼
domain/use-cases (only if logic spans repos)     reportProvider (composes >1 repository)
        ▼
presentation ViewModels                          TaskListNotifier (StreamNotifier over the live repo stream)
```

Providers compose downward, mirroring the layer DAG. Cross-layer aggregation is just provider
composition — a report provider `ref.watch`es two repository streams; no manual stream combining.

## keepAlive vs autoDispose

| Provider kind | Lifetime | Example |
| --- | --- | --- |
| Database, key store, repositories, services, `Clock`, app-level settings notifiers (theme/locale) | **`keepAlive`** — built once, disposed on app exit | `appDatabaseProvider`, `taskRepositoryProvider` |
| Cheap derived providers | **`autoDispose`** (the default) | a filtered list |
| Expensive derived providers | `autoDispose` **plus** `ref.keepAlive()` so navigating away doesn't force a recompute | a computed report |
| Per-screen form/controller state | **`autoDispose`** | `taskEditorNotifier` |

Never make a singleton (DB, scheduler) `autoDispose` — it can be torn down mid-operation.

## 1. Placeholder root providers, overridden at startup

The canonical pattern for injecting async-constructed infra — it doubles as the test seam.

```dart
// data/providers.dart
final appDatabaseProvider =
    Provider<AppDatabase>((ref) => throw UnimplementedError('override in bootstrap()'));
// The ONE time type is Clock from package:clock — never a bespoke ClockService, never DateTime.now().
// Tests override with clockProvider.overrideWithValue(Clock.fixed(t)).
final clockProvider = Provider<Clock>((ref) => const Clock());

// An injected id source — the same discipline as the Clock; keeps domain value
// objects free of UI types like UniqueKey.
final idGeneratorProvider =
    Provider<String Function()>((ref) => throw UnimplementedError('override in bootstrap()'));
```

`bootstrap.dart` constructs the real instances and `overrideWithValue`s them in the root
`ProviderScope`. A forgotten override is a **loud** startup crash, not silent null data.

## 2. Repositories: interface only where earned

```dart
// A repository over an in-memory DB is CONCRETE — no interface (it runs in a test).
final taskRepositoryProvider =
    Provider<TaskRepository>((ref) => TaskRepository(ref.watch(appDatabaseProvider)));

// A repository over a NETWORK client earns an interface + a fake.
final remoteSyncProvider =
    Provider<RemoteSync>((ref) => HttpRemoteSync(ref.watch(httpClientProvider)));

// Reactive read = the source of truth. Scope streams so one row change doesn't re-emit app-wide.
// Named for its role (a StreamProvider), distinct from the AsyncNotifierProvider below.
final taskListStreamProvider =
    StreamProvider<List<Task>>((ref) => ref.watch(taskRepositoryProvider).watchTasks());
```

Notifiers and widgets never touch the database directly — always through a repository provider.

## 3. The ViewModel: a live stream + intent methods

`build()` returns the live repository stream; an intent method commits through the single write path
and the **watched stream re-emits**. No manual `state = ...` republish — the reactive read is the one
source of UI truth.

```dart
final class TaskListNotifier extends StreamNotifier<List<Task>> {
  @override
  Stream<List<Task>> build() =>
      ref.watch(taskRepositoryProvider).watchTasks();       // track every emission

  Future<void> add(String title) async {                    // intent method — the durable act
    final id = ref.read(idGeneratorProvider)();
    await ref.read(taskRepositoryProvider).add(Task.create(id: id, title: title));
    // No republish: the committed write makes watchTasks() re-emit and build()'s stream updates state.
  }
}

final taskListNotifierProvider =
    StreamNotifierProvider<TaskListNotifier, List<Task>>(TaskListNotifier.new);
```

A `StreamNotifier`'s `state` is an `AsyncValue<List<Task>>` the View switches on with `.when`; every
repository emission flows through by value equality. Never a mutable field, never `notifyListeners()`.
Use `ref.listen` (not `ref.watch`) in the UI for one-shot SnackBar/navigation reactions.

## 4. Per-entity state: `family` + `autoDispose`

```dart
// Keyed by a stable ID so one entity's state never leaks into another's.
final taskDetailProvider = AsyncNotifierProvider.autoDispose
    .family<TaskDetailNotifier, Task, String>(TaskDetailNotifier.new);
```

Key `family` by a value type (a `String` id, a `freezed` args object) — never by a mutable object.

## 5. Background isolates get NO ProviderScope

A `ProviderContainer` cannot cross isolates. Infra construction lives in **plain top-level factory
functions** that both the app and a fresh in-isolate container call.

```dart
// data/ — plain top-level factory: no Riverpod, no Flutter widgets.
Future<AppDatabase> openAppDatabase(String dbPath) async =>
    AppDatabase(NativeDatabase(File(dbPath)));

// a background entrypoint — builds its own throwaway container from the SAME factory.
@pragma('vm:entry-point')
Future<void> backgroundWork() async {
  final db = await openAppDatabase(await resolveDbPath());
  final container = ProviderContainer(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
  );
  try {
    await container.read(taskRepositoryProvider).reconcile();
  } finally {
    container.dispose();
    await db.close();
  }
}
```

Never reference the UI container or share a `ProviderContainer` across isolates. The local database is
the true source of truth; the isolate rebuilds everything from it.

## Rules

**Do**
- `ref.watch` in `build`/derivations; `ref.read` only in callbacks; `ref.listen` for side-effects.
- Read the DB only through repository providers; wrap store `.watch()` in stream providers.
- Use `ref.watch(p.select((s) => s.field))` + small `ConsumerWidget`s to avoid rebuild storms.
- Offload heavy work to `Isolate.run`/`compute` — never a sync compute in `build`.
- Keep engines/calculators framework-free and `Clock`-injected; providers do only wiring.
- Add `addTearDown(container.dispose)` — or use `ProviderContainer.test()` — in every provider test.

**Don't**
- Touch the database, secure storage, or a platform channel from a widget or ViewModel.
- Introduce a second DI container (`get_it`/`injectable`/`MultiProvider`) or a god `AppState`.
- Make the DB/scheduler `autoDispose`; treat provider memory as durable state.
- Reference providers/`ProviderScope` from a background isolate entrypoint.

## Testing with ProviderContainer overrides

```dart
test('task list emits after add', () async {
  final container = ProviderContainer(overrides: [
    appDatabaseProvider.overrideWithValue(AppDatabase(NativeDatabase.memory())),
  ]);
  addTearDown(container.dispose);

  await container.read(taskListNotifierProvider.notifier).add('write tests');
  final tasks = await container.read(taskListNotifierProvider.future);
  expect(tasks, isNotEmpty);
});
```

- **In-memory DB seam** — override `appDatabaseProvider` with `NativeDatabase.memory()`; the *same*
  override seam serves production startup and tests.
- **Pure calculators** — construct them directly with fakes and an injected `Clock`
  (`package:clock` + `fake_async`); no Riverpod needed.
- **Override style** — `overrideWith((ref) => fake)` for behavior fakes, `overrideWithValue(x)` for
  pre-built instances. Both give per-test isolation with no global mutation (the win over a reset-able
  service locator).
- Prefer **fakes over mocks** for code you own; use `mocktail` (no codegen) where a mock is warranted.

## Packages

```yaml
dependencies:
  flutter_riverpod: ^3.0.0
  riverpod_annotation: ^3.0.0   # if using codegen (@riverpod)
dev_dependencies:
  riverpod_generator: ^3.0.0
  riverpod_lint: ^3.0.0
  custom_lint: ^0.7.0
  mocktail: ^1.0.0
  # NOT used, on purpose: get_it, injectable, package:provider.
```
