// Demonstrates the single money-division primitive: an integer largest-remainder
// (Hamilton) allocate() whose parts always sum EXACTLY to the whole, plus the
// subtotal -> tax -> tip split pipeline layered on top of it and the
// percent->minor-units "second rounding site". Pure Dart, no dependencies.

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

// --- A tiny split pipeline over a neutral Order -----------------------------

class LineItem {
  const LineItem(this.minor, this.assigneeIndexes);
  final int minor; // amount in minor units
  final List<int> assigneeIndexes; // participants who share this item
}

/// tip resolved to minor units ONCE (the second rounding site) before allocate.
int resolveTipMinor(int subtotalMinor, double rate) =>
    (subtotalMinor * rate).round();

/// subtotals -> allocate(tax, subtotals) -> allocate(tip, subtotals).
/// Returns each participant's final total; they sum to the grand total exactly.
List<int> splitOrder({
  required int participantCount,
  required List<LineItem> items,
  required int taxMinor,
  required double tipRate,
}) {
  final subtotals = List<int>.filled(participantCount, 0);
  for (final item in items) {
    final weights = List<int>.filled(participantCount, 0);
    for (final i in item.assigneeIndexes) {
      weights[i] = 1;
    }
    final shares = allocate(item.minor, weights);
    for (var i = 0; i < participantCount; i++) {
      subtotals[i] += shares[i];
    }
  }

  final assignedSubtotal = subtotals.fold(0, (a, b) => a + b);
  final tax = allocate(taxMinor, subtotals);
  final tipMinor = resolveTipMinor(assignedSubtotal, tipRate);
  final tip = allocate(tipMinor, subtotals);

  return [
    for (var i = 0; i < participantCount; i++) subtotals[i] + tax[i] + tip[i],
  ];
}

void main() {
  // Verified largest-remainder vectors.
  assert(allocate(1001, [1, 1, 1]).toString() == '[334, 334, 333]');
  assert(allocate(660, [1584, 4033, 1933]).toString() == '[138, 353, 169]');
  assert(allocate(1510, [1584, 4033, 1933]).toString() == '[317, 807, 386]');
  assert(allocate(-1001, [1, 1, 1]).toString() == '[-334, -334, -333]');
  assert(allocate(100, []).isEmpty);
  assert(allocate(90, [0, 0, 0]).toString() == '[30, 30, 30]');

  // Worked anchor: distribute a total across 3 weighted parties (0, 1, 2).
  // Party 0: one 1250 item. Party 1: 2800 + 900. Party 2: 1600. Plus a 1000 item
  // shared equally across all three.
  // tax 660; tip 20% of the pre-tax subtotal (7550 -> 1510).
  // Subtotals become [1584, 4033, 1933], matching the allocate vectors above.
  final finals = splitOrder(
    participantCount: 3,
    items: const [
      LineItem(1250, [0]),
      LineItem(2800, [1]),
      LineItem(900, [1]),
      LineItem(1600, [2]),
      LineItem(1000, [0, 1, 2]),
    ],
    taxMinor: 660,
    tipRate: 0.20,
  );
  assert(finals.toString() == '[2039, 5193, 2488]');

  // The invariant that must never break: parts sum to the grand total exactly.
  assert(finals.fold(0, (a, b) => a + b) == 9720);

  print('allocate.dart: all assertions passed');
}
