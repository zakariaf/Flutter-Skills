---
name: run-goldens-rebaseline
description: >-
  Runs the golden re-baselining ritual — the one sanctioned way committed reference
  images are overwritten. Enforces the order: land and green the non-golden geometry,
  contrast and a11y tests FIRST, re-baseline only in the pinned blessing environment
  that produced the committed images, with loadAppFonts() so nothing renders in Ahem,
  via `flutter test --update-goldens --tags golden` (never in CI, never to make a red
  pipeline green), then inspect every changed PNG by eye, delete the orphans left by
  renamed or removed tests, land the images as their own commit naming why they moved,
  and prove it by re-running the suite WITHOUT the flag. Manual, side-effecting
  workflow. Use when a deliberate visual change breaks matchesGoldenFile, when adding
  or renaming a golden test, or when someone reaches for --update-goldens.
disable-model-invocation: true
---

# Run goldens rebaseline

Blessing a golden overwrites the only record of what the UI used to look like. It is
the one operation in the test suite that *destroys* an assertion instead of running it,
so it is a **manual, low-freedom, human-run** workflow: execute the steps in order, do
not improvise, and never run it to make a failure go away.

The two-lane golden strategy, the harness, and why goldens are the *weakest* visual
assertion belong to `widget-golden-and-a11y-testing`. This skill is only the ritual for
changing the baselines.

## Non-negotiable rules

1. **A golden failure is a question, not a chore.** Before anything is regenerated,
   answer: did I intend this pixel change? If the answer is not an unambiguous yes for
   *every* changed image, the change is a regression and the code is what gets fixed.
2. **Green the real assertions first.** Computed geometry, tap-target size, overflow,
   text-scale, and pure-Dart contrast tests must pass *before* re-baselining. WHY: a
   golden cannot assert anything — a blessed screenshot of clipped, unreadable text
   passes forever. The assertions are the gate; the images are only a diff.
3. **Re-baseline only in the pinned blessing environment.** Same OS and same Flutter
   version that produced the committed images. WHY: font rasterization differs by host,
   so blessing elsewhere rewrites every image with host noise and permanently breaks the
   comparison for everyone else.
4. **`loadAppFonts()` must have run.** Without it the real-font lane renders every glyph
   as an Ahem box and you bless a wall of rectangles that will "pass" forever.
5. **Never `--update-goldens` in CI, and never to fix a red pipeline.** A gate that
   rewrites the thing it checks asserts nothing (`ci-pipeline-and-gates`). Blessing is a
   local, human-reviewed act.
6. **Never bless a flaky golden.** A golden that changes without a code change is an
   environment or animation-settling defect — pump to a settled frame, remove the
   time-dependence, or delete the golden. Re-blessing hides it until the next run.
7. **Inspect every changed image by eye, individually.** Not the count, not the diff
   stat — the images. WHY: this is the entire review; an unrelated screen that moved is
   exactly what the ritual exists to catch.
8. **Bless the whole affected set in one pass, never a subset.** Blessing only the
   images you expected to change leaves the others failing and invites a second,
   unreviewed pass.
9. **Delete the orphans.** A renamed or removed golden test leaves its PNG behind
   forever, and nothing fails. Removing stale files is part of the same change.
10. **The images land as their own commit, in the same PR as the change that moved
    them,** with a message naming *what* changed and *why*. WHY: binary blobs mixed into
    a code commit make the code diff unreadable, and a reviewer cannot tell an intended
    re-baseline from a smuggled one.

## The ordered workflow

1. **Confirm the change is intentional** and that the non-golden test suite (geometry,
   overflow, text-scale, contrast, a11y) is green.
2. **Run the failing goldens once, without the flag, and read the failure output.**
   Flutter writes `failures/*_testImage.png`, `*_masterImage.png`, and `*_isolatedDiff.png`
   next to the goldens — open the diff before deciding anything.
3. **Confirm you are in the blessing environment** (pinned OS + `flutter --version`
   matching the one that produced the committed baselines).
4. **Re-baseline, scoped to the golden tag:**
   ```bash
   flutter test --update-goldens --tags golden
   # or a single file while iterating:
   flutter test --update-goldens test/golden/notes_screen_golden_test.dart
   ```
5. **List what actually changed** and open every one:
   ```bash
   git status --porcelain -- '*.png'
   ```
   An image you did not expect is a regression. Stop, revert the images
   (`git checkout -- <paths>`), and fix the code.
6. **Remove orphans** — golden files no longer referenced by any test:
   ```bash
   # Every committed golden whose filename appears in no test source.
   for f in $(git ls-files 'test/**/goldens/*.png'); do
     grep -rq "$(basename "$f")" test --include='*.dart' || echo "orphan: $f"
   done
   ```
7. **Delete the `failures/` artifacts** so they are never committed.
8. **Prove it: re-run the suite WITHOUT the flag.**
   ```bash
   flutter test --tags golden
   ```
   Anything still failing means the baseline you just wrote does not reproduce — an
   unsettled animation, a time-dependent value, or a font that was not loaded.
9. **Commit the images alone**, e.g.
   `test(goldens): rebaseline notes screen — row height 40→48 (design review FIX-12)`.

## Verification (blocking — must pass before the PR)

- `flutter test --tags golden` is green **without** `--update-goldens`, run twice in a
  row to catch a golden that settles differently between runs.
- Every changed PNG was opened and matches the intended change; nothing unrelated moved.
- No `failures/` directory, no orphan PNGs, and no `--update-goldens` anywhere in
  `.github/workflows/`.
- The geometry/contrast/a11y assertions — the ones that can actually fail meaningfully —
  are still green.

## Anti-patterns

- **`--update-goldens` as the reflex response to a red test** — deletes the assertion
  instead of reading it.
- **Blessing on a different machine or Flutter version than the baselines** — rewrites
  every image with host-specific rasterization; everyone else's suite goes red.
- **Blessing without `loadAppFonts()`** — a wall of Ahem boxes, blessed as truth.
- **`--update-goldens` in a CI workflow** — the gate now asserts nothing, permanently.
- **Committing images together with the code change** — the reviewer cannot separate the
  intended re-baseline from an accidental one.
- **Blessing a subset of the failures** — the rest fail on the next run and get blessed
  unreviewed.
- **Leaving orphan PNGs after renaming a test** — dead weight nothing will ever fail on.
- **Re-blessing a golden that keeps drifting** — that is a flake to fix, not a baseline
  to update.
- **Committing `failures/*_testImage.png`** — noise, and it silently doubles as a second
  set of "reference" images nobody trusts.

## Definition of done

- [ ] The visual change was intentional and every changed image was inspected by eye.
- [ ] Non-golden geometry, overflow, text-scale, contrast, and a11y tests were green
      *before* re-baselining, and still are.
- [ ] Re-baselined in the pinned blessing environment, with `loadAppFonts()` in effect.
- [ ] The whole affected set was blessed in one pass; nothing unexpected changed.
- [ ] Orphan goldens deleted; `failures/` artifacts removed.
- [ ] `flutter test --tags golden` passes **without** the flag, twice in a row.
- [ ] Images committed on their own, in the same PR, with a message naming the cause.
- [ ] No `--update-goldens` anywhere in CI configuration.

## Related skills

- `widget-golden-and-a11y-testing` — the two golden lanes, the `pumpApp` harness,
  `loadAppFonts()`, and why goldens are the weakest assertion in the suite.
- `ci-pipeline-and-gates` — gates verify and never bless; the pinned-runner rule.
- `design-review-workflow` — the review pass that legitimately produces intentional
  visual changes.
- `design-system-structure` — where a token change that moved every golden originated.
- `testing-strategy` — the assertions that should be carrying the weight instead.

## References

- Flutter — `matchesGoldenFile`: https://api.flutter.dev/flutter/flutter_test/matchesGoldenFile.html
- Flutter — `flutter test` options (`--update-goldens`, `--tags`): https://docs.flutter.dev/reference/flutter-cli
- Flutter — `GoldenFileComparator` / `LocalFileComparator`: https://api.flutter.dev/flutter/flutter_test/GoldenFileComparator-class.html
- `golden_toolkit` / `alchemist` — `loadAppFonts()`: https://pub.dev/packages/alchemist
