# Deriving a seed you can defend

## Why a hash *and* a mix step

Daily keys are adversarially similar: `2026-07-04` and `2026-07-05` differ by one byte. FNV-1a is a
fine, tiny, specified hash, but its avalanche is weak — flip one input byte and a recognizable amount
of structure survives into the output. Seed a generator with that directly and consecutive days
produce visibly related content. Users notice this before they notice almost anything else, and it
looks like the generator is broken even though every value is technically "random".

So: **hash to get a 64-bit value, then mix before drawing.** SplitMix64's finalizer is the standard
cheap fix — two multiply/xor-shift rounds that scatter one-bit input differences across the whole
output word.

Prove it rather than assume it, with a decorrelation test:

```dart
test('consecutive days do not correlate', () {
  final picks = [
    for (var d = 1; d <= 60; d++)
      generateDailyPick('2026-01-${d.toString().padLeft(2, '0')}').fingerprint(),
  ];
  expect(picks.toSet().length, equals(picks.length));            // no repeats
  // And no adjacent pair shares more than chance would predict:
  for (var i = 1; i < picks.length; i++) {
    expect(sharedItems(picks[i - 1], picks[i]), lessThanOrEqualTo(maxExpectedOverlap));
  }
});
```

## Salts

One frozen constant per feature, and one per mode within a feature. Without them, two features that
both derive from today's date draw the identical sequence and their outputs move together — the same
correlation problem one level up.

Salts are **frozen on first ship**, like the generator itself. Changing a salt changes every key's
output, which is a version cutover (see `golden-vectors.md`), not a tweak.

## Draw order is part of the contract

```dart
// These two produce completely different content, and both are "correct" code.
final a = rng.nextInt(rows), b = rng.nextInt(cols);
final b = rng.nextInt(cols), a = rng.nextInt(rows);   // <-- silently rewrites every key
```

Any refactor that reorders, adds, or removes a draw changes all output after that point. This is
exactly what the golden vectors catch, and it is the single most common way a "pure cleanup" commit
breaks reproducibility. Comment the draw sequence where it is not obvious, and treat a vector diff in
a refactor PR as a defect until proven otherwise.

## Dart-specific determinism traps

- **`dart:math`'s `Random(seed)` has no documented cross-version algorithm guarantee.** It is
  reproducible for a given runtime, which is fine for a test fixture and not fine for content two
  users compare on two phones running two SDK builds. Own the PRNG.
- **On the web, `int` is a JavaScript double.** 64-bit wrap-around multiplication does not behave as
  it does on the VM, so an FNV-1a-64 or SplitMix64 written the natural way produces *different*
  numbers in a web build. If web is a target, implement the hash and PRNG in 32-bit halves (or with
  `BigInt`) and add a vector row asserted in a browser test. If web is not a target, say so in the
  package's README — this is the kind of assumption that gets discovered by a port.
- **`identityHashCode` varies between runs.** Anything ordered by default `Object.hashCode`, or by
  iteration over a `HashSet`/`HashMap` of objects, is not reproducible. Sort by an explicit,
  meaningful key before you draw from a collection. `LinkedHashMap` literal order is stable, but the
  moment a `Set` is involved, sort first.
- **Floating point is a liability on the generation path.** Prefer integer arithmetic; a double
  accumulated in a different order is a different double, and transcendental functions are not
  bit-identical everywhere. If a float must be part of the output, freeze it as a rounded integer or a
  fixed-precision string.
- **`toString()` of a double, a `Set`, or a `Map` is not a stable serialization.** Write an explicit
  canonical serializer for anything you fingerprint.

## Where the generator lives

Put it in a **Flutter-free package or directory** (`project-structure-and-packages`) so the bans are
mechanically checkable: no `dart:ui`, no `dart:io`, no clock, no ambient random. That is what lets
`scripts/check-determinism-bans.sh` be a real gate instead of a suggestion, and it is what lets the
tests be plain `dart test` with no widget binding.

## Heavy generation

If generation is expensive enough to drop frames, run it with `Isolate.run` — but keep the generator a
**pure function of value types** so it stays trivially transferable and its determinism is unaffected.
Performance is owned by `flutter-performance`; the only rule here is that moving work off the main
isolate must not introduce a second entropy source (a common accident: seeding "per worker").
