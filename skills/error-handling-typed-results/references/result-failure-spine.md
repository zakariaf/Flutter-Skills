# Result / Failure spine, the global net, isolate re-wrap & logging

The full detail behind the two-tier model. Tier 1 is typed values at every boundary; tier 2 is exceptions-for-bugs-only routed to the global net. Keep the spine (`Result` + `Failure`) in a Flutter-free layer so pure logic and repositories import the same vocabulary.

> **App shape.** In a single-package app these live in `lib/core/`. **When multi-package (workspace):** put the spine in a Flutter-free `packages/core` so pure Dart packages can depend on it without a Flutter SDK constraint. Never present the multi-package split as required for a small app.

## The `Result` spine

Hand-rolled, zero-dependency, native Dart 3 `sealed`. Keep the operator set small.

```dart
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

  Result<R, F> flatMap<R>(Result<R, F> Function(T) f) => switch (this) {
        Ok(:final value) => f(value),
        Err(:final failure) => Err(failure),
      };

  bool get isOk => this is Ok<T, F>;
}
```

If you want ready-made `mapError`/`AsyncResult`, adopt `result_dart` **across the codebase** — do not hand-roll half and import the other half. Do not adopt Flutter's published generic `Result<T>` sealed type for the error spine: its error arm is typed `Object`, so matching it tells you *nothing about which failure* (zero exhaustiveness, the whole property you want), and it names a variant `Error`, shadowing `dart:core.Error`.

## Why `F extends Failure`, not `Result<T>`

A bare `Result<T>` (or `Either<Object, T>`) has no type to switch on — the failure case gets silently collapsed. Parameterising the error as `F extends Failure` and giving **each boundary its own sealed family** is what makes `switch` exhaustive and "added a new failure" a compile error at every call site.

## Failure taxonomy per boundary

Each boundary (repository, service, DAO group) owns a `sealed` family. `code` is a stable, localization-key-like identifier; params are typed; **no user-facing strings anywhere**.

| Boundary family | Example subtypes (code) | Typed params |
| --- | --- | --- |
| `DbFailure` | `NotFound` (`db.not_found`) | `String entity, String id` |
| | `ConstraintViolated` (`db.constraint_violated`) | `String field` |
| | `TransactionRolledBack` (`db.transaction_rolled_back`) | — |
| `BackupFailure` | `WriteFailed` (`backup.write_failed`) | — |
| | `VerifyFailed` (`backup.verify_failed`) | — |
| `NotificationFailure` | `PermissionDenied` (`notif.permission_denied`) | — |
| | `ExactAlarmDenied` (`notif.exact_alarm_denied`) | — |
| | `PendingCapExceeded` (`notif.pending_cap_exceeded`) | `int requested` |
| `ComputeFailure` | `ComputeFailed` (`compute.failed`) | `String stage` |
| `ValidationFailure` | `ValidationFailure` (`validation.field_errors`) | `List<FieldError> fieldErrors` |

```dart
sealed class Failure {
  const Failure();
  String get code; // stable, localization-key-like, e.g. 'db.not_found'
}

sealed class NotificationFailure extends Failure {
  const NotificationFailure();
}

final class PermissionDenied extends NotificationFailure {
  const PermissionDenied();
  @override
  String get code => 'notif.permission_denied';
}

final class PendingCapExceeded extends NotificationFailure {
  const PendingCapExceeded(this.requested);
  final int requested; // e.g. budgeted against a platform pending-notification cap
  @override
  String get code => 'notif.pending_cap_exceeded';
}
```

**Localization contract.** The UI maps `code` → a gen-l10n key at the presentation edge. A `Failure` × `supportedLocales` exhaustiveness test guarantees every code has a message in every language — a missing translation becomes a test failure, not a runtime blank. See `i18n-rtl-l10n`.

## Convert-at-the-boundary

Wrap each dangerous call **once**, at its boundary. Catch narrowly with an `on` clause; log the original exception + stack **before** returning the typed failure.

```dart
Future<Result<Product, DbFailure>> insertProduct(ProductDraft d) async {
  try {
    return Ok((await _dao.insert(d)).toDomain());
  } on SqliteException catch (e, st) {
    _log.error('db.insert_product', e, st); // local log FIRST
    return Err(_mapDbException(e));          // then the typed, string-free failure
  }
}

DbFailure _mapDbException(SqliteException e) => switch (e.resultCode) {
      19 /* SQLITE_CONSTRAINT */ => ConstraintViolated(_offendingColumn(e)),
      _ => const TransactionRolledBack(),
    };

// drift/sqlite3 `SqliteException` exposes resultCode / extendedResultCode /
// message / explanation — there is NO `tableName`/column field. Recover a
// best-effort column name from the message ('UNIQUE constraint failed:
// products.sku' -> 'products.sku'); fall back when the driver omits it.
String _offendingColumn(SqliteException e) {
  final m = RegExp(r'constraint failed:\s*([\w.]+)').firstMatch(e.message);
  return m?.group(1) ?? 'unknown';
}
```

Use `on Exception catch` when the plugin only throws exceptions, `on Object catch` when it can throw `Error`s across a channel — never a bare/underscore catch.

## Global safety net — exceptions-for-bugs-only

Anything *thrown* is a programmer error or a truly-unrecoverable state — never a recoverable failure (those are typed `Result` values that never throw across a layer, so they never reach the net). This skill owns only that taxonomy of what the net routes into.

**`app-startup-and-bootstrap` owns the net and everything about installing it** — do not restate its `bootstrap()` here. It installs the two handlers before `runApp`: `FlutterError.onError` (build/layout/paint sync errors) and `PlatformDispatcher.instance.onError` (async + platform-channel errors — notifications, permissions, secure storage — that never reach `FlutterError.onError`), with `onError` returning `true`, no `runZonedGuarded`, and `ProviderException` unwrapped before logging so the trace records the cause, not the wrapper. The `runZonedGuarded`-only-for-a-crash-SDK decision is in `mechanism-selection.md`.

## Isolate error re-wrapping

Heavy work runs via `Isolate.run`/`compute`. **Isolate errors do not hit `FlutterError.onError`** — re-wrap them as `Result` across the boundary rather than letting them propagate opaquely.

```dart
Future<Result<Report, ComputeFailure>> computeReport(ReportInput input) async {
  try {
    return Ok(await Isolate.run(() => ReportBuilder().run(input)));
  } on Object catch (e, st) {
    _log.error('compute.report', e, st);
    return const Err(ComputeFailed('report'));
  }
}
```

The engine args/results crossing the isolate boundary must be serializable immutable value types.

## Local structured logging

Severity + module + stable code + **redacted** context to a size-capped rotating file in the app-support dir (`logger` with a custom `FileOutput`, or `dart:developer` `log` for a lighter footprint). Expose a user-initiated "Export diagnostics" affordance so users attach logs to a bug report themselves.

- **Redact** any PII (free-text notes, identifiers, location) before writing.
- Rotate at a fixed byte cap (e.g. a few files of ~1 MiB); drop the oldest.
- The logger must be **incapable of throwing** — it runs inside the error handlers, so a throw there re-enters the handler and recurses until the app dies. This is the one place a bare, intentionally-discarded catch is licensed, and it must carry the exact marker `// ignore: swallowed_catch` on (or immediately next to) the `catch` line. That marker is the ONLY escape hatch `scripts/check-swallowed-catch.sh` honors — the licensed exception and the gate agree on one token; nothing else swallows.

```dart
void record(String message, StackTrace? stack) {
  try {
    // ... bounded, synchronous, flushed, redacted write ...
  } catch (_) {
    // ignore: swallowed_catch — INTENTIONAL, and the ONE licensed bare catch.
    // This runs inside FlutterError.onError / PlatformDispatcher.onError; if it
    // throws, the handler's error re-enters the handler and recurses until the
    // app dies. Do NOT rethrow or log here.
  }
}
```

## Accumulative validation

Field validators accumulate **all** errors (applicative style), not fail-fast, so the form shows every problem at once. **Normalize before parse** and use `tryParse` (never a throwing `parse`) so a `FormatException` never escapes on valid-looking input. Numeral/locale normalization (Eastern-Arabic/Persian digits, non-ASCII decimal/grouping separators) is owned by `i18n-rtl-l10n` — call its normalizer here, do not re-implement it.

```dart
Result<Item, ValidationFailure> validateItem(RawItemForm raw) {
  final errors = <FieldError>[];

  final quantity = _int(raw.quantity, 'quantity', errors);
  final price = _decimal(raw.price, 'price', errors);

  if (errors.isNotEmpty) return Err(ValidationFailure(errors));
  return Ok(Item(quantity: quantity!, price: price!));
}

int? _int(String input, String field, List<FieldError> errors) {
  final v = int.tryParse(normalizeNumerals(input).trim()); // normalizer from i18n skill
  if (v == null || v < 0) {
    errors.add(FieldError(field, 'not_a_number')); // stable reason code, not a string
    return null;
  }
  return v;
}
```

`FieldError` carries a field name + a stable reason code (`'not_a_number'`, `'out_of_range'`); the form maps the reason to a gen-l10n message.

## Pitfalls

- **User strings in `Failure`/`Exception`** — breaks translation, RTL mirroring, numeral localization.
- **Silent swallow** (`catch (_) {}` / bare `catch (e)`) — discards type *and* stack.
- **`default:` on a sealed switch** — a new failure subtype slips through at compile time.
- **Treating plugin/permission errors as sync** — they are async MethodChannel errors NOT caught by `FlutterError.onError`.
- **Letting a `FormatException` bubble from `parse`** — normalize, then `tryParse`.
- **Logging the Riverpod wrapper instead of the cause** — unwrap before writing.
