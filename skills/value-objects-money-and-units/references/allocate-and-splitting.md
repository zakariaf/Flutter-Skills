# allocate() and the split pipeline

This is the correctness core. Get it exactly right; everything else is decoration.

## Why one primitive

Represent every amount as `int` minor units. Route **every** division of money —
shared items, tax, tip, discounts, proration — through the single
`allocate(amount, weights)` function. One rounding path means "sum of parts ==
whole to the exact minor unit" is proven once and tested once, for any input.

## The primitive (integer largest-remainder / Hamilton)

```dart
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

### Why each detail matters

| Detail | Reason |
| --- | --- |
| `amount * w[i]` before `~/`/`%` | Multiply first keeps everything integer — no float ever enters. |
| floor then distribute leftover | Guarantees each floor share ≤ exact share; leftover is always `0 ..< n`. |
| sort by remainder desc, index asc | Deterministic tie-break; same input → same output, reproducible in tests. |
| `amount < 0` mirror + negate | Discounts/refunds prorate with the same conservation guarantee. |
| zero weight-sum → equal weights | Everyone-comped / 100%-off still splits residual evenly, never divides by zero. |
| empty weights → `[]` | Money math must never trap the UI. |
| `assert` conservation | Fails fast in debug/test if an edit ever breaks the invariant. |

## The invariant that must never break

`Σ shares == amount`, exactly, for every input. And across the whole pipeline:

```
Σ perParticipant.total == assignedSubtotal + taxMinor + tipMinor == grandTotal
```

Assert it and test it.

## Verified test vectors (port verbatim)

```dart
assert(allocate(1001, [1, 1, 1]).toString() == '[334, 334, 333]');
assert(allocate(660, [1584, 4033, 1933]).toString() == '[138, 353, 169]');
assert(allocate(1510, [1584, 4033, 1933]).toString() == '[317, 807, 386]');
assert(allocate(-1001, [1, 1, 1]).toString() == '[-334, -334, -333]');
assert(allocate(100, []).isEmpty);
assert(allocate(90, [0, 0, 0]).toString() == '[30, 30, 30]'); // equal fallback
```

## The split pipeline — three passes, each closed by `allocate()`

Use a neutral `Order` of `LineItem`s, each linking its assignees by id, plus tax
and tip. Never store a total on the order — derive it.

1. **Item subtotals.** A personal item's minor units go wholly to its owner. A
   shared item splits across its `k` assignees via `allocate(itemMinor, [1]*k)`
   in a stable roster order. Each participant subtotal `S[i]` = sum of their
   personal + shared shares. Items with no assignee surface as *unassigned* —
   never charged silently.
2. **Tax.** Take the exact given tax minor units (do **not** recompute from a
   percentage) and `tax = allocate(taxMinor, S)`.
3. **Tip.** Resolve the tip to minor units **once** (rounding site #2), then
   `tip = allocate(tipMinor, S)`. Default base is the pre-tax subtotal (offer a
   post-tax toggle).

`finalᵢ = S[i] + tax[i] + tip[i]`. Because every whole-bill figure is distributed
by `allocate()`, the finals sum to the grand total exactly, for any input.

## The two-rounding-sites trap

There are **two** places rounding happens, not one:

1. `allocate()` itself (handled).
2. **percent → minor units**, whenever a tax/tip/discount is expressed as a rate.

Round the percentage to integer minor units **once**, before feeding `allocate()`:

```dart
// pct is a fraction (0.20 for 20%). Round to minor units ONCE.
final tipMinor = (assignedSubtotalMinor * pct).round();
final tip = allocate(tipMinor, subtotals);
```

A naive `double` percent threaded through the allocation is a classic
off-by-a-minor-unit bug that `allocate` coverage alone will not catch. Model the
rate as a sealed choice so the conversion has exactly one home:

```dart
sealed class TipMode {
  const TipMode();
}
final class PercentTip extends TipMode {
  const PercentTip(this.rate); // e.g. 0.20
  final double rate;
}
final class FixedTip extends TipMode {
  const FixedTip(this.amount); // already minor units
  final int amount;
}

int resolveTipMinor(TipMode mode, int subtotalMinor) => switch (mode) {
      PercentTip(:final rate) => (subtotalMinor * rate).round(),
      FixedTip(:final amount) => amount,
    };
```

## Edge policies to pin in tests

- **Everyone comped (`assignedSubtotal == 0`).** `allocate`'s equal-weight
  fallback splits residual tax/tip evenly. Encode a test so it can't drift.
- **Discounts / comps.** A comped item is `Money(0, …)`; a whole-bill discount is a
  **negative** total prorated with the same `allocate()` (mirror-and-negate).
- **Never sum independently-rounded parts to get a total.** Always allocate a known
  integer total and let the parts absorb the residual.
- **Never recompute a given tax from its rate.** The provided figure is ground
  truth; recomputing reintroduces a rounding disagreement with the source of record.
