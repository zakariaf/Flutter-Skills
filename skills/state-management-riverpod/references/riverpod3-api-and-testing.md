# Riverpod 3.x API shifts, tutorials' mistakes, and testing

## What older tutorials get wrong

| Thing | Status in 3.x |
|---|---|
| `StateProvider` | Banned. A mutable global with extra steps; a `Notifier` expresses the same intent honestly. |
| `StateNotifierProvider` | Legacy. `Notifier` + `NotifierProvider` is the idiom. |
| `ChangeNotifierProvider` (Riverpod) | Legacy. Use `Notifier`/`AsyncNotifier`. (`package:provider`'s `ChangeNotifier` is a different stack — see the SKILL appendix.) |
| Legacy providers' home | Moved to `package:flutter_riverpod/legacy.dart`. Importing that file is a CI-failing grep. |
| `Notifier` / `AsyncNotifier` | The idiom for anything with methods — a `Notifier` **is** the ViewModel. |
| "Notifiers are recreated on every rebuild" | **False** — reverted before stable. Notifiers are preserved across rebuilds. Do not restructure around the myth. |
| `overrideValue` | Does not exist. The method is **`overrideWithValue`** (and `overrideWith` for a builder). |
| `createContainer` + `addTearDown(container.dispose)` | Obsolete. `ProviderContainer.test()` self-disposes. |
| `autoDispose` interface clones (`AutoDisposeRef`, `AutoDisposeNotifier`) | Removed as separate types; `autoDispose` behaviour still exists. Migrating spelling is cosmetic. |

## Codegen (`@riverpod`): optional, opt-in

For a handful of hand-written providers, codegen buys inferred types and argument-typed families at the cost of a `build_runner` round-trip, a generated-file review surface, and a second dialect. It is worth it when a codebase leans on families and inferred provider types at scale; skip it when a few plain declarations are readable with zero tooling.

One asymmetry that bites: **`autoDispose` defaults to `false` for hand-written providers and `true` under codegen.** If you mix the two, be explicit. If you use codegen, adopt it consistently and run it through `run-codegen` / `codegen-and-toolchain`.

## Retry behaviour

Riverpod 3 retries failing providers by default (exponential backoff, bounded). For an app whose provider failures are real, local bugs (a corrupt DB, a missing file) rather than transient network blips, retrying just hides the failure behind a spinner. Disable it where failure should be loud:

```dart
ProviderScope(
  retry: (retryCount, error) => null, // null disables; tune per app
  overrides: [/* ... */],
  child: const App(),
);
```

An app *with* a network may want the default backoff for network-backed providers and `null` for local ones. Decide deliberately; do not leave it to default without a reason.

## Logging provider failures

Riverpod 3 rethrows provider failures wrapped in a `ProviderException`. **Unwrap it before logging** — logging the wrapper records `ProviderException` on every entry and destroys the diagnostic signal. Log the underlying cause and stack.

## Testing seams

Override the throwing seams; test the units behind them, not the framework.

```dart
test('completing a task commits through the single write path', () async {
  // ProviderContainer.test() self-disposes — no manual addTearDown.
  final container = ProviderContainer.test(
    overrides: [
      databaseProvider.overrideWithValue(db),           // real in-memory DB, not a fake
      clockProvider.overrideWithValue(Clock.fixed(t)),  // package:clock, deterministic time
    ],
  );
  // complete() is a void intent method; it owns its Future internally.
  container.read(taskListNotifierProvider.notifier).complete(id);
  await pumpEventQueue();                                // let the write + stream re-emit settle
  // assert against the repository / DB state, not the provider
});
```

Guidelines (see `testing-strategy`):

- **Do not test the providers themselves.** Asserting that `ref.watch` propagates tests Riverpod. Test the repository, the pure core, and the widgets — override seams to reach them.
- **Prefer a real in-memory DB over a mocked DAO** for owned code: a map-backed fake accepts rows the real schema rejects and never runs a migration.
- **Widget tests go through a shared `pumpApp` harness** that supplies default seam overrides and appends caller overrides after them, so a caller's override wins. See `widget-golden-and-a11y-testing`.
- **Lint config:** keep `missing_provider_scope` on (no `ProviderScope` means every read throws on first use). Turn `riverpod_syntax_error` off unless you use codegen — it references generator internals and is dead config otherwise. See `lint-and-style-config`.
