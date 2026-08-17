---
name: testing-strategy
description: >-
  Enforces test doctrine where shape follows code not the pyramid: pushes logic into
  Flutter-free packages tested with pure package:test and an injected Clock; asserts
  invariants with seeded fuzz tests against an independent oracle plus round-trip and
  rounding goldens; prefers bare-implements fakes over mocktail for code you own;
  tests the data layer against a real NativeDatabase.memory Drift engine, never a
  mocked DAO; drives Notifiers headlessly with ProviderContainer overrides; guards one
  end-to-end acceptance gate and a runtime invariant tripwire; floors coverage on
  unrecoverable-bug files not a global percentage; and fixes the coverage-lies-upward
  gap. Use when writing tests under test/ or integration_test/, choosing unit vs
  widget vs integration, adding a fuzz or round-trip property, wiring a fake or
  ProviderContainer test, gating coverage, or triaging a flaky-suite failure.
---

# Testing Strategy

Tests are the only correctness instrument you control at build time: shape the suite
to the code, not to a decades-old ratio, and make each test assert behaviour a build
either passes or fails. Applies to every test under `test/` and `integration_test/`.

Read the reference for the task at hand:
- `references/test-layers.md` — per-layer harness, imports, teardown, edge tables (pure core, in-memory Drift, headless Notifier, integration).
- `references/property-and-fakes.md` — fakes-over-mocks, enum-driven fake state, seeded fuzz, independent oracles, absence-of-a-failure-class tests.
- `references/coverage-and-budget.md` — file-level floors, the coverage-lies-upward fix, the suite-time budget, and the manual-pass handoff.

Run `scripts/check_test_hygiene.sh` and `scripts/run_tests.sh` before a PR.

Golden, RTL, and a11y widget mechanics live in `widget-golden-and-a11y-testing`; this
skill governs everything below the pixel.

## Non-negotiable rules

1. **Shape the suite to the code, not the pyramid.** The 70/20/10 numbers trace to a
   2011 test-*size* heuristic (its author said they were "pulled out of a hat") and
   never described Flutter's unit/widget/integration taxonomy. Test at the **cheapest
   tier that can assert the behaviour**: anything expressible as `f(input) -> output`
   is a unit or property test, never a `pumpWidget`. Driving pure logic through the
   widget tree is slower, flakier, and hides which layer broke.
2. **Put business rules in a Flutter-free package and inject a `Clock`.** Domain math
   lives in pure Dart with zero Flutter/plugin/IO imports, tested with `package:test`
   (not `flutter_test`). The one time type is `package:clock`'s `Clock` — NEVER
   `DateTime.now()`, never a bespoke `ClockService`. Pure `core` reads the ambient
   `clock.now()`, pinned in tests with `withClock(Clock.fixed(t), …)`; Riverpod/feature
   code reads the injected `clockProvider`, overridden with
   `clockProvider.overrideWithValue(Clock.fixed(t))` (seam owned by
   `value-objects-money-and-units`). The ban is structural: a pure package declares no
   Flutter SDK constraint.
3. **Assert invariants, not just examples.** Every conversion has a **round-trip**
   test (`decode(encode(x)) == x`) and **rounding goldens** at half-way/boundary
   values; every universal claim is a **seeded fuzz** loop (`for (var seed = 0; seed
   < N; seed++)`) or property test, checked against an **independent oracle** — never
   the production function under test. Print the generated input in `reason:` so a
   failure is its own minimal repro. `==` on integers only; `closeTo(x, 1e-9)` on
   doubles.
4. **Test the data layer against a real in-memory engine.** Use
   `NativeDatabase.memory()`, never a mocked DAO — a mocked DAO proves nothing about
   SQL, constraints, indexes, or migrations. Mock repositories only *above* the data
   layer. `addTearDown(db.close)` and close streams synchronously so reactive
   `.watch()` streams do not leak "Timer still pending".
5. **Prefer bare-`implements` fakes over mocks for code you own.** A `class FakeX
   implements X` (no `noSuchMethod` superclass) makes an interface change a **compile
   error**, models the risk (state, not call-order) as a field, and doubles as the
   contract's documentation. Reserve `mocktail` for genuinely external dependencies;
   never `mockito`/`@GenerateMocks` (codegen, no null-safety win).
6. **`registerFallbackValue` for every custom type passed to `any()`/`captureAny()`**
   in `setUpAll`. mocktail throws at *runtime*, not compile time, on a missing
   fallback — this is the single most common mocktail failure.
7. **Drive Notifiers headlessly with `ProviderContainer`.** Override provider
   dependencies via `overrideWith`; never pump a widget to test state. Assert on the
   exposed `AsyncValue`/state, drive actions through `.notifier`, and dispose the
   container in teardown.
8. **Guard one end-to-end acceptance gate.** A single realistic scenario asserted to
   the exact expected result, plus the **conservation invariant** (parts sum to the
   whole). It is the test that proves the pieces compose. Back it with a **runtime
   assert tripwire** inside the primitive itself (`assert(sum(result) == total)`) —
   free in release, catches the bug the moment it happens.
9. **Hold an unrecoverable-bug-files floor by diff-review, not a coverage gate.**
   There is no automated percentage gate — coverage is a published report
   (`ci-pipeline-and-gates` owns that). Instead hold a 100% floor on the handful of
   **files** (migrations, the money/allocate primitive, the parser with wire-format
   traps) where a gap is silent data loss — enforced by **reading the diff**, not by
   counting lines. A directory or global percentage gate rewards vanity tests and
   exclusion churn. First **fix the coverage-lies-upward gap**: `flutter test
   --coverage` omits files no test imports, so the number overstates safety.
10. **Never `pumpAndSettle()` on an indefinite animation** (splash, shimmer, spinner)
    — it hangs on a 10-minute timeout. Use timed `pump(Duration)` with `fakeAsync`.
11. **Keep the suite fast, and hand structurally-untestable paths to a manual pass.**
    A suite that costs minutes gets skipped, and a skipped suite is a distrusted one.
    Anything an emulator cannot reproduce (real audio, OEM device diversity, native
    surfaces without a Flutter engine) is enumerated in a **named manual pre-release
    pass**, not faked green — a green test that proves nothing is worse than an
    admitted gap.

## Tier the test to the code (`package:test` vs `flutter_test`)

Pure logic runs under `dart test` with no widget binding; only UI and plugin-wrapper
tests need `flutter_test`.

```dart
// test/domain/money_test.dart — pure Dart, `dart test`, no flutter_test import.
import 'package:test/test.dart';
import 'package:app_core/app_core.dart';

void main() {
  // Round-trip: encoding is lossless across the ISO-4217 exponent range.
  test('minor-units round-trip for exponents 0, 2, 3', () {
    for (final currency in [Currency.jpy, Currency.usd, Currency.kwd]) {
      final money = Money(amountMinor: 12345, currency: currency);
      expect(Money.parse(money.format(), currency), equals(money));
    }
  });
}
```

## Inject the clock; pin it in tests

Production reads `clock.now()`; tests freeze it so time-dependent logic is
deterministic — no wall clock, no flake.

```dart
// Production: a Reminder is due when its target time has passed.
bool isDue(Reminder r) => !clock.now().isBefore(r.dueAt);

// test/domain/reminder_test.dart
test('reminder is due exactly at its due instant', () {
  final due = DateTime.utc(2026, 1, 1, 9);
  withClock(Clock.fixed(due), () {
    expect(isDue(Reminder(dueAt: due)), isTrue);
  });
});
```

For code behind a provider, inject `clockProvider` and freeze it in a container test
with `clockProvider.overrideWithValue(Clock.fixed(due))` — same `Clock`, same fixed
instant, driven through Riverpod instead of the ambient zone.

## Seeded fuzz against an independent oracle

Twenty lines of `package:test` give you what a stale property package would, with the
generated input as the built-in minimal repro. The oracle must be independent of the
function under test.

```dart
// test/domain/allocate_test.dart
test('allocate: parts always sum to the input (fuzz)', () {
  final rng = Random(0xC0FFEE);
  for (var seed = 0; seed < 500; seed++) {
    final n = rng.nextInt(20) + 1;
    final total = rng.nextInt(100000);
    final weights = List.generate(n, (_) => rng.nextInt(500));
    final parts = allocate(amountMinor: total, weights: weights);
    expect(parts.fold(0, (a, b) => a + b), equals(total),
        reason: 'seed=$seed total=$total weights=$weights'); // its own repro
  }
});
```

## Real in-memory Drift, never a mocked DAO

```dart
// test/data/order_dao_test.dart
void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close()); // reactive .watch() streams must not leak timers

  test('CHECK constraint rejects a negative quantity', () {
    expect(
      () => db.orderDao.insertItem(const OrderItem(quantity: -1)),
      throwsA(isA<SqliteException>()), // proves the real constraint, not a stub
    );
  });
}
```

## Headless Notifier tests with `ProviderContainer`

```dart
// test/features/cart/cart_notifier_test.dart
void main() {
  test('addItem publishes the new total', () async {
    final container = ProviderContainer(
      overrides: [orderRepositoryProvider.overrideWith((ref) => _FakeOrderRepo())],
    );
    addTearDown(container.dispose);

    await container.read(cartNotifierProvider.future);
    await container.read(cartNotifierProvider.notifier).addItem(_anItem);

    final state = container.read(cartNotifierProvider);
    expect(state, isA<AsyncData<CartState>>());
    expect(state.requireValue.totalMinor, 1299);
  });
}
```

`ProviderContainer.test()` (Riverpod 3.x) auto-disposes and is the preferred form when
available; otherwise `addTearDown(container.dispose)`.

## Drive timers with `fakeAsync`

```dart
test('debounced search fires once after the window', () {
  fakeAsync((async) {
    final calls = <String>[];
    final debouncer = Debouncer(const Duration(milliseconds: 300));
    debouncer.run(() => calls.add('a'));
    async.elapse(const Duration(milliseconds: 299));
    expect(calls, isEmpty);
    async.elapse(const Duration(milliseconds: 1));
    expect(calls, ['a']);
  });
});
```

## Anti-patterns

- **Inverting the pyramid** — driving pure `f(input) -> output` logic through
  `pumpWidget`. Slower, flakier, hides the broken layer.
- **`DateTime.now()` / ambient `Random()` reachable from domain logic.** Makes
  "identical inputs -> identical output" untestable; inject `Clock` and a seed.
- **`flutter_test` imported into a pure package.** Breaks the structural boundary and
  slows the fastest tier; the package should declare no Flutter SDK constraint.
- **A mocked DAO standing in for the database.** Proves nothing about SQL,
  constraints, indexes, or migrations. Use `NativeDatabase.memory()`.
- **`==` on doubles**, or covering a universal claim with one lucky example instead of
  a fuzz loop over an independent oracle.
- **A fake that lies about its contract** (a dependency that can never fail) — the
  test then reflects a happy-path stub, not real behaviour. Fakes must expose failure.
- **Missing `registerFallbackValue`** for a custom `any()` argument — a runtime throw
  no compiler catches.
- **`pumpAndSettle()` on an indefinite indicator** — hangs on the 10-minute timeout.
- **A global/directory coverage-percentage gate** — rewards vanity tests, and the raw
  number lies upward. Floor the unrecoverable files; publish the rest.
- **A green test over a structurally-untestable path** (real audio, native tile,
  device diversity) — worse than an admitted gap, because it stops anyone checking by
  hand.
- **A test with no meaningful `expect`**, shared mutable state across tests, or a vague
  name like `test('works')`.

## Definition of done

- [ ] Each test lives at the cheapest tier that can assert it; pure logic under
      `package:test`, widget/integration only where the UI/plugin seam is the point.
- [ ] Domain logic reads `clock.now()`, never `DateTime.now()`; tests pin it with
      `withClock`.
- [ ] Every conversion has a round-trip test and boundary rounding goldens; every
      universal claim is a seeded fuzz/property test against an independent oracle,
      with the input echoed in `reason:`.
- [ ] The data layer is tested against `NativeDatabase.memory()`, not a mocked DAO;
      `db.close()` in teardown.
- [ ] Owned collaborators are bare-`implements` fakes; `mocktail` is reserved for
      external deps with `registerFallbackValue` for every custom `any()` type.
- [ ] Notifiers are tested through `ProviderContainer` overrides, disposed in
      teardown; no widget pumped to test state.
- [ ] One acceptance gate asserts a realistic scenario exactly and the conservation
      invariant; the primitive carries a runtime `assert` tripwire.
- [ ] Coverage floors sit on the unrecoverable-bug **files**; the coverage-lies-upward
      gap is fixed (untested files included); generated files stripped.
- [ ] No `pumpAndSettle()` on an indefinite animation; timers driven by `fakeAsync`.
- [ ] The suite stays within its time budget; every structurally-untestable path is
      named in the manual pre-release pass, not faked green.

## Related skills

- See `widget-golden-and-a11y-testing` for golden lanes, the overflow/RTL matrix, and honest a11y limits.
- See `value-objects-money-and-units` for the `allocate()` primitive and `Clock` injection this skill tests.
- See `persistence-drift` for the DAO/value-object seam the in-memory tests exercise.
- See `run-migration` for the forward-only migration ritual whose from→to paths get the 100% floor.
- See `error-handling-typed-results` for the sealed `Result`/`Failure` the exhaustive-switch tests assert on.
- See `async-safety` for the dropped-Future holes the silence-review checklist targets.
- See `service-boundary-and-native` for the injectable ports the fakes stand in for.
- See `ci-pipeline-and-gates` for how these lanes and greps are wired as gates.
- See `seeded-determinism-and-golden-vectors` for pinning a seeded generator with a frozen fingerprint table when output must reproduce across devices and releases.

## References

- Flutter testing overview — https://docs.flutter.dev/testing/overview
- Riverpod testing — https://riverpod.dev/docs/essentials/testing
- Drift testing (NativeDatabase.memory) — https://drift.simonbinder.eu/docs/testing/
- `package:clock` — https://pub.dev/packages/clock
- `package:fake_async` — https://pub.dev/packages/fake_async
- `package:mocktail` — https://pub.dev/packages/mocktail
