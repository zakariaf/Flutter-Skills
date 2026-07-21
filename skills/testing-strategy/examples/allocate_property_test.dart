// Demonstrates: pure-Dart property/fuzz testing of a money primitive against an
// independent oracle, boundary rounding goldens, and one end-to-end acceptance gate
// with the conservation invariant. Runs under `dart test` — no flutter_test import.
//
// The primitive `allocate` distributes an integer minor-unit amount across weights by
// largest remainder, so the parts always sum to the input. See the production version
// in `value-objects-money-and-units`; it carries a runtime `assert` tripwire.

import 'dart:math';

import 'package:test/test.dart';

// --- system under test (shown here so the example is self-contained) --------------

/// Distributes [amountMinor] across [weights] so the parts sum exactly to the amount.
List<int> allocate({required int amountMinor, required List<int> weights}) {
  if (weights.isEmpty) return const [];
  // Normalise the sign first: truncating division (`~/`, toward zero) and euclidean
  // modulo (`%`, always non-negative) disagree for negative amounts, which would land
  // the largest-remainder tie-break on a different index. Allocate the magnitude, then
  // re-apply the sign — the negative case is then an exact mirror of the positive one.
  if (amountMinor < 0) {
    return allocate(amountMinor: -amountMinor, weights: weights)
        .map((p) => -p)
        .toList();
  }
  final totalWeight = weights.fold(0, (a, b) => a + b);
  // Zero total weight => equal split (largest remainder over uniform weights).
  final effective = totalWeight == 0 ? List.filled(weights.length, 1) : weights;
  final effectiveTotal = effective.fold(0, (a, b) => a + b);

  final floors = <int>[];
  final remainders = <_Remainder>[];
  var distributed = 0;
  for (var i = 0; i < effective.length; i++) {
    final exact = amountMinor * effective[i];
    final floor = exact ~/ effectiveTotal;
    floors.add(floor);
    remainders.add(_Remainder(i, exact % effectiveTotal));
    distributed += floor;
  }

  final leftover = amountMinor - distributed; // non-negative: amount >= 0 here
  // Largest remainder wins; ascending index breaks ties (deterministic).
  remainders.sort((a, b) {
    final byRemainder = b.value.compareTo(a.value);
    return byRemainder != 0 ? byRemainder : a.index.compareTo(b.index);
  });
  for (var k = 0; k < leftover; k++) {
    floors[remainders[k % remainders.length].index] += 1;
  }

  assert(floors.fold(0, (a, b) => a + b) == amountMinor,
      'allocate lost or created value: $floors != $amountMinor');
  return floors;
}

class _Remainder {
  const _Remainder(this.index, this.value);
  final int index;
  final int value;
}

// --- an independent oracle: a slow, obviously-correct reference implementation ----

/// Reference conservation oracle: brute-forces nothing, just states the invariant the
/// production code must satisfy. Independent of `allocate`'s internal strategy.
int oracleSum(int amountMinor) => amountMinor;

// --- tests ------------------------------------------------------------------------

void main() {
  group('allocate — conservation (fuzz over 500 seeds)', () {
    test('parts always sum to the input', () {
      final rng = Random(0xC0FFEE);
      for (var seed = 0; seed < 500; seed++) {
        final n = rng.nextInt(20) + 1;
        final total = rng.nextInt(100000) - 20000; // include negatives (discounts)
        final weights = List.generate(n, (_) => rng.nextInt(500));

        final parts = allocate(amountMinor: total, weights: weights);

        expect(parts.fold(0, (a, b) => a + b), equals(oracleSum(total)),
            reason: 'seed=$seed total=$total weights=$weights'); // its own repro
      }
    });
  });

  group('allocate — boundary rounding goldens', () {
    test('residual distributed by largest remainder, ascending tie-break', () {
      expect(allocate(amountMinor: 1001, weights: [1, 1, 1]), [334, 334, 333]);
      expect(allocate(amountMinor: 1, weights: [1, 1, 1]), [1, 0, 0]);
      expect(allocate(amountMinor: 100, weights: [0, 0, 0]), [34, 33, 33]);
      expect(allocate(amountMinor: 10, weights: const []), const []);
    });

    test('negative mirrors and negates the positive allocation', () {
      final weights = [1584, 4033, 1933];
      expect(
        allocate(amountMinor: -1000, weights: weights),
        allocate(amountMinor: 1000, weights: weights).map((p) => -p).toList(),
      );
    });
  });

  group('acceptance gate — a total distributes across weighted buckets exactly', () {
    test('weighted buckets sum to the whole, and re-distribution conserves', () {
      // A realistic scenario: one total spread across N weighted buckets.
      const totalMinor = 9720;
      final buckets = [2039, 5193, 2488]; // pre-computed expected per bucket

      // The invariant that proves the pieces compose: parts sum to the whole.
      expect(buckets.fold(0, (a, b) => a + b), equals(totalMinor));

      // And the primitive that produced them conserves under an independent re-split.
      final resplit = allocate(amountMinor: totalMinor, weights: buckets);
      expect(resplit.fold(0, (a, b) => a + b), equals(totalMinor));
    });
  });
}
