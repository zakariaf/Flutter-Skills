# Fakes, properties, and absence-of-a-failure-class tests

## Fakes over mocks for code you own

Write a plain `class FakeX implements X` with **no `noSuchMethod` superclass** (do not
extend `Mock` or `Fake`). In priority order:

| Why | Detail |
|---|---|
| Interface drift breaks the **build** | Bare `implements` means adding a method to `X` is a compile error, not a runtime surprise in one forgotten test. |
| The risk is **state**, not call-order | The interesting question is rarely "was `save()` called". It is "what happens when the store is empty / the write fails". A fake models that as a field; a mock needs `when` plus side-effect gymnastics. |
| The fake **is** the contract's documentation | Whoever inherits the repo reads the fake to learn every way the collaborator can behave. |

Do not justify a fake by claiming mocks "silently absorb" interface changes — a
reviewer will push back, correctly. `mocktail` throws a `TypeError` on an un-stubbed
`Future`-returning method. Reserve `mocktail` for genuinely **external** dependencies
(a plugin wrapper, a network client) where writing a fake is more code than value; use
bare-`implements` fakes for interfaces this repo owns. Never `mockito`/`@GenerateMocks`
— it adds codegen with no null-safety advantage over mocktail.

### Model the world as an enum, not booleans

When a collaborator has several distinct failure environments, drive the fake from a
sealed set so each is a first-class, named case and a new one is a compile error.

```dart
enum StoreEnv {
  healthy,
  empty,
  writeRejected,
  readTimedOut,

  /// A failure no code path can detect from Dart — exists only to be excluded.
  corruptedButReportsOk;

  /// The environments the app can actually detect and must handle.
  static Iterable<StoreEnv> get detectable =>
      values.where((e) => e != StoreEnv.corruptedButReportsOk);
}

class FakeStore implements Store {
  FakeStore(this.env);
  final StoreEnv env;
  final saved = <Item>[]; // a spy: assert on WHAT was saved, not just that save ran

  @override
  Future<Result<void, StoreFailure>> save(Item item) async {
    switch (env) {                 // NO `default:` — a new env is a compile error
      case StoreEnv.healthy:
      case StoreEnv.empty:
        saved.add(item);
        return const Ok(null);
      case StoreEnv.writeRejected:
        return const Err(StoreFailure.writeRejected());
      case StoreEnv.readTimedOut:
        return const Err(StoreFailure.timedOut());
      case StoreEnv.corruptedButReportsOk:
        saved.add(item);           // believes it saved; it did not
        return const Ok(null);
    }
  }
}
```

The `corruptedButReportsOk` value exists to be **excluded**, and the exclusion is the
honest part — it is the single line that justifies a manual pass. Keep its doc comment
intact.

## `registerFallbackValue` for every custom `any()` type

mocktail cannot see a missing fallback at compile time; it throws at runtime. Register
every custom type that crosses `any()`/`captureAny()` in `setUpAll`.

```dart
setUpAll(() {
  registerFallbackValue(const Item.fallback());
  registerFallbackValue(DateTime.utc(2026));
});
```

## Properties over examples, with an independent oracle

A universal claim ("parts always sum to the whole", "decode undoes encode", "the
filter never passes an unsafe value") is a property, not one example. Two ways to write
it, both in twenty lines of `package:test`:

1. **Seeded fuzz loop.** `for (var seed = 0; seed < N; seed++)` over a `Random(seed)`,
   asserting the invariant and echoing the generated input in `reason:`. The printed
   input **is** the minimal repro a shrinking library would have produced. Prefer this
   to adding a property-testing dependency for the common case — one less dependency to
   keep fresh.
2. **Round-trip.** `expect(decode(encode(x)), equals(x))` over the fuzzed space, plus
   fixed **rounding goldens** at the half-way and exponent boundaries (`==` on integers,
   `closeTo(_, 1e-9)` on any calibrated double).

The oracle must be **independent** of the function under test. If the property is "par
== optimum", compute the optimum with a separate exhaustive minimiser — never call the
production implementation on both sides, which asserts only that a function equals itself.

## Assert the absence of a failure class

The highest-value test is one **unsatisfiable by a code path that fails silently**.
Parameterize over every *detectable* failure environment and assert that the outcome is
never the forbidden one — for a UI that must never go silent, `spoke OR showed`, never a
per-variant special case.

```dart
for (final env in StoreEnv.detectable) {
  test('$env: an add always reaches the store OR surfaces a visible failure', () async {
    final store = FakeStore(env);
    final result = await AddItemUseCase(store).run(_anItem);
    final persisted = store.saved.isNotEmpty;
    final surfaced = result is Err; // a typed failure the UI can render
    expect(persisted || surfaced, isTrue,
        reason: 'SILENT LOSS under $env: neither stored nor surfaced.');
  });
}
```

Rules for maintaining it:
- Iterate `.detectable`, never `.values` — the undetectable env would fail for a reason
  no code change can fix, and a permanently-red test gets deleted.
- Adding a value to the enum is how a newly-imagined failure becomes an **obligation**
  instead of a backlog note: add the value first, let the build go red.
- Make the failure a typed `Result`/`Failure` (see `error-handling-typed-results`) so
  `surfaced` is a total function of the outcome, not a per-variant check.

## The acceptance gate and the runtime tripwire

Keep exactly one realistic end-to-end scenario asserted to the exact expected result,
plus the conservation invariant that the parts sum to the whole. It is the test that
proves the pieces compose, where unit tests each prove a piece in isolation.

Back the primitive with a runtime `assert` — it costs nothing in release (asserts are
stripped) and catches the violation at the instant it happens, in every test that
exercises the path:

```dart
List<int> allocate({required int amountMinor, required List<int> weights}) {
  // ... largest-remainder distribution ...
  assert(parts.fold(0, (a, b) => a + b) == amountMinor,
      'allocate lost or created value: $parts != $amountMinor');
  return parts;
}
```

## Freeze fixtures

When snapshotting CSV/JSON fixtures, freeze the clock, locale, and numeral system.
Never commit a fixture containing a live timestamp — it flakes on the next run.
