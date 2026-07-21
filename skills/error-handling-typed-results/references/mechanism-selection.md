# Which failure mechanism to use, `@useResult`, and the runZonedGuarded decision

Before you write a failing function, choose the mechanism. Four options, one decision each.

## 1. Pick the mechanism

| Kind | Means | Use it for |
| --- | --- | --- |
| `Error` subclass | **A bug in this code.** Never catch it. | Programmer errors only (`ArgumentError`, `StateError`) |
| `assert` | A bug an invariant catches, **debug only** (stripped in release) | Internal invariants: index bounds, non-empty preconditions |
| `Exception` | Something the environment did that a boundary will catch | drift/SQLite, file I/O, platform channels — caught at the seam |
| **Sealed outcome (`Result`/`Failure`)** | An **expected, individually actionable** failure carrying a payload | Any failure the caller must handle: not-found, permission denied, invalid input |

The line that decides `assert` vs sealed outcome: **`assert` is stripped in release.** `assert(await plugin.setUp() == ok)` is green in every test and *absent on the device* — the perfect silent-failure bug. Asserts cover ground *this code* owns (a violated internal invariant). Sealed outcomes cover ground the *environment* owns (a plugin, the OS, the user's input).

```dart
// RIGHT — an internal invariant this code could violate.
Cell({required this.row, required this.col})
    : assert(row >= 0 && col >= 0, 'negative coordinate is a bug');

// WRONG — the platform violates this at runtime, in release, where the assert
// does not exist. Availability is a fact about the environment, not our bug.
Future<void> announce(String text) async {
  assert(await _tts.setVoice(v) == 1); // vanishes in release → total silence
}
```

Rules that fall out of this:

- **Never `assert` on a platform/plugin/channel return value.** Return a typed failure instead.
- **Never catch an `Error` subtype** to "be safe" — you are hiding a bug that should crash in debug.
- **Never `throw e` in a catch** — it resets the stack to the rethrow line; with a local-only log the on-device trace is your entire forensic record. Use `rethrow`.
- **Never parse a platform-channel payload with a cast.** Everything crossing a channel is `Map<Object?, Object?>`; use `tryParse` + null checks.

## 2. `@useResult` is load-bearing

A `Result`-returning method should be annotated `@useResult` so that discarding the outcome is a lint diagnostic:

```dart
@useResult
Future<Result<Order, OrderFailure>> place(OrderDraft d);
```

Without it, `await place(d);` (outcome discarded) compiles clean and the failure vanishes. `@useResult` only *bites* when `unused_result` is promoted to **error** in `analysis_options.yaml` — its default severity is a warning a solo dev scrolls past. See `lint-and-style-config`.

### The lint hole no rule sees

With `discarded_futures`, `unawaited_futures`, and `unused_result` all promoted to error, one wiring still slips through **every** rule:

| Code | Diagnostics |
| --- | --- |
| `onTap: () => c.place(d)` | **NONE.** All three miss it. |
| `onTap: () { c.place(d); }` | `discarded_futures` + `unused_result` |
| `onTap: () async { c.place(d); }` | `unawaited_futures` + `unused_result` |
| `onTap: () => c.placeNow(d)` | clean — the fix |

The arrow closure *returns* the Future, so every rule considers it "used"; the target type is `VoidCallback`, so Dart's void-compatibility silently discards it — Future and error both vanish. **The fix is structural: a callback must never touch a Future.** Expose a `void`-returning intent method that internally `unawaited(...)`s with a `catchError`. This overlaps with `async-safety` — see that skill for the full treatment; here it is enough to know the typed `Result` is *also* dropped by this hole, so route taps through a void method.

## 3. The runZonedGuarded decision

Flutter's error surfaces are covered by two handlers installed before `runApp` — `FlutterError.onError` (build/layout/paint sync errors) and `PlatformDispatcher.instance.onError` (async + platform-channel errors). `app-startup-and-bootstrap` owns installing and ordering them; the only decision this section makes is whether to add a zone.

**Default: no `runZonedGuarded`.** The documented fix for the zone-mismatch warning is to *remove zones from the application*, and these two handlers already catch Flutter's error surfaces. Adding a zone you do not need is pure footgun: it complicates stack traces and can silence the mismatch diagnostic.

**Add `runZonedGuarded` only when a crash-reporting SDK requires it.** Sentry/Firebase Crashlytics wrap their own init inside a zone; the "use all three" advice is *crash-SDK advice*, not a general rule. If you adopt such an SDK, follow its integration exactly:

```dart
// ONLY with a crash SDK that mandates a zone.
runZonedGuarded(() {
  // SDK init here, then:
  runApp(app);
}, (error, stack) {
  crashSdk.recordError(error, stack);
});
```

Tradeoff, stated honestly: a codebase that ships **no** telemetry (privacy-first, offline-only) should install exactly the two handlers and no zone — the zone buys nothing and costs trace clarity. A codebase that ships a crash SDK installs the third catch-all because the SDK needs it. Decide once, at the composition root; do not sprinkle zones elsewhere.

## 4. Call-site shape

The intermediate sealed type lets you handle a whole failure category in one branch when every subtype resolves the same way:

```dart
Future<void> onPlace(OrderDraft d) async {
  switch (await _orders.place(d)) {
    case Ok():
      _showConfirmation();
    // Matching the intermediate sealed OrderFailure IS exhaustive; adding a new
    // subtype does not break this branch — correct when all failures resolve the
    // same way (show the error + let the user retry).
    case Err(failure: final f):
      _log.record('place failed: ${f.code}', StackTrace.current);
      _showRetry(f.code); // map code → localized message at the edge
  }
}
```

When different subtypes need different recovery, switch each one explicitly — still no `default:`.

> **CI must build, not just analyze.** `analyzer: errors: non_exhaustive_switch_statement: ignore` silences `dart analyze` while `dart compile` still fails on a non-exhaustive switch. Your pipeline must actually compile/build to keep the exhaustiveness guarantee. See `ci-pipeline-and-gates`.
