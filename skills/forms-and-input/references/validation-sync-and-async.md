# Validation: sync and async

Two validation channels, two homes. Get this split right and forms stay fast, testable, and localized.

## Channel 1 — synchronous `validator` (shape checks)

`TextFormField.validator` has type `FormFieldValidator<String>` = `String? Function(String?)`. It is:

- **Synchronous.** Flutter calls it during `FormState.validate()`, inline in the build/layout path. It cannot `await`.
- **Total.** Handle `null` and empty; return `null` for valid, a message otherwise.
- **Localized.** Return `AppLocalizations.of(context).<key>`, never a literal.
- **Pure.** No side effects, no I/O, no reading mutable app state. Same input → same result.

Use it for shape: required, length bounds, format (regex), range. These are instant and deterministic.

```dart
String? validateEmail(String? value, AppLocalizations l10n) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return l10n.fieldRequired;
  // Structural format check — a bound, not a design value.
  final looksLikeEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text);
  return looksLikeEmail ? null : l10n.emailInvalid;
}
```

Compose multiple rules by returning the first failure. Keep each validator short (D9: methods ≤30 lines) and testable as a plain pure function — pass `l10n` in so the function has no `BuildContext` dependency and unit-tests without a widget.

### Why async does NOT belong here

`validator: (v) async => ...` returns a `Future<String?>`, but the parameter type is `String? Function(String?)`. A `Future` is non-null, so if the analyzer even accepts it via an `async` closure mismatch, the returned future is truthy and the field is treated as **always valid**. Worse, you would issue a network call synchronously on every layout pass. Async validation is a different concern with different timing (debounce, cancellation, loading UI) and a different owner (a Notifier).

## `AutovalidateMode`

Set on `Form` (applies to all fields) or per `TextFormField`.

| Mode | Behavior | Use when |
| --- | --- | --- |
| `disabled` | Only validates on explicit `validate()` (submit) | Very short forms; per-keystroke feedback is noise |
| `onUserInteraction` | Silent until first interaction, then live per field | **Default** for most forms |
| `always` | Validates every build from first frame | Almost never — shouts before typing |

`onUserInteraction` is the humane default: a field stays quiet until the user has touched it, then gives live feedback. Submit still calls `_formKey.currentState!.validate()` to catch untouched required fields.

## Channel 2 — asynchronous validation (availability / uniqueness)

Anything that hits a repository, service, or the network: "is this account name taken", "does this order id exist". This is I/O and belongs in a Riverpod `Notifier`/`AsyncNotifier`.

### The pattern

1. Field's `onChanged` calls a notifier method with the new text.
2. The notifier **debounces** with a `dart:async` `Timer` over a fixed duration, cancelling any pending timer. The `Timer` is made deterministic in tests by `fakeAsync` (advance time), not by the clock seam. Any *timestamp* the check records comes from `ref.read(clockProvider).now()` — never `DateTime.now()`; the Clock seam is owned by `service-boundary-and-native`.
3. After the debounce settles, it runs the async check through a repository (single read path — see `persistence-drift`/`flutter-architecture`).
4. It exposes the outcome as `AsyncValue<CheckResult>` (or a sealed status).
5. The field reads that state and maps it to `InputDecoration.errorText`.

### Rules for the async notifier

- **Debounce, don't spam.** Cancel the previous `Timer` on each keystroke; only the last keystroke after the quiet window fires the check.
- **Cancel on dispose.** Cancel the timer and any subscription in the notifier's dispose (`ref.onDispose`). See `async-safety`.
- **Guard staleness.** If the input changed while a check was in flight, ignore the stale result (compare against the current query, or rely on `AsyncNotifier` state replacement).
- **Loading is not an error.** While the check runs, show a progress affordance, not an error. `errorText` stays `null` until a definitive "taken"/"failed".
- **Failures are typed.** A network failure surfaces as `AsyncError` mapped to a localized "couldn't check" message — do not treat "check failed" as "name taken." See `error-handling-typed-results`.

### Submit must re-check

Debounced async validity can be stale at submit time (user hit submit inside the debounce window). On submit: (a) run sync `validate()`, and (b) confirm the async status is a settled "available" — if it is loading or unknown, either await a final check or block submit. The server remains the source of truth and the write path returns its own typed failure on conflict.

```dart
Future<void> submit() async {
  if (!(formKey.currentState?.validate() ?? false)) return;
  final status = ref.read(nameAvailabilityNotifierProvider);
  if (status is! AsyncData || status.value != NameCheck.available) return; // not settled-good
  await ref.read(accountFormNotifierProvider.notifier).save(...);
}
```

See `examples/async_field_notifier.dart` for a complete debounced notifier.

## Testing

- Sync validators: pure-function unit tests, no widget — pass `l10n` (or a test double) and assert the returned key/`null`.
- Async notifier: `ProviderContainer` with a fake repository; run under `fakeAsync` and advance time to fire the debounce `Timer`; assert state transitions idle → loading → data/error. If the check records timestamps, override `clockProvider` with a fixed `Clock` too. See `testing-strategy`.
