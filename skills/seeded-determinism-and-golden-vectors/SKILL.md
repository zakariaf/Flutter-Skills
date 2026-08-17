---
name: seeded-determinism-and-golden-vectors
description: >-
  Enforces reproducible derived content — output every device must compute identically from a
  key, with no server. The key is injected, never read from a clock; a calendar-day key is a
  civil date, not an instant, and one day definition serves every comparison; the seed is a
  specified hash plus a mix step feeding a PRNG you own, never `dart:math`'s `Random`; entropy
  has exactly one source, so no `DateTime.now()`, no ambient `Random()`, no ordering by
  `identityHashCode`; content is regenerated from (key, generatorVersion) rather than stored; a
  shipped generator is frozen and an improvement is a versioned cutover, never an in-place edit
  that rewrites history; and it is pinned by a committed golden-vector table of fingerprints from
  an independent oracle, regenerated only by a reviewed command CI verifies but never blesses.
  Use when generating content from a seed or date, writing or regenerating golden vectors,
  versioning a generator, or debugging output that differs between devices or runs.
---

# Seeded determinism and golden vectors

Some output must be a **pure function of a key**: the daily pick every user compares with their
friends, a procedurally generated layout, a shareable result someone else can verify. It has to come
out identical on every device, in every timezone, on the platform build you ship next year — with no
server to arbitrate. That is a stronger property than "the tests pass", and it needs its own
discipline plus a frozen oracle to keep it.

`testing-strategy` owns *how* you test pure logic (seeded fuzz against an independent oracle, injected
`Clock`). This skill owns what makes the output reproducible in the first place, and the committed
vector table that pins it.

**A golden *vector* is not a golden *image*.** Vectors are data fingerprints for a pure generator,
asserted by `dart test` with no widget binding; reference PNGs of rendered UI belong to
`widget-golden-and-a11y-testing`, and re-blessing them is the separate ritual in
`run-goldens-rebaseline`. The two share only the word "golden" and the rule that a gate must never
regenerate what it checks.

## Non-negotiable rules

1. **The key is injected, never read.** A generator takes its key as an argument — a date string, an
   id, a sequence number. Nothing reachable from it calls `DateTime.now()`. Wall-clock time enters
   the app exactly once, through the injected `Clock` at the composition root
   (`value-objects-money-and-units` owns that rule). WHY: a generator that reads a clock is
   untestable and un-golden-able, and its output cannot be reproduced from a bug report.

2. **A calendar-day key is a civil date, not an instant.** "The 4th of July" is a date-only value —
   store and pass it as one (an ISO `YYYY-MM-DD` string or a day serial), never as a `DateTime`
   instant. An *event timestamp* is still a UTC instant; a *day identity* is not a moment in time at
   all. WHY: an instant makes every read timezone-dependent, so two devices disagree about which
   content is "today's".

3. **One day definition, used everywhere it is compared.** If content is derived from a UTC day while
   a streak, deadline, or "already seen" check uses local midnight, the two disagree for hours every
   day near the boundary. Pick local or UTC deliberately, name it once, and route every comparison
   through that one definition.

4. **Entropy has exactly one source: a seed you derived.** No ambient `Random()`/`Random.secure()`
   anywhere on the generation path — not even for a "harmless" tiebreak or shuffle. Every draw is an
   explicit call on the seeded generator you threaded in, and the **order of draws is part of the
   contract**: reordering two draws changes every output after it.

5. **Derive the seed with a specified hash *and* a mix step.** Hash the key string (FNV-1a-64 is
   small, specified and easy to reimplement), XOR in a per-feature and per-mode salt, then pass the
   result through an avalanche/mix step (SplitMix64) before drawing from it. WHY: consecutive keys
   differ by one byte, and without a mix step that correlation shows up as visibly similar output on
   consecutive days — the bug users notice first. See `references/seed-derivation.md`.

6. **Own the PRNG; do not depend on an unspecified one.** `dart:math`'s `Random(seed)` is reproducible
   within a given runtime, but its algorithm is an implementation detail with no documented stability
   guarantee across SDK versions or platforms. Output a user will compare with another user's must not
   rest on that. SplitMix64 is eight lines; write it, test it against published vectors, and freeze it.

7. **Salt per feature and per mode.** Two features seeded from the same date must not draw the same
   sequence, or their outputs correlate visibly. One salt constant per feature, frozen forever once
   shipped.

8. **Regenerate derived content; never store it.** Persist the **key**, the **generatorVersion**, and
   the **outcome** (what the user did). The content itself is `key → generator → content`, rebuildable
   forever. WHY: storing it doubles the source of truth and makes history un-migratable. Derived
   *aggregates* are likewise recomputed on read — `persistence-drift` owns that rule.

9. **A shipped generator is frozen.** The moment users have seen output for a key, that output *is*
   what that key means. An improvement ships as a **new version with a cutover key**, with the old
   version kept in the binary to reproduce everything before it. Never edit a shipped generator in
   place: it silently rewrites what the past was, and every stored outcome now refers to content that
   no longer exists.

10. **Pin the contract with golden vectors.** A committed table of `(key, params) → fingerprint` rows,
    plus whatever derived metrics the UI shows, asserted exactly. Store a **fingerprint** (a stable
    hash of the canonical serialization), not the whole artifact, so the table stays small and a real
    change is a one-line diff a reviewer can actually see. `==` for integers and fingerprints;
    tolerance only for a deliberately calibrated float.

11. **Compute every expected value from an independent oracle.** A fixture generated by the
    implementation under test enshrines that implementation's bugs — including the one you are about
    to introduce. Derive vector rows from a separate, simpler, slower implementation, or by hand.
    (`testing-strategy` owns the independent-oracle principle for fuzz loops; this is its frozen-table
    half.)

12. **Regeneration is explicit, reviewed, and never automatic.** Vectors are refreshed only by a
    deliberate local command whose diff a human reads in the pull request. **CI verifies and never
    blesses** — a pipeline that regenerates its own expectations is a gate that checks nothing, the
    same failure as running `--update-goldens` in CI.

13. **Measured, then labeled — never marketed as a proof.** Where a generated artifact carries a
    derived label (a difficulty, a quality tier, a size class), the metric is computed and the label
    is a **frozen threshold table** over it. Assert that the mapping is monotonic and that the
    thresholds have not moved; do not describe a calibration as proven, and never re-label content
    that already shipped.

## Deriving the seed

```dart
/// FNV-1a-64 over the key's UTF-8 bytes. Small, specified, trivially portable.
int fnv1a64(String key) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(key)) {
    hash = (hash ^ byte) * 0x100000001b3;   // 64-bit wrap-around is intended
  }
  return hash;
}

/// The one entropy source. SplitMix64 — eight lines, published test vectors,
/// and yours forever, unlike an SDK-internal generator.
class SeededRng {
  SeededRng(this._state);
  int _state;

  int nextInt64() {
    _state += 0x9e3779b97f4a7c15;
    var z = _state;
    z = (z ^ (z >>> 30)) * 0xbf58476d1ce4e5b9;
    z = (z ^ (z >>> 27)) * 0x94d049bb133111eb;
    return z ^ (z >>> 31);
  }

  /// Uniform in [0, max). Draw order is part of the contract — never reorder.
  int nextInt(int max) => nextInt64().toUnsigned(63) % max;
}

/// The only place the calendar meets a generator. `isoDay` is a civil date
/// ("2026-07-04") supplied by the caller — the generator never reads a clock.
SeededRng seedFor(String isoDay, {required int featureSalt, int modeSalt = 0}) =>
    SeededRng(fnv1a64(isoDay) ^ featureSalt ^ modeSalt);
```

⚠️ **If the app also builds for web, 64-bit integer arithmetic does not behave this way** — Dart
integers compile to JavaScript doubles there. Either restrict this code to native targets or
implement the hash and PRNG in 32-bit halves. See `references/seed-derivation.md`.

## The golden vector table

```dart
// One row per pinned key. Computed ONCE from an independent oracle (rule 11) and
// refreshed only by `dart run tool/update_vectors.dart` (rule 12).
const dailyPickVectors = <DailyPickVector>[
  DailyPickVector('2026-01-01', 0x9f3ac1e0, 12, 'year boundary'),
  DailyPickVector('2026-07-04', 0x2b7708d4, 3, 'mid-year'),
  DailyPickVector('2026-12-31', 0x84ce11a9, 7, 'year end'),
];

test('the generator reproduces every frozen vector', () {
  for (final v in dailyPickVectors) {
    final pick = generateDailyPick(v.isoDay);
    expect(pick.fingerprint(), equals(v.fingerprint), reason: v.note);
    expect(pick.items.length, equals(v.itemCount), reason: v.note);
  }
});
```

Cover the boundaries a bug would hide behind: the first and last key you support, a leap day, a
month/year rollover, and at least one *historical* key so a regression that rewrites the past fails
loudly.

## Anti-patterns

- **`DateTime.now()` inside a generator or a seed helper** — the output stops being reproducible and
  cannot be regenerated from a bug report.
- **A `DateTime` instant used as a day identity** — every read becomes timezone-dependent.
- **Deriving content from a UTC day while a boundary check uses local midnight** — a daily off-by-one
  for hours a day, and the hardest kind of bug to see from your own timezone.
- **An ambient `Random()` for a "harmless" tiebreak** — one call and the whole contract is gone.
- **Reordering draws** during a refactor — every output after the swap changes; draw order is a contract.
- **Seeding straight from the raw hash with no mix step** — consecutive days come out visibly similar.
- **Reusing one salt for two features** — their outputs correlate.
- **Depending on `Random(seed)`, `identityHashCode`, or hash-set iteration order** for anything a user
  sees — no documented stability guarantee; sort by an explicit key before drawing.
- **Storing the generated artifact** — persist `(key, generatorVersion, outcome)` and regenerate.
- **Editing a shipped generator in place** — it rewrites what past keys meant; ship a versioned cutover.
- **Vectors generated by the implementation under test** — they enshrine its bugs.
- **Storing whole artifacts in the vector table** — unreviewable diffs; fingerprint them.
- **Auto-regenerating vectors in CI** — the gate then verifies nothing.
- **Calling a calibrated label "proven"** — the metric is measured; the label is a frozen threshold.

## Definition of done

- [ ] The generator takes its key as an argument; nothing on its path reads a clock or ambient random.
- [ ] A day key is a civil date, and one day definition is used by every comparison that touches it.
- [ ] The seed is `hash(key) ^ featureSalt ^ modeSalt` through a mix step, into a PRNG the repo owns.
- [ ] Salts are frozen constants, one per feature/mode.
- [ ] Content is regenerated from `(key, generatorVersion)`; only the key, version and outcome persist.
- [ ] `generatorVersion` is stored with every outcome; a generator change ships as a new version with
      a cutover, and the previous version stays able to reproduce history.
- [ ] A committed vector table pins fingerprints plus any user-visible derived metric, covering the
      range boundaries, a leap day, and a historical key.
- [ ] Every expected value came from an independent oracle, not from the implementation under test.
- [ ] Regeneration is a reviewed local command; CI only verifies.
- [ ] A determinism test asserts two runs from the same key are byte-identical, so any reintroduced
      ambient randomness fails the build.
- [ ] `scripts/check-determinism-bans.sh` is green over the generator's package/directory.
- [ ] Any derived label is a frozen threshold table with a monotonicity test; shipped content is never
      re-labeled.

## Related skills

- See `testing-strategy` for seeded fuzz loops, the independent-oracle principle, and injecting
  `Clock` — this skill's tests are that shape.
- See `value-objects-money-and-units` for canonical storage and the injected `Clock` seam.
- See `persistence-drift` for storing the key/version/outcome and recomputing derived aggregates.
- See `project-structure-and-packages` for keeping the generator in a Flutter-free package where these
  bans are mechanically enforceable.
- See `widget-golden-and-a11y-testing` for reference *images* of rendered UI, and
  `run-goldens-rebaseline` for the ritual that re-blesses them — a different tier from these vectors.
- See `ci-pipeline-and-gates` for running the vector check and the ban grep as gates.
- See `dart3-idioms-and-coding-standards` for the immutable value types the generator returns.

## References

- Dart API — `dart:math` `Random` (seeded construction): https://api.dart.dev/stable/dart-math/Random-class.html
- Dart — numbers on the web (`int` as JS double, `>>>`, overflow): https://dart.dev/guides/language/numbers
- Dart API — `identityHashCode`: https://api.dart.dev/stable/dart-core/identityHashCode.html
- FNV hash specification: https://datatracker.ietf.org/doc/html/draft-eastlake-fnv
- SplitMix64 (Steele, Lea, Flood — "Fast splittable pseudorandom number generators"): https://doi.org/10.1145/2660193.2660195
- `package:test`: https://pub.dev/packages/test
