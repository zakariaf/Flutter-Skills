---
name: error-handling-typed-results
description: Enforces a typed-error spine — a hand-rolled sealed Result<T,F> plus one per-boundary sealed Failure carrying a stable code and typed params (never a localized string), returned instead of thrown; recoverable failures are values, only bugs throw. Convert-at-boundary catches narrowly with an on-clause and logs the original error+stack BEFORE returning a typed Failure; call sites switch exhaustively with no default:; the taxonomy of what the global error net (FlutterError.onError + PlatformDispatcher.onError, installed by app-startup-and-bootstrap) routes into, plus Isolate.run re-wrapping; mechanism selection (Error vs assert vs Exception vs sealed outcome) and @useResult; and a never-lose-data layer (one-transaction-per-mutation, debounced autosave drafts, optimistic soft-delete/Undo). Use when writing result.dart/failures.dart, a try/catch or sealed-switch default:, wiring bootstrap handlers, a repository/service/DAO boundary, or transactions, drafts, or soft-delete/Undo.
---

# Error Handling — Typed Results

Recoverable failures are typed **values** that flow through the layers and are switched on exhaustively; only genuine bugs and unrecoverable states throw, and those are caught once by a global net. Wrapped around both, never-lose-data — transactions, autosave drafts, soft-delete/Undo — is a first-class subsystem, not plumbing. Two tiers, no middle ground.

Read the reference for the task at hand:
- `references/result-failure-spine.md` — the `Result`/`Failure` source, the per-boundary taxonomy, convert-at-boundary, the global net, isolate re-wrapping, and local logging.
- `references/mechanism-selection.md` — throw vs `assert` vs `Exception` vs sealed outcome, `@useResult`, and the runZonedGuarded decision.
- `references/never-lose-data.md` — one transaction per mutation, debounced autosave drafts, optimistic soft-delete / Trash / Undo behind one filter.

Run `scripts/check-swallowed-catch.sh` and `scripts/check-softdelete-parity.sh` before a PR.

## Non-negotiable rules

1. **Model recoverable failures as values, not exceptions.** Anything that fails for a runtime reason the caller must handle — DB error, file/backup I/O, notification scheduling, an expected not-found, invalid input — returns `Result<T, F extends Failure>` (sealed `Ok`/`Err`). Throwing across a layer for an *expected* failure is a review reject.
2. **Hand-roll one zero-dependency sealed `Result` and `Failure` in a Flutter-free layer** so pure logic and repositories share ONE vocabulary. `result_dart` is the sanctioned drop-in if you want ready-made `flatMap`/`mapError`/`AsyncResult` — adopt it wholesale or hand-roll; never mix both.
3. **One sealed `Failure` family per boundary, each subtype carrying a stable `code` + typed params — NEVER a user-facing or localized string.** A baked-in message breaks translation, RTL mirroring, and numeral rendering. Localize from the `code` at the presentation edge.
4. **`switch` failures exhaustively with NO `default:` / `case _:`.** Sealed exhaustiveness turns "added a new failure" into a *compile error* until every switch covers it; a `default:` silently defeats the only compiler-grade safety net you have.
5. **Convert at the boundary — log first, then return.** Wrap each dangerous call once, catch narrowly with an `on` clause, **log the original error + stack to the local log BEFORE returning** the typed failure. A `PlatformException`/`SqliteException`/`FormatException` never leaks past its adapter into a Notifier or widget.
6. **Never swallow.** `catch (_) {}`, bare `catch (e)` that discards type/stack, and `throw e` (use `rethrow`) are banned — CI greps for them. Never catch `Error` subtypes (`StateError`, `AssertionError`): those are bugs, let them crash in debug.
7. **Keep pure logic total — it never throws.** Every pure function returns a value for every input; uncertainty is an explicit output (an `outOfRange` variant, a clamped value). Programmer invariants use `assert` (stripped in release). Async/error handling lives *outside* pure code, at the boundary seam.
8. **Anything *thrown* is a bug or unrecoverable state, routed to the global net — never a recoverable failure.** Recoverable failures are typed `Result` values that never throw across a layer, so they never reach the net. The two handlers (`FlutterError.onError` + `PlatformDispatcher.instance.onError`) and their install order are owned by `app-startup-and-bootstrap`; this skill owns only the taxonomy of what reaches them. The `runZonedGuarded`-only-for-a-crash-SDK decision is in `references/mechanism-selection.md`.
9. **Re-wrap `Isolate.run`/`compute` errors as `Result` at the call site.** Isolate errors do **not** hit `FlutterError.onError`; catch them where you await or they propagate opaquely.
10. **Log locally only.** A size-capped rotating file plus a user-initiated "Export diagnostics" affordance. If you ship a crash SDK, that is a deliberate choice with its own zone; otherwise no Crashlytics/Sentry/Firebase.
11. **Never lose hand-entered data.** One `transaction(...)` per multi-table mutation (all-or-nothing); persist in-progress form state to a debounced `drafts` table; delete via `is_deleted` soft-delete behind a single shared filter, with SnackBar Undo. Detail in `references/never-lose-data.md`.

## The Result + Failure spine

Native Dart 3 `sealed`, zero dependencies. Pure logic and repositories return the same type.

```dart
// lib/core/result.dart — Flutter-free.
sealed class Result<T, F extends Failure> {
  const Result();
}

final class Ok<T, F extends Failure> extends Result<T, F> {
  const Ok(this.value);
  final T value;
}

final class Err<T, F extends Failure> extends Result<T, F> {
  const Err(this.failure);
  final F failure;
}

extension ResultX<T, F extends Failure> on Result<T, F> {
  R fold<R>(R Function(T) onOk, R Function(F) onErr) => switch (this) {
        Ok(:final value) => onOk(value),
        Err(:final failure) => onErr(failure),
      };
  Result<R, F> map<R>(R Function(T) f) => switch (this) {
        Ok(:final value) => Ok(f(value)),
        Err(:final failure) => Err(failure),
      };
}
```

```dart
// lib/core/failure.dart — one family per boundary; code + typed params, no strings.
sealed class Failure {
  const Failure();
  String get code; // stable, localization-key-like, e.g. 'db.not_found'
}

sealed class OrderFailure extends Failure {
  const OrderFailure();
}

final class OrderNotFound extends OrderFailure {
  const OrderNotFound(this.id);
  final String id;
  @override
  String get code => 'order.not_found';
}

final class OrderConstraintViolated extends OrderFailure {
  const OrderConstraintViolated(this.field);
  final String field;
  @override
  String get code => 'order.constraint_violated';
}

final class OrderStoreUnavailable extends OrderFailure {
  const OrderStoreUnavailable();
  @override
  String get code => 'order.store_unavailable';
}
```

Sealed variants are `final class` + `const` ctor + `final` fields. You switch on the type; you never compare instances, so do not write `==`/`hashCode` or reach for freezed/equatable here.

## Convert at the boundary

Wrap the dangerous call once. Log the original exception + stack **before** returning a typed, string-free failure. `@useResult` makes discarding the outcome a lint error.

```dart
// lib/data/order_repository.dart — the ONLY place the store SDK is imported.
@useResult
Future<Result<Order, OrderFailure>> findOrder(String id) async {
  try {
    final row = await _dao.byId(id).timeout(const Duration(seconds: 5));
    if (row == null) return Err(OrderNotFound(id));
    return Ok(row.toDomain());
  } on TimeoutException catch (e, st) {
    _log.error('order.find.timeout', e, st); // log FIRST — never swallow
    return const Err(OrderStoreUnavailable());
  } on SqliteException catch (e, st) {
    _log.error('order.find.db', e, st);
    return Err(_mapDbException(e)); // typed, stable code, no strings
  }
}
```

## Exhaustive switch at the call site

The Notifier (ViewModel) switches every case; localization happens here, from the `code`.

```dart
// lib/features/order/order_notifier.dart — manual Riverpod 3.x AsyncNotifier
// ViewModel. Hand-written providers are the default; `@riverpod` codegen is an
// optional alternative (see state-management-riverpod). `autoDispose`/`family`
// are provider MODIFIERS — never AutoDispose*/*Family base classes, which were
// removed in 3.0. The family arg (the order id) is read via `arg`.
final orderNotifierProvider =
    AsyncNotifierProvider.autoDispose.family<OrderNotifier, Order, String>(
        OrderNotifier.new);

class OrderNotifier extends AsyncNotifier<Order> {
  @override
  Future<Order> build() async {
    switch (await ref.watch(orderRepositoryProvider).findOrder(arg)) {
      case Ok(:final value):
        return value;
      case Err(:final failure): // sealed => no default:; adding a case is a compile error
        throw OrderLoadException(failure); // surfaces as AsyncValue.error to the View
    }
  }
}

// A View renders AsyncValue loading/error/data; it maps failure.code to a localized string.
```

For UI that recovers per-case rather than showing a generic error, switch the failure in the widget and map each `code` to an l10n message — never a `default:`.

## The global net routes only thrown bugs

`app-startup-and-bootstrap` owns the net and everything about it: the two handlers — `FlutterError.onError` (build/layout/paint sync errors) and `PlatformDispatcher.instance.onError` (async + platform-channel errors) — installed before `runApp`, `onError` returning `true`, no `runZonedGuarded`, and `ProviderException` unwrapped before logging. Do not restate that `bootstrap()` here.

What this skill owns is the *taxonomy* of what reaches those handlers: only genuine bugs and unrecoverable states. Every recoverable failure is a typed `Result`/`Failure` value that never throws across a layer, so it never reaches the net. Isolate errors are the one thrown category the net misses — re-wrap them as `Result` at the call site (below).

## Isolate error re-wrapping

```dart
// Heavy work runs off the UI isolate; its errors do NOT reach FlutterError.onError.
Future<Result<Report, ComputeFailure>> buildReport(ReportInput input) async {
  try {
    return Ok(await Isolate.run(() => ReportBuilder().run(input)));
  } on Object catch (e, st) {
    _log.error('report.compute', e, st);
    return const Err(ComputeFailed('report'));
  }
}
```

## Anti-patterns

- **`catch (_) {}` / bare `catch (e)`** — discards type *and* stack; fatal when the lost data can't be re-fetched. Catch narrowly and log `(e, st)`.
- **A user-facing `String` inside a `Failure`/`Exception`** — breaks translation, RTL mirroring, numeral rendering. Codes + typed params only.
- **`default:` / `case _:` on a sealed switch** — a new failure subtype slips through unhandled; you lose compile-time exhaustiveness.
- **`throw e;` in a catch** — resets the stack to the rethrow line. Use `rethrow`.
- **A low-level exception in the UI** — `PlatformException`/`SqliteException`/`FormatException` reaching a Notifier or widget. Convert it at the adapter.
- **`throw` inside pure logic for uncertainty** — keep it total; return an explicit "cannot within budget" value.
- **Catching `Error` subtypes "to be safe"** — you are hiding a bug; let it crash in debug.
- **A generic `Result<T>` whose error arm is `Exception`/`Object`** — no type to switch on; every case gets silently dropped. Type the error as `F extends Failure`.
- **`assert` on a platform/plugin return value** — the assert is stripped in release, so the real-device failure becomes total silence. Return a typed failure instead.
- **Treating notification/permission/plugin errors as sync** — they are async MethodChannel errors; catch at the call site AND rely on `PlatformDispatcher.onError`.
- **A multi-table write without a transaction** — a half-applied write silently corrupts derived data with no way to notice offline.
- **A second analytics/chart query that bypasses the shared soft-delete filter** — deleted rows silently pollute reports. One filter, every read.

## Definition of done

- [ ] Recoverable failures return a sealed `Result<T, F>`; every call site `switch`es all cases with no `default:`.
- [ ] Each boundary owns one sealed `Failure`; every subtype carries a stable `code` + typed params, zero localized strings.
- [ ] Pure logic stays total (returns, never throws); error handling lives at the repository/service/DAO seam.
- [ ] Boundary catches are narrow (`on` clauses), log `(e, st)` FIRST, then return a typed `Err`; no bare/empty catch; `rethrow` preserves stacks.
- [ ] Only bugs/unrecoverable states are thrown into the global net (installed by `app-startup-and-bootstrap`); no recoverable failure throws across a layer.
- [ ] `Isolate.run`/`compute` calls re-wrap errors as `Result` at the call site.
- [ ] Multi-table mutations run in one transaction; in-progress forms autosave on a debounce; deletes are soft + reversible behind a single shared filter.
- [ ] `scripts/check-swallowed-catch.sh` and `scripts/check-softdelete-parity.sh` pass.

## Related skills

- See `async-safety` for the arrow-callback Future-drop hole no lint catches, `unawaited`/`.timeout`/`mounted` discipline, and subscription/timer disposal.
- See `dart3-idioms-and-coding-standards` for sealed classes, exhaustive `switch` expressions, and total non-throwing functions.
- See `state-management-riverpod` for AsyncNotifier ViewModels, `AsyncValue` loading/error/data, and providers-as-DI.
- See `app-startup-and-bootstrap` for `main()` ordering and where the global error handlers install.
- See `persistence-drift` for the DAO/transaction machinery, `run-migration` for schema evolution.
- See `service-boundary-and-native` for the injectable-interface seam where SDK/plugin exceptions are caught and converted.
- See `i18n-rtl-l10n` for mapping a failure `code` to a localized message and for numeral normalize-before-parse (do not duplicate it here).
- See `testing-strategy` for asserting on `Err` branches and `fake_async` clock-driven debounce/purge tests.
- See `lint-and-style-config` for promoting `avoid_catches_without_on_clauses`, `unawaited_futures`, and `unused_result` to errors.
- See `ui-states-and-feedback` for how a `Failure` code becomes an error state, a snackbar, or an Undo — never a rendered exception.
- See `data-export-and-restore` for the user-facing end of never-lose-data: versioned backups and an all-or-nothing restore.

## References

- Dart — [Error handling](https://dart.dev/language/error-handling) (exceptions vs errors, `rethrow`, catch specificity)
- Dart — [Branches: exhaustive switch](https://dart.dev/language/branches#exhaustiveness-checking) and [class modifiers: `sealed`](https://dart.dev/language/class-modifiers#sealed)
- Dart — [Concurrency](https://dart.dev/language/concurrency) (`Isolate.run`, message passing)
- Flutter — [Handling errors in Flutter](https://docs.flutter.dev/testing/errors) (`FlutterError.onError`, `PlatformDispatcher.instance.onError`)
- Riverpod — [AsyncNotifier / AsyncValue](https://riverpod.dev/docs/concepts/providers)
- pub.dev — [result_dart](https://pub.dev/packages/result_dart) · [clock](https://pub.dev/packages/clock) · [meta (`@useResult`)](https://pub.dev/packages/meta)
