# Canonical storage: exponents, units, parsing, rounding, Clock

Everything here is pure Dart — depends only on `decimal` and `clock`. No Flutter,
no `intl`, no `dart:io`. Formatting and digit normalization live outside this core.

## The ISO-4217 exponent rule

Minor-units-per-major is `10^exponent`, derived from the currency's **real**
ISO-4217 exponent — never a hardcoded `100`.

| Exponent | Example codes | minorPerMajor | `12345` minor units == |
| --- | --- | --- | --- |
| 0 | JPY, VND, KRW | 1 | 12345 |
| 2 | USD, EUR, GBP | 100 | 123.45 |
| 3 | KWD, BHD, OMR | 1000 | 12.345 |

A hardcoded `* 100` is a 100× error for a 0-exponent currency and a 10× error for
a 3-exponent one. Always route through `currency.minorPerMajor`. Persist the
exponent alongside the code on the aggregate so the amount reconciles identically
even if the device locale changes before relaunch.

### Exponent test matrix (assert exactly)

| Input string | Currency | Exponent | Expected minor units |
| --- | --- | --- | --- |
| `"1.50"` | USD | 2 | `150` |
| `"125.00"` | KWD | 3 | `125000` |
| `"125"` | JPY | 0 | `125` |
| `"12.345"` | KWD | 3 | `12345` |
| `"0.001"` | OMR | 3 | `1` |
| any | unknown code | — | typed `Failure`, never a defaulted 2-decimal parse |

## Parsing a major-unit string to exact minor units

The input must already be ASCII-normalized (digits + separators) upstream — this
core never sees localized numerals. Parse with `decimal` (no binary-float error),
scale by the exponent, round once.

```dart
Money moneyFromMajorString(String ascii, Currency c) {
  final scaled = (Decimal.parse(ascii) * Decimal.fromInt(c.minorPerMajor))
      .round(); // exact; Decimal has no binary-float error
  return Money(scaled.toBigInt().toInt(), c);
}
```

Never `Decimal(someDouble)` — that carries the binary error you are trying to
avoid. Construct `Decimal` from a `String` or from integer minor units.

## The cents-accumulator for keypad input

A numeric keypad with no fixed decimal key should accumulate digits **directly
into minor units**, sidestepping the locale decimal-separator problem entirely:

```dart
/// Each digit press shifts the accumulator and adds the digit.
/// "1","2","5","0" with a 2-exponent currency -> 1250 minor units (12.50).
int accumulateDigit(int currentMinor, int digit) => currentMinor * 10 + digit;
```

If you must parse a free-text field, apply a strict re-format-and-compare check:
`Decimal.parse` (and platform format parsers) silently ignore trailing garbage
(`"12.50xyz"` → `1250`), so reject any input whose canonical re-rendering differs
from what the user typed.

## Rounding discipline

- Use `package:decimal` for all exact division/parsing.
- Apply an explicit `RoundingMode` — default **half-even (banker's)** — **once**,
  at the parse boundary or the final-total/conversion boundary.
- **Never round intermediate sums** — it accumulates bias.
- Display rounding belongs to the formatting layer, not this core.

## Physical value objects — SI base, convert at the edge

Same discipline as money: an integer canonical field, rounding `.from<Unit>`
factories, and edge-only `to<Unit>()` getters returning `double`.

```dart
final class Distance { // canonical: whole metres
  const Distance.metres(this.metres);
  final int metres;
  factory Distance.km(num km) => Distance.metres((km * 1000).round());
  factory Distance.miles(num mi) => Distance.metres((mi * 1609.344).round());
  double toKm() => metres / 1000;
  double toMiles() => metres / 1609.344;
}

final class Volume { // canonical: whole millilitres
  const Volume.millilitres(this.ml);
  final int ml;
  factory Volume.litres(num l) => Volume.millilitres((l * 1000).round());
  factory Volume.usGallons(num g) => Volume.millilitres((g * 3785.411784).round());
  factory Volume.ukGallons(num g) => Volume.millilitres((g * 4546.09).round());
  double toLitres() => ml / 1000;
}
```

### Conversion factors (exact where an exact definition exists)

| Quantity | Display unit | To canonical | From canonical |
| --- | --- | --- | --- |
| Distance (m) | km | ×1000 | ÷1000 |
| Distance (m) | mile (intl) | ×1609.344 | ÷1609.344 |
| Volume (mL) | litre | ×1000 | ÷1000 |
| Volume (mL) | US gallon | ×3785.411784 | ÷3785.411784 |
| Volume (mL) | UK/imperial gallon | ×4546.09 | ÷4546.09 |
| Duration (min) | hour | ×60 | ÷60 |

Because volume is stored canonically, a value entered in US gallons and one
entered in UK gallons (≈20% apart) never silently corrupt each other — the
distinction survives import, export, and unit switching. Derived display metrics
(a rate, an average) are computed from canonical fields on read, never stored.

## Injected Clock — deterministic time

Any class that reads time takes a `Clock` (`package:clock`) constructor arg.
Production passes `const Clock()`; tests pass a fixed clock or drive `fake_async`.

```dart
final class ExpiryPolicy {
  const ExpiryPolicy(this._clock);
  final Clock _clock;
  bool isExpired(DateTime asOfUtc, {required int maxAgeDays}) =>
      _clock.now().difference(asOfUtc).inDays > maxAgeDays;
}

test('20-day-old snapshot within a 30-day window is not expired', () {
  final policy = ExpiryPolicy(Clock.fixed(DateTime.utc(2026, 7, 21)));
  expect(policy.isExpired(DateTime.utc(2026, 7, 1), maxAgeDays: 30), isFalse);
});
```

For elapsed-time logic (not just a fixed instant), wrap the code under test in
`fakeAsync((async) { … async.elapse(Duration(days: 20)); … })` so timers advance
without real waiting.

## A note on display-only scalings

A currency sometimes has a customary display unit that is a fixed multiple of its
canonical minor unit (a "×10 view", a grouping convention). Model it as a
**presentation flag**, not a separate `Currency`: store canonical minor units,
multiply on input and divide on display. The stored row must be byte-identical
whichever way the user entered it. Round-trip that invariant in a test.
