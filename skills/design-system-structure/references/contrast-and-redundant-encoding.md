# Contrast as a unit test, and redundant encoding

Because every color is a token declared in one place, accessibility floors that are usually manual become mechanical: a unit test over declared pairs. This is the part of the design system that is a *correctness property*, not a matter of taste.

## Both themes pass AA — independently, as a unit test

Dark gets no credit for light's ratios. Author each theme so, on its *actual* surfaces:

- Body text ≥ 4.5:1.
- Large text (≥ 24px, or ≥ 19px bold) and meaningful non-text UI (borders, focus rings, selection, meters, icons that carry meaning) ≥ 3:1.
- A muted/tertiary tone that only passes at large sizes is caption/large-text only — never an interactive label or body copy. Document which slot that is.

Because the values are tokens, verify with `Color.computeLuminance()` instead of eyeballing:

```dart
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

test('semantic pairs meet AA in both themes', () {
  for (final c in [lightColors, darkColors]) {
    expect(contrastRatio(c.onSurface, c.surface), greaterThanOrEqualTo(4.5));
    expect(contrastRatio(c.hairline, c.surface), greaterThanOrEqualTo(3.0)); // non-text
    expect(contrastRatio(c.accent, c.surface), greaterThanOrEqualTo(3.0));
  }
});
```

Enumerate every declared foreground/background pair. Hand-sampling is only needed where a value sits over a gradient or texture — then measure the **worst-case stop/region** (or put text on a measured scrim and measure the scrim), and record the sampled value as evidence. A new color slot with no gate entry is an unverified color that nothing in the field will report as broken.

## Color is the derived token — the ≥3-signal rule is owned by accessibility

`accessibility-as-code` owns the never-color-alone rule: every stateful meaning carries **≥3 non-color signals** (glyph, label, weight/position) with color only supporting — see it for the channel table, thresholds, chart-hue reservations, and traversal rules. The *design-system* half, owned here, is one thing: **color is a derived token, computed last.**

- **Derive color last.** The status is a value object (an enum or a small class); color is a pure function *of* it, resolved through a semantic slot at the end. Status is never read *from* color, and the color is never a raw literal — it is a slot read (SKILL rule 7).
- **Severity ramps carry monotonic luminance.** Author each step as both a different hue *and* darker/heavier, so severity survives desaturation and the supporting color reinforces the non-color signals instead of carrying them.

The acceptance test both skills lean on: a **pure-greyscale screenshot** must still answer "what state is this, and what needs attention?". Add a greyscale golden.

## Screen-reader completeness for decorative painters

A `CustomPaint` is one opaque rectangle to a screen reader. Wrap it so the *meaning* is announced, not the pixels:

```dart
Semantics(
  container: true,
  label: 'Account balance',
  value: '$formattedValue. Status: ${status.label(l)}.',
  child: ExcludeSemantics(child: BalanceChart(...)), // hide the decorative painter
)
```

Group a tile's number + label + icon with `MergeSemantics` into one readable unit. Expose the *final* value of any count/counter animation immediately and `ExcludeSemantics` the animation. `custom-canvas-and-gestures` owns the painter-side pattern.

## a11y flags come from `MediaQuery` — owned by accessibility-as-code

Reading platform a11y flags (`disableAnimationsOf`, `boldTextOf`, `highContrastOf`, `textScaler`) from `BuildContext` at build time rather than a stale app-state copy is owned by `accessibility-as-code`. Two design-system wrinkles only: you may read `highContrastOf` opportunistically to *seed* an initial theme default (the user's explicit stored choice must still win, and `highContrastOf` is reported only on some platforms, so an in-app switch is the reliable mechanism); and the one flag this skill acts on directly is `disableAnimationsOf`, which feeds `resolveMotion` — the reduced-motion helper this skill owns.

## Honest limits

An automated contrast test proves the declared pairs, not every rendered composition (text over a photo, a color under a semi-transparent scrim, a token used somewhere unexpected). A greyscale golden proves the states you rendered into it. Neither replaces the once-per-app manual review (`design-review-workflow`) — they make it start from a floor instead of from zero.
