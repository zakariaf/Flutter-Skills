# The golden vector table

A golden vector is a committed row of `(key, params) → expected fingerprint (+ any user-visible
derived metric)`, asserted exactly. It is to a generator what a golden image is to a widget — with
one advantage: a fingerprint diff is one line, so a reviewer can actually see that something changed.

## Shape

```dart
@immutable
class DailyPickVector {
  const DailyPickVector(this.isoDay, this.fingerprint, this.itemCount, this.note);
  final String isoDay;      // the key
  final int fingerprint;    // stable hash of the canonical serialization
  final int itemCount;      // a metric the UI actually shows
  final String note;        // why this row exists — read during review
}
```

- **Fingerprint, do not dump.** A whole serialized artifact per row makes the table unreadable and its
  diffs unreviewable, which is how a wrong regeneration gets approved.
- **The fingerprint needs a canonical serialization.** Fixed field order, integers not doubles, sorted
  collections. `toString()` is not canonical.
- **Assert `==` for integers and fingerprints.** A tolerance on a fingerprint is meaningless; a
  tolerance on an integer hides a real change. Reserve `closeTo` for a value that is genuinely a
  calibrated float, and then state the tolerance's reason in a comment.
- **Include a metric the product actually shows** alongside the fingerprint. The fingerprint catches
  *any* change; the metric tells the reviewer whether the change matters to a user.

## Coverage

Rows are cheap; pick them for the bugs they would catch:

- the first and last key the app supports,
- a leap day, a month rollover, a year rollover,
- one row per parameter band or mode the generator supports,
- at least one **historical** key — a date users have already seen — so a regression that rewrites the
  past fails loudly instead of quietly.

## The expected values come from an independent oracle

Generating fixtures with the implementation under test produces a table that agrees with today's
bugs and will keep agreeing with them forever. Get the expected values from something else:

- a second, simpler, slower implementation (brute force is ideal — correctness matters, speed does not),
- a hand-computed row for a small case,
- a reference implementation in another language,
- for a *counting* property, an exhaustive enumerator rather than the production heuristic.

Where a second implementation is genuinely impossible, say so in the table's header comment and treat
those rows as regression pins only — they prove "nothing changed", never "this is right".

## Regeneration: explicit, local, reviewed

```bash
dart run tool/update_vectors.dart     # writes the table; the human reads the diff
```

- **CI verifies; CI never regenerates.** A pipeline that refreshes its own expectations is a gate that
  passes by construction — the same failure mode as `flutter test --update-goldens` in CI.
- A vector diff in a pull request that was supposed to be a refactor is a **defect until proven
  otherwise**. Ask which draw moved.
- The regeneration tool prints *why* each row changed where it can (old vs new metric), because a diff
  of hex fingerprints is otherwise unreviewable.

## Versioning and cutover

Once users have seen output for a key, that output *is* what the key means. So a generator improvement
is a **new version**, not an edit:

```dart
const int generatorVersion = 2;
const String v2CutoverDay = '2026-09-01';   // keys before this still use v1

Pick generateDailyPick(String isoDay) =>
    isoDay.compareTo(v2CutoverDay) < 0 ? _generateV1(isoDay) : _generateV2(isoDay);
```

- **v1 stays in the binary** for as long as history is reachable. Deleting it breaks every stored
  outcome that refers to it.
- **Every stored outcome persists its `generatorVersion`**, so replay picks the right code path.
- **Add new vector rows; never overwrite old ones.** The v1 rows keep proving that the past still
  reproduces. A table where old rows changed is the exact failure the table exists to prevent.
- Choose a **future** cutover key so the switch is not retroactive for anyone mid-session.

## Labels over metrics

Where the artifact carries a derived label — a difficulty, a tier, a size class — separate the two:

- the **metric** is computed by the generator or a solver, and is pinned in the vector row;
- the **label** is a frozen threshold table over the metric.

Test that the mapping is **monotonic** (a higher metric never maps to an easier label) and that the
thresholds themselves have not moved. Do not describe the labeling as proven — it is a calibration.
And never re-label content that already shipped: a user who was told a thing was "hard" was told that,
and rewriting it retroactively makes every past result incomparable.
