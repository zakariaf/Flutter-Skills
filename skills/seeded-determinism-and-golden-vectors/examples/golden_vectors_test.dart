// Demonstrates the test tier that pins a seeded generator: a frozen vector table asserted
// exactly, a run-twice determinism check, a decorrelation check on consecutive keys, a
// historical-key regression pin, and a monotonicity check on the label thresholds.
//
// Plain `package:test` — no Flutter binding, no fonts, no network. The generator under test
// is examples/seeded_generator.dart.
//
// The fingerprints below are ILLUSTRATIVE. A real table is written by a reviewed
// `dart run tool/update_vectors.dart` from an INDEPENDENT oracle — never by the
// implementation under test. See references/golden-vectors.md.

import 'package:test/test.dart';

import 'seeded_generator.dart';

class DailyPickVector {
  const DailyPickVector(this.isoDay, this.fingerprint, this.itemCount, this.note);
  final String isoDay;
  final int fingerprint;
  final int itemCount;
  final String note;
}

// One row per pinned key. Rows are chosen for the bugs they catch, and old rows
// are NEVER overwritten — a v1 row keeps proving the past still reproduces.
const vectors = <DailyPickVector>[
  // --- v1 era (before the 2026-09-01 cutover) — historical, must never change.
  DailyPickVector('2026-01-01', 0x1111111111111111, 3, 'v1 · year boundary'),
  DailyPickVector('2026-02-29', 0x2222222222222222, 3, 'v1 · leap day'),
  DailyPickVector('2026-07-04', 0x3333333333333333, 3, 'v1 · shipped date users saw'),
  // --- v2 era (from the cutover onward).
  DailyPickVector('2026-09-01', 0x4444444444444444, 4, 'v2 · first day of the new version'),
  DailyPickVector('2026-12-31', 0x5555555555555555, 3, 'v2 · year end'),
];

void main() {
  group('frozen vectors', () {
    test('every row reproduces exactly', () {
      for (final v in vectors) {
        final pick = generateDailyPick(v.isoDay);
        // `==` for fingerprints and integers: a tolerance here would hide a real change.
        expect(pick.fingerprint(), equals(v.fingerprint), reason: v.note);
        expect(pick.items.length, equals(v.itemCount), reason: v.note);
      }
    });

    test('the cutover routes each key to the right generator version', () {
      expect(generateDailyPick('2026-08-31').generatorVersion, equals(1));
      expect(generateDailyPick('2026-09-01').generatorVersion, equals(2));
      // v1 must stay reachable for as long as history is: deleting it breaks
      // every stored outcome that refers to it.
    });
  });

  group('determinism', () {
    test('the same key produces a byte-identical result', () {
      // The check that fails the moment anyone reintroduces ambient randomness
      // or a clock read on the generation path.
      for (final day in ['2026-01-01', '2026-07-04', '2027-03-15']) {
        final a = generateDailyPick(day);
        final b = generateDailyPick(day);
        expect(a.canonical(), equals(b.canonical()), reason: day);
      }
    });

    test('consecutive days do not correlate', () {
      // Without the SplitMix64 mix step this fails: FNV-1a's weak avalanche
      // leaks one-byte key differences straight into the output.
      final fingerprints = <int>[];
      for (var d = 1; d <= 28; d++) {
        final day = '2026-10-${d.toString().padLeft(2, '0')}';
        fingerprints.add(generateDailyPick(day).fingerprint());
      }
      expect(fingerprints.toSet().length, equals(fingerprints.length));

      for (var i = 1; i < fingerprints.length; i++) {
        final previous = generateDailyPick('2026-10-${i.toString().padLeft(2, '0')}');
        final current = generateDailyPick('2026-10-${(i + 1).toString().padLeft(2, '0')}');
        final shared = previous.items
            .map((e) => e.id)
            .toSet()
            .intersection(current.items.map((e) => e.id).toSet());
        expect(shared.length, lessThan(current.items.length),
            reason: 'day $i and ${i + 1} produced the same selection');
      }
    });
  });

  test('labels are monotonic in the measured metric', () {
    // The metric is measured; the label is a frozen threshold table over it.
    // Assert the mapping never gets easier as the metric grows — do not claim
    // the calibration itself is "proven".
    var previous = labelFor(0).index;
    for (var count = 0; count <= 12; count++) {
      final current = labelFor(count).index;
      expect(current, greaterThanOrEqualTo(previous), reason: 'itemCount $count');
      previous = current;
    }
  });
}
