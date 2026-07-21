# Reads and side effects: watch / read / listen / select

## The split

| Use | Where | Why |
|---|---|---|
| `ref.watch(p)` | inside `build()`; inside a provider body to depend on another | Rebuild / recompute on change. |
| `ref.watch(p.select((s) => s.field))` | inside `build()` | Rebuild on **one** field only — the surgical rebuild scope. |
| `ref.read(p.notifier)` | inside callbacks (`onTap`, `onPressed`, timers) | No rebuild; fetch the notifier to call an intent method. |
| `ref.read(p)` | rarely, a one-shot value read in a callback | A `read` of a value in `build()` freezes on stale data with no error. |
| `ref.listen(p, cb)` | inside `build()` | Side effects on change (navigate, snackbar). Never fire a side effect directly from `build()`. |

Rule of thumb: **watch to show, read to act, listen to react.**

## .select narrows the rebuild

`ref.watch(p)` at the top of a large widget rebuilds the whole subtree on any field change. Split a leaf `ConsumerWidget` that `watch`es only the field it renders, via `.select`.

```dart
// Rebuilds only when openCount changes, not on every state field.
final n = ref.watch(taskListNotifierProvider.select((s) => s.value?.openCount ?? 0));
```

`.select` must return a value with stable equality — return a scalar or a value-equal object, never a freshly-allocated list/map each call (that always compares unequal and defeats the point).

## The stale-closure hole (no lint catches it)

Never capture a `ref.watch`ed value into an `onTap` closure. On a fast re-tap after a re-render, the closure acts on the **previous** entity — the wrong action, silently. Pass a stable key and resolve at tap time with `ref.read`.

```dart
// WRONG — captures `task`; a re-tap after rebuild acts on a stale item.
onTap: () => ref.read(p.notifier).complete(task),

// RIGHT — id is a stable primary key; position/identity cannot go stale.
onTap: () => ref.read(p.notifier).complete(task.id),
```

Inside the intent method, resolve the entity *now* via `ref.read`.

## Action-path methods return `void`

An arrow closure that "returns" a `Future` into a `VoidCallback` target drops the `Future` **and its error**, and satisfies neither `discarded_futures` nor `unawaited_futures` — the lints think it is handled because the closure returns it, but the target type discards it. This is the silence bug.

A `void`-returning intent method makes the hole unreachable by construction: a callback never holds a `Future` to drop. Start async work *inside* the method and attach an error sink.

```dart
class TaskNotifier extends Notifier<TaskUiState> {
  // VOID, deliberately. Do not "improve" to return a Future.
  void complete(TaskId id) {
    unawaited(_complete(id).catchError(_recordAndShow));
  }

  Future<void> _complete(TaskId id) async {
    await ref.read(taskRepositoryProvider).markComplete(id);
    if (!ref.mounted) return;              // guard state writes after await
    state = state.copyWith(lastCompleted: id);
  }
}
```

See `async-safety` for the full Future-drop discussion.

## Guarding after await

- In a `Notifier`/`AsyncNotifier`, `ref.mounted` guards a `state` write after an `await` — the Riverpod analogue of `use_build_context_synchronously`.
- In a widget callback that touches `BuildContext` after an `await`, check `context.mounted`. Prefer resolving everything you need from `ref`/`context` *before* the await.

## ref.listen for side effects

React to a state change with a side effect exactly once per change — never by running the effect inline in `build()` (which fires on every rebuild).

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  ref.listen(taskListNotifierProvider, (prev, next) {
    if (next.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed')));
    }
  });
  // ...
}
```

## Rendering AsyncValue

Consume an `AsyncValue` with `.when` (or a `switch` over its sealed shape) and handle **every** arm — a missing/empty arm becomes a collapsed or frozen UI. No hand-rolled `isLoading`/`hasError` booleans.

```dart
ref.watch(taskListNotifierProvider).when(
  loading: () => const CircularProgressIndicator(),
  error: (e, _) => RetryView(onRetry: () => ref.invalidate(taskListNotifierProvider)),
  data: (s) => TaskListView(state: s),
);
```
