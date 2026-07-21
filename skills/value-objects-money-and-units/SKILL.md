---
name: value-objects-money-and-units
description: >-
  Enforces a pure-Dart value-object core that stores every quantity canonically —
  money as integer minor units keyed to each currency's real ISO-4217 exponent
  (never *100), physical amounts as SI whole units,
  timestamps as UTC — and converts only at the presentation edge; forbids
  double/num money, cross-currency arithmetic, and defaulting an unknown currency
  to two decimals; routes every division of money through one largest-remainder
  allocate() primitive so parts always sum to the whole to the exact minor unit;
  derives totals instead of storing them, links entities by stable id, and injects
  a Clock instead of DateTime.now. Use when defining or changing Money, Currency,
  or a unit value object; parsing or formatting an amount; splitting, prorating,
  discounting, tax/tip, or distributing money; adding a currency or FX rate;
  converting quantities; or fixing float-money, hardcoded-100, cross-currency,
  off-by-a-cent, or stored-total-drift bugs.
---

# Value objects: money & units

Store every quantity **once, in one canonical form, and convert only when shown or
exported**. Money is integer minor units plus a currency; physical quantities are
whole SI base units; time is UTC. This is what lets a user flip any display
preference (currency symbol, unit system, locale) without corrupting one stored
row, and lets "sum of parts == whole" be structural, not hoped-for.

This core is **pure Dart** — no `flutter/*`, no `intl`, no `dart:io`, no plugins.
Formatting and digit normalization happen upstream/downstream, not here. These
value objects live in `lib/core/`, the sanctioned pure-foundation layer (see
`project-structure-and-packages`) — never a `utils/`/`common/`/`shared/` grab-bag.

Read the reference for the task at hand:
- `references/allocate-and-splitting.md` — the largest-remainder `allocate()`
  primitive, its invariants, the two-rounding-sites trap, edge policies, verified
  test vectors, and the subtotal→tax→tip split pipeline.
- `references/canonical-storage.md` — the ISO-4217 exponent rule, the SI unit
  tables, `decimal`-based parsing, the cents-accumulator for keypad input,
  rounding discipline, and the Clock-injected dated-rate / staleness engine.
- `references/domain-model.md` — value-type modelling: relationships as id links,
  derive-don't-store, one currency per aggregate, immutable state with value
  equality.

Run `scripts/check-money-violations.sh` and `scripts/verify-core.sh` before a PR.

## Non-negotiable rules

1. **Money is `int` minor units + a `Currency` — NEVER `double`/`num`/`REAL`.**
   Binary floats cannot represent `0.01`; drift silently corrupts totals the user
   can never re-derive. No money API accepts or returns `double`.
2. **Derive minor-units-per-major from the currency's real ISO-4217 exponent —
   NEVER hardcode `* 100`, `/ 100`, or "2 decimals".** Exponent is 0 for JPY/VND,
   2 for USD/EUR, 3 for KWD/BHD/OMR. A hardcoded `100` is a 100× error for a
   0-exponent currency and a 10× error for a 3-exponent one. Route through
   `currency.minorPerMajor`.
3. **Unknown currency code is a typed failure, never a silent default-to-2.** The
   exponent table lists only shipped currencies; `Currency.tryParse` returns null
   and the caller emits a `Failure`.
4. **One currency per aggregate; cross-currency arithmetic is forbidden.** Adding
   two `Money` of different currencies is a category error — throw
   (programmer error) or convert through the FX layer first. Keep currency a
   fact of the enclosing aggregate so `Money` arithmetic never has to guard it.
5. **Route EVERY division of money through one `allocate(amount, weights)`
   primitive.** Shared items, tax proration, tip proration, discounts — all one
   rounding path, so "parts sum to the whole to the exact minor unit" is proven
   once and tested once.
6. **There are TWO rounding sites, not one: `allocate()` AND percent→minor-units.**
   Round a percentage to integer minor units **once** before feeding `allocate()`.
   A naive `double` percent is a classic off-by-a-cent bug that `allocate`
   coverage will not catch.
7. **Never sum independently-rounded parts to get a total.** Always `allocate()` a
   known integer total and let the parts absorb the residual.
8. **Derive totals; never store them.** A denormalized stored total is the classic
   drift bug. Totals are computed from items + weights on read.
9. **Model relationships as stable-`id` links, not embedded copies.** Give every
   entity an explicit `final id` (e.g. a UUID). Editing a price then leaves
   assignments intact and deleting a participant just drops them from link sets.
10. **Store canonically, convert at the edge.** Physical quantities are whole SI
    base units (`int` metres / millilitres / minutes); time is a UTC `DateTime`.
    `.from<DisplayUnit>` factories round *into* canonical; `to<DisplayUnit>()`
    getters return a `double` used only at the presentation edge.
11. **Normalize digits/separators to ASCII BEFORE input reaches this core.** Never
    call `int.parse`/`double.parse`/`Decimal.parse` on raw localized input — it
    throws on Eastern-Arabic numerals. Fold upstream (see `i18n-rtl-l10n`).
12. **Parse with `decimal`; round ONCE with an explicit mode at the boundary.**
    Use `package:decimal` for exact division/parsing, apply an explicit
    `RoundingMode` (default half-even/banker's) once at the parse or final-total
    boundary — never on intermediate sums (accumulates bias).
13. **Inject `package:clock`'s `Clock`; NEVER call `DateTime.now()`, never roll a
    bespoke `ClockService`.** Every time-reading class in this pure core takes a
    `Clock` constructor arg; Riverpod/feature code injects the *same* `Clock`
    through a `clockProvider` (see `service-boundary-and-native`) so the two
    vocabularies compose. Fixed clocks / `fake_async` then make time-dependent
    logic deterministic in tests.
14. **The core stays Flutter-free and IO-free.** Deps are only `decimal` and
    `clock`. Formatting lives in the presentation layer; storage in the data layer.

## Canonical storage

Widgets and repositories exchange **value objects**, never raw `int`s or strings.

| Quantity | Canonical storage | Type | Never store |
| --- | --- | --- | --- |
| Money | integer **minor units** + `Currency` | `int` | double, formatted string |
| Distance | whole **metres** | `int` | km, miles |
| Volume | whole **millilitres** | `int` | litres, gallons |
| Duration | whole **minutes** (or `Duration`) | `int` | hours as double |
| Timestamp | UTC **ISO-8601 instant** | `DateTime` (UTC) | local time |

```dart
/// ISO-4217 minor-unit exponents. Explicit table — NEVER default to 2.
enum Currency {
  jpy('JPY', 0), vnd('VND', 0),
  usd('USD', 2), eur('EUR', 2), gbp('GBP', 2),
  kwd('KWD', 3), bhd('BHD', 3), omr('OMR', 3);

  const Currency(this.code, this.exponent);
  final String code;
  final int exponent;

  /// 10^exponent — minor units per major unit. The ONLY scaling source.
  int get minorPerMajor => switch (exponent) {
        0 => 1,
        2 => 100,
        3 => 1000,
        _ => throw StateError('unsupported exponent $exponent for $code'),
      };

  static Currency? tryParse(String code) {
    // Plain loop, not `firstOrNull` (a package:collection extension) — keeps the
    // core dependency-free beyond `decimal`.
    for (final c in Currency.values) {
      if (c.code == code) return c;
    }
    return null;
  }
}

/// Money is (integer minor units) + (currency). No floats, ever.
final class Money implements Comparable<Money> {
  const Money(this.minorUnits, this.currency);
  final int minorUnits; // e.g. 12345 with KWD == 12.345 KWD
  final Currency currency;

  Money operator +(Money o) => currency == o.currency
      ? Money(minorUnits + o.minorUnits, currency)
      : throw ArgumentError('currency mismatch: $currency vs ${o.currency}');

  @override
  int compareTo(Money o) {
    assert(currency == o.currency, 'compare across currencies is a bug');
    return minorUnits.compareTo(o.minorUnits);
  }

  @override
  bool operator ==(Object o) =>
      o is Money && o.minorUnits == minorUnits && o.currency == currency;
  @override
  int get hashCode => Object.hash(minorUnits, currency);
}
```

Physical value objects follow the identical shape — an integer canonical field,
rounding `.from<Unit>` factories, and edge-only `to<Unit>()` getters. See
`references/canonical-storage.md` and `examples/money.dart`.

## The one division path: `allocate()`

Every time money is split, it goes through this integer largest-remainder
(Hamilton) primitive. Never divide money any other way.

```dart
/// Splits [amount] minor units across [weights], guaranteeing the parts sum
/// EXACTLY to [amount]. Deterministic ascending-index tie-break; residual < n.
/// Negative amount mirrors and negates (discounts/refunds); zero weight-sum
/// falls back to equal weights; empty weights returns [] — money math must
/// never throw into the UI.
List<int> allocate(int amount, List<int> weights) {
  final n = weights.length;
  if (n == 0) return const [];
  if (amount < 0) return allocate(-amount, weights).map((s) => -s).toList();

  final sanitized = [for (final w in weights) w < 0 ? 0 : w];
  final weightSum = sanitized.fold(0, (a, b) => a + b);
  final w = weightSum == 0 ? List.filled(n, 1) : sanitized;
  final total = weightSum == 0 ? n : weightSum;

  final shares = List<int>.filled(n, 0);
  final remainders = <({int remainder, int index})>[];
  var distributed = 0;
  for (var i = 0; i < n; i++) {
    final product = amount * w[i]; // multiply FIRST, then ~/ and % — no float
    final floorShare = product ~/ total;
    shares[i] = floorShare;
    distributed += floorShare;
    remainders.add((remainder: product % total, index: i));
  }
  var leftover = amount - distributed; // always in 0 ..< n
  remainders.sort((a, b) => a.remainder != b.remainder
      ? b.remainder.compareTo(a.remainder)
      : a.index.compareTo(b.index));
  for (var k = 0; leftover > 0; k++, leftover--) {
    shares[remainders[k].index] += 1;
  }
  assert(shares.fold(0, (a, b) => a + b) == amount, 'allocate must be exact');
  return shares;
}
```

Verified vectors (assert these in a test):
`allocate(1001,[1,1,1]) == [334,334,333]` ·
`allocate(660,[1584,4033,1933]) == [138,353,169]` ·
`allocate(1510,[1584,4033,1933]) == [317,807,386]`.

The split pipeline layers `allocate()` in passes — item subtotals, then
`allocate(taxMinor, subtotals)`, then `allocate(tipMinor, subtotals)` — so every
whole-bill figure is distributed and the per-participant finals sum to the grand
total exactly. Full pipeline, edge policies, and the percent→minor-units rounding
site are in `references/allocate-and-splitting.md` and `examples/allocate.dart`.

## Parsing input to exact minor units

Input must already be ASCII-normalized upstream. Parse with `decimal` (no binary
error), scale by the currency's exponent, round once.

```dart
/// Caller MUST have normalized digits + separators to ASCII first.
Money moneyFromMajorString(String ascii, Currency c) {
  final scaled = (Decimal.parse(ascii) * Decimal.fromInt(c.minorPerMajor))
      .round(); // exact; Decimal has no binary-float error
  return Money(scaled.toBigInt().toInt(), c);
}
```

For a numeric keypad with no fixed decimal key, accumulate digits into minor
units directly and never touch a locale decimal separator — see
`references/canonical-storage.md`.

## Derive, don't store; inject a Clock

Totals are computed on read from items + weights; a stored total is a drift bug.
Any time-dependent value object (a dated rate, a staleness band, an expiry) takes
an injected `Clock` so tests are deterministic.

```dart
final class RateSnapshot {
  const RateSnapshot(this._clock);
  final Clock _clock;
  int ageDays(DateTime asOfUtc) => _clock.now().difference(asOfUtc).inDays;
}
// prod: RateSnapshot(const Clock());  test: RateSnapshot(Clock.fixed(fixedUtc));
```

## Anti-patterns

- **`double amount` / `num price` fields.** Cannot represent `0.01`; corrupts
  totals irreversibly. Use `int` minor units.
- **`amount * 100` / `cents / 100`.** Wrong for every non-2-exponent currency.
  Route through `currency.minorPerMajor`.
- **Defaulting an unknown currency to 2 decimals.** Silently mis-scales. Return a
  typed failure.
- **Adding `Money` across currencies, or storing a currency per line item when the
  whole aggregate is single-currency.** Convert at the FX boundary; keep currency
  at the aggregate level.
- **Summing independently-rounded shares to produce a total.** Rounds twice and
  drifts. `allocate()` a known integer total instead.
- **Recomputing tax/tip from a percentage inside the allocation loop.** Round the
  percent to integer minor units once, then `allocate()`.
- **Storing a denormalized `total` on the entity.** Derive it.
- **`DateTime.now()`, or a hand-rolled `ClockService`/`SystemClock`/`FakeClock`,
  inside the pure core.** Untestable / non-composable time. Inject
  `package:clock`'s `Clock`.
- **`Decimal(someDouble)` or `int.parse` on raw localized input.** Binary error /
  throws on Eastern digits. Parse `Decimal` from a `String`; normalize first.
- **Rounding intermediate sums.** Accumulates bias. Round once at the boundary.

## Definition of done

- [ ] Every money field is `int` minor units + a `Currency`; no `double`/`num`.
- [ ] All scaling goes through `currency.minorPerMajor`; no literal `100`.
- [ ] Unknown currency returns a typed failure, never a defaulted parse.
- [ ] No cross-currency arithmetic; currency lives at the aggregate level.
- [ ] Every money split calls `allocate()`; conservation asserted and tested with
      the verified vectors.
- [ ] Percentages round to integer minor units once, before `allocate()`.
- [ ] No stored totals; totals derive on read.
- [ ] Entities carry an explicit stable `id`; relationships are id links.
- [ ] Physical quantities stored as SI `int`s; converted only at the edge.
- [ ] Time-reading classes take an injected `Clock`; no `DateTime.now()` in core.
- [ ] Core imports only `decimal` and `clock`; no Flutter/intl/dart:io.
- [ ] `scripts/check-money-violations.sh` and `scripts/verify-core.sh` pass.

## Related skills

- See `project-structure-and-packages` for where this pure core lives (`lib/core/`,
  the sanctioned foundation layer) within the feature-first app layout.
- See `service-boundary-and-native` for injecting this `Clock` into Riverpod
  code via `clockProvider` (the same `package:clock` seam, provider-wired).
- See `error-handling-typed-results` for the sealed `Result<T, F extends Failure>`
  spine that parsing and FX return instead of throwing.
- See `i18n-rtl-l10n` for ASCII digit/separator normalization and currency
  formatting at the presentation edge (kept out of this pure core).
- See `dart3-idioms-and-coding-standards` for immutable value types, sealed types,
  and total non-throwing domain functions.
- See `persistence-drift` for storing minor units + ISO code (never a REAL) and
  mapping rows to these value objects.
- See `testing-strategy` for the clock-injected, table-driven unit tests these
  pure functions demand.

## References

- ISO 4217 currency exponents — https://en.wikipedia.org/wiki/ISO_4217
- `package:decimal` — https://pub.dev/packages/decimal
- `package:clock` — https://pub.dev/packages/clock
- `fake_async` — https://pub.dev/packages/fake_async
- Largest-remainder (Hamilton) method — https://en.wikipedia.org/wiki/Largest_remainder_method
- Dart records & patterns — https://dart.dev/language/records
