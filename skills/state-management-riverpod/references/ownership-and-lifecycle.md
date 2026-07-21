# Ownership, shapes, and lifecycle

## The ownership table

Every long-lived store is exactly one of four shapes. Pick by what it *owns*, not by habit.

| It owns… | Shape | Notes |
|---|---|---|
| Per-feature presentation state | `StreamNotifier` (build() returns the live repo stream) or `Notifier`/`AsyncNotifier` exposing one immutable value | The ViewModel. Reversible in-session edits stay in the value; durable acts cross the write path and re-emit. |
| A reactive projection of the database | `StreamProvider` over a repository/DAO stream | Never a separately-maintained cache. A committed write re-emits and the UI rebuilds. |
| An injected collaborator | plain `Provider` (DI) | The repository, engine, `Clock`, a platform service. A thin wire — no logic. |
| Per-entity / per-session state | `Notifier`/`AsyncNotifier` `.family` + `.autoDispose` | Keyed by a stable equatable value; disposed on unmount. |

A provider that does domain math reads the wrong layer — that math belongs in the engine/repository. A provider that mutates persisted state directly bypasses the write path.

## Derive-don't-store, applied to Riverpod

A derived read model (a total, a count, a streak, a histogram) is either a getter on the state value or a `StreamProvider` projection over the source query. It is **never** a second stored field or a second cache. There is one source of truth; everything else is computed from it on read. A stored derivation is a bug waiting for the two copies to disagree.

```dart
// Derived read as a projection over the source stream — recomputed, never stored.
final openTaskCountProvider = StreamProvider.autoDispose<int>((ref) {
  return ref.watch(taskRepositoryProvider).watchAll().map(
        (tasks) => tasks.where((t) => !t.done).length,
      );
});
```

## family — key by a stable equatable value

Per-entity state is parameterized with `.family`, keyed by an id or a `@freezed`/record args value with real value equality. Never key by a mutable object (a whole entity, a list, a builder) — the family cache compares keys by equality, and a mutable key both leaks entries and can collide.

```dart
final taskDetailProvider =
    AsyncNotifierProvider.autoDispose.family<TaskDetailNotifier, TaskDetail, TaskId>(
        TaskDetailNotifier.new);
```

## autoDispose — bound memory to screen lifetime

- Per-entity/per-session providers are `.autoDispose`: the heavy state (large collections, controllers, caches) dies when the last listener unmounts.
- App-scope singletons (database, engine, services, settings) are plain `Provider`, **never** `autoDispose` — they are process-lifetime.
- Needing `ref.keepAlive()` usually means `autoDispose` was turned on where it did not belong. Prefer removing `autoDispose` over pinning it alive, unless you genuinely want cache-until-idle semantics.

## ref.onDispose — release what you own

Riverpod owns a `StreamProvider`'s subscription, so you never hand-manage a `StreamSubscription` for it. For anything you construct inside a provider that holds a resource (a controller, a socket, a native handle), release it in `ref.onDispose`.

```dart
final connectionProvider = Provider.autoDispose<Connection>((ref) {
  final conn = Connection.open();
  ref.onDispose(conn.close); // ordinary lifecycle hygiene
  return conn;
});
```

## Composition-root DI

Live collaborators are constructed in exactly one place: `main` (or `main_<flavor>` per flavor), which overrides the throwing seams in the root `ProviderScope`. See `app-startup-and-bootstrap`.

- One live implementation per interface per flavor.
- A placeholder seam throws until overridden — an un-wired dependency fails loudly at first read, never returns silent null data.
- Tests override the same seams with deterministic fakes (or a real in-memory DB), so tests get the app's wiring minus the platform. See `service-boundary-and-native` and `testing-strategy`.

## Minimalism check

Before adding a provider, ask whether a **constructor argument** or a small field would do. Provider count going up is a smell, not progress. Reach for `family`, scoping, or codegen only when a plain hand-written provider genuinely cannot express the need — each adds a cost (a review surface, a dialect, a tooling round-trip) that a small app rarely earns.

## When multi-package (workspace)

In a single-package app all providers live under `lib/`. Only when the app is split into a Dart pub workspace do collaborators (engine, data layer) live in separate packages that the feature package depends on downward; the throwing-seam providers are still declared once and overridden at the app's composition root. Do not introduce package boundaries for a small app. See `project-structure-and-packages`.
