# Service interface — typed outcomes, fakes, and the Future-drop hole

Deep-dive for the shape of one side-effect boundary. The seam is: **value-typed interface → typed outcome → throwing provider → one live impl → hand-written fake.**

## Why a typed outcome, not `bool` / `throw` / `Result<Exception>`

A side-effect method reports how it went. Pick the return type deliberately:

| Return type | Why it is wrong for a boundary |
|---|---|
| `bool` | Invites ignoring; `false` carries no reason, so the feature cannot distinguish "user cancelled" from "target unavailable". |
| `throw` | Dart requires no `throws` declaration and no `catch`, so the failure gets forgotten. A thrown-and-swallowed error is the silent-failure default. |
| `Result<Exception>` | Zero exhaustiveness. `case Err(:final e)` cannot tell the compiler a *new* failure kind appeared, so adding one never forces a call site to handle it. |
| **sealed outcome** | A non-exhaustive `switch` over a sealed type is a **compile error** (`non_exhaustive_switch_statement`). Adding a variant breaks every call site until handled. |

Model failure as data:

```dart
sealed class SaveResult { const SaveResult(); }
final class Saved extends SaveResult { const Saved(); }
sealed class SaveFailure extends SaveResult {
  const SaveFailure(this.code); // a STABLE code + params, never a localized string
  final String code;
}
final class SaveRejected  extends SaveFailure { const SaveRejected(super.code); }
final class SaveTimedOut  extends SaveFailure { const SaveTimedOut(super.code); }
```

Carry on each failure whatever the feature needs to resolve it (a fallback payload, the offending value). That makes "what the UI does on failure" a **total function of the outcome** — one `switch`, no `default`.

**Never write `default:` or `case _:` over a sealed outcome.** It silently disables the exhaustiveness alarm — the whole reason the type is sealed.

**Never `assert` a platform return code.** `assert` is stripped in release, so `assert(await channel.invoke() == ok)` is green in every test and absent on the user's device — the perfect silent failure. Asserts cover *our* bugs (`Error`); sealed outcomes cover *the environment* (`Exception`).

## Honest guarantees — do not over-claim

| Mechanism | Strength |
|---|---|
| Non-exhaustive `switch` over a sealed type | **Compile error.** Real, not "just a warning". |
| A caller discarding the outcome | Not caught by the type system. Close it with `@useResult` on the method + `unused_result: error` in `analysis_options.yaml` — an *analyzer* diagnostic, only as strong as CI blocking on it. |
| A raw platform return code (e.g. a channel returning `0`) | **Nothing detects this.** Hand-written check, at the wire, with a comment at the point of temptation. |

The honest claim is: *compile error on a new variant, analyzer error on a discarded outcome, hand-written detection at the wire.* Not "silence is impossible".

## Check every return code by hand, at the wire

The live impl is thin, but every platform return value is checked explicitly — the checks read as paranoia and are the documented behaviour of the plugin. Leave the comment where the temptation to skip it lives:

```dart
final class ChannelSaveService implements SaveService {
  const ChannelSaveService(this._channel);
  final MethodChannel _channel;
  static const _ok = 1;

  @override
  Future<SaveResult> save(String value) async {
    final Object? code;
    try {
      code = await _channel.invokeMethod<int>('save', value).timeout(const Duration(seconds: 8));
    } on TimeoutException {
      return const SaveTimedOut('timeout');
    } on PlatformException catch (e) {
      return SaveRejected(e.code);
    }
    // Some plugins report failure as result.success(0) — NOT result.error — so it
    // never throws. Unchecked, that is a silent failure. Check it by hand.
    if (code != _ok) return SaveRejected('code_$code');
    return const Saved();
  }
}
```

## The arrow-callback Future-drop hole (no lint catches it)

The most idiomatic way to wire a tap is a silent bug:

```dart
// WRONG — the arrow closure "returns" the Future, so discarded_futures thinks it is
// handled; but the target type is VoidCallback, so the Future AND its error are dropped.
onTap: () => service.save(value),
```

The fix is structural, not disciplinary — a `void`-returning handler that owns the `unawaited` + `catchError`:

```dart
final class SaveController {
  SaveController(this._service, this._log);
  final SaveService _service;
  final Logger _log;

  /// Returns void ON PURPOSE. The callback never holds a Future, so there is
  /// nothing to drop — the hole is unreachable by construction. Do not "fix"
  /// this into Future<void>.
  void saveNow(String value) {
    unawaited(_run(value).catchError((Object e, StackTrace s) {
      _log.error('saveNow threw', e, s); // even a total _run can throw in teardown/log
    }));
  }

  Future<void> _run(String value) async {
    final outcome = await _service.save(value);
    switch (outcome) {
      case Saved():
        return;
      case SaveFailure(:final code):
        _log.warn('save failed: $code'); // feature layer maps code -> localized copy
    }
  }
}
```

See `async-safety` for the general no-silent-failure discipline this instantiates.

## Fakes over mocks — model the ways the world breaks

`implements` (never `extends` with `noSuchMethod`): adding a method to the interface **breaks the build** instead of failing at runtime. The risk a boundary carries is not "was it called" — it is "what happens when the target is unavailable / the code came back 0", which is **state**, which a fake models naturally.

For a boundary with many failure modes, enumerate them and loop the highest-value test over them:

```dart
enum SaveEnv { healthy, rejected, timesOut, reportedOkButNoop }

final class FakeSaveService implements SaveService {
  FakeSaveService(this.env);
  SaveEnv env;
  @override
  Future<SaveResult> save(String value) async => switch (env) {
        SaveEnv.healthy => const Saved(),
        SaveEnv.rejected => const SaveRejected('rejected'),
        SaveEnv.timesOut => const SaveTimedOut('timeout'),
        SaveEnv.reportedOkButNoop => const Saved(), // Dart-undetectable; manual device check
      };
}
```

Then write the one test that is **unsatisfiable by a silently-failing path**: loop over every *detectable* env and assert the user-visible invariant holds (e.g. `savedOrShowedError`). Every other test asserts a behaviour; this one asserts the *absence of a failure class*, so adding an env forces the UI to handle it or the build goes red. The `reportedOkButNoop` case has no Dart-side signal and stays a manual-checklist step — write the checklist step, do not fake the test.

`mocktail` is for one-off stubs only, where a full fake is overkill. Never mock the raw `MethodChannel` across a suite — you already own the interface; fake that. Keep at most one channel-contract test as an upgrade canary.

## The mutating service feeds the single write path

A service that changes durable state (a saved draft, a granted entitlement, a published mirror) is consumed by a **repository method that commits before republishing** — persist first, acknowledge second:

```dart
Future<void> confirmAndPublish(Item item) async {
  await _db.transaction(() async {
    await _db.upsert(item);          // durable first
  });
  await _widgetGateway.publish(item.toSnapshot()); // then the side effect fan-out
  // stream emits AFTER the commit — a crash mid-flow never leaves "shown but not saved"
}
```

See `error-handling-typed-results` (never-lose-data: transactions, autosave, soft-delete) and `persistence-drift` (one-transaction-per-mutation, persist-before-publish).
