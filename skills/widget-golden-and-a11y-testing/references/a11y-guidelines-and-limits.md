# Accessibility testing — guidelines, gate, and honest limits

Accessibility is a correctness property, not polish. No lint enforces it —
`flutter_lints` and `very_good_analysis` ship zero a11y rules — so it is enforced
in `test/` or it is not enforced. But be precise about what automation can prove.

## State the ceiling before writing a line

Automated checks catch a **small minority** of real accessibility issues. Do not
quote the "~57%" figure — that is axe-core's ~100 **web** rules. Flutter ships
**four** guidelines, roughly the trivially machine-checkable subset, and one is
known-broken. Never write a commit message, comment, or report claiming a suite
"tests accessibility". Overclaiming is exactly how an inaccessible app ships green.

## The four built-in guidelines and what each is worth

| Constant | Threshold | Real value |
|---|---|---|
| `androidTapTargetGuideline` | `Size(48, 48)` | Near-zero on an edge-to-edge layout — see boundary skip |
| `iOSTapTargetGuideline` | `Size(44, 44)` | Same |
| `labeledTapTargetGuideline` | label non-empty | Near-zero — an internal id passes |
| `textContrastGuideline` | 4.5 normal / 3.0 large | Known false-negative; do not trust |

Three defects, each load-bearing:

**(a) `MinimumTapTargetGuideline` silently skips every node flush with the view
edge.** Its boundary check uses a `0.001` gap on all four sides and returns
`Evaluation.pass()` without measuring. On an edge-to-edge grid the perimeter cells
are skipped and only interior cells are measured — the test goes green while
checking almost nothing. It also skips any node that is a link, hidden, or has
neither a tap nor a long-press action.

**(b) `textContrastGuideline` has an open, unfixed false negative.** It screenshots
the layer and picks foreground/background by a naive light/dark colour histogram,
mis-attributing background in low-variance regions: white text (`0xFFFFFF`) on
`0xFAFAFA` **passes**. It also only sees text findable via `find.text`, so a
`CustomPainter` label is invisible to it. `MinimumTextContrastGuidelineAAA` exists
but inherits the same sampling defect.

**(c) `labeledTapTargetGuideline` only checks the label is non-empty.** A node
leaking internal data into its label passes.

Keep all four as one-line **advisory tripwires** against catastrophic regression.
They are never the gate.

## Two API facts commonly got wrong

`meetsGuideline` returns an `AsyncMatcher`. **`await expectLater(...)` is
mandatory** — a plain `expect()` looks right and does not do what it looks like.

Semantics is **ON by default** in widget tests: `testWidgets` takes
`bool semanticsEnabled = true` and calls `ensureSemantics()` for you, auto-disposing
the handle. A manual `tester.ensureSemantics()` / `handle.dispose()` pair is a
redundant second reference-counted handle — needed only with
`semanticsEnabled: false` or inside a plain `test()`. When it *is* needed, register
it as `addTearDown(handle.dispose)`, never a trailing `handle.dispose()`: teardown
survives a throwing `expect()`, and a leaked `SemanticsHandle` is itself a flake
source.

## The gate: assert the SemanticsNode directly

```dart
testWidgets('each item exposes a button labelled by its display name',
    (tester) async {
  await tester.pumpApp();

  final node = tester.getSemantics(find.byKey(const ValueKey('item_0')));

  // isSemantics — NOT containsSemantics, which is deprecated. Most tutorials predate it.
  expect(node, isSemantics(
    label: 'First item',
    isButton: true,
    hasEnabledState: true,
    isEnabled: true,
    isFocusable: true,
    hasTapAction: true,
  ));

  // The check NO guideline makes: the label must not leak internal data.
  expect(node.label, isNot(contains('item_0')),
      reason: 'the semantic label leaks the internal id; a screen-reader user '
          'would hear it on every scan step');
});
```

## Tap targets: an explicit getSize loop, not meetsGuideline

Because the built-in guideline skips edge nodes, measure geometry directly. Pick a
floor from the standard you commit to — WCAG 2.5.8 (AA) is 24x24 CSS px, 2.5.5
(AAA) is 44x44; Material recommends 48dp. Do not invent a larger non-standard
number.

```dart
testWidgets('every item is >= 48x48 dp at 200% on the smallest phone',
    (tester) async {
  tester.useDevice(Device.compact);
  await tester.pumpApp(textScaler: const TextScaler.linear(2.0));

  for (final item in kTestItems) {
    final size = tester.getSize(find.byKey(ValueKey('item_${item.id}')));
    expect(size.width, greaterThanOrEqualTo(48.0));
    expect(size.height, greaterThanOrEqualTo(48.0));
  }
});
```

## Traversal order, when it is a design decision

If reading order is deliberately not layout order (e.g. priority-first), assert it
so nobody silently reverts the `sortKey`.

```dart
testWidgets('the screen reader visits items in priority order', (tester) async {
  await tester.pumpApp();

  // startNode:/endNode: — start:/end: are deprecated. They take FinderBase<SemanticsNode>.
  final ordered = tester.semantics.simulatedAccessibilityTraversal(
    startNode: find.semantics.byLabel(kByPriority.first.name),
    endNode: find.semantics.byLabel(kByPriority.last.name),
  );

  expect(ordered.map((n) => n.label).toList(),
      kByPriority.map((i) => i.name).toList(),
      reason: 'traversal order changed — someone dropped the sortKey');
});
```

The fix that this protects costs one argument:
`Semantics(sortKey: OrdinalSortKey(item.priority.toDouble()))`. Traversal order is
a decision; inheriting it from layout is not.

## Contrast: a pure-Dart unit test, because the guideline false-passes

Assert contrast on **colour values**, never on rendered pixels. Loop over every
theme so adding a theme without a passing pairing fails. A single ratio is not
enough — but resist the tempting *wrong* second channel:

> **Grayscale is not an independent channel.** `Color.computeLuminance()` is
> luminance-only (chroma-blind), and any correct `gray(c)` reconstructs a grey with
> exactly that luminance, so `computeLuminance(gray(c)) == computeLuminance(c)` and
> therefore `wcag(gray(a), gray(b)) == wcag(a, b)` for **all** a, b. Wrapping the
> WCAG inputs in `gray()` changes nothing. A WCAG pass already *is* adequate
> luminance contrast — which is precisely what survives Android's system-wide
> grayscale mode. So do not present grayscale as a fourth channel; it carries zero
> signal beyond the WCAG ratio.

The real concern grayscale gestures at is a **chroma-only distinction**: a selected
state at (near-)equal luminance to its background looks distinct in colour yet
collapses to nothing in grayscale. Catch it by asserting the WCAG *luminance* ratio
between the two **state colours** directly — that already fails when the only signal
is chroma. Two genuine channels, then: WCAG luminance ratio, and APCA (Lc) as a
perceptual second opinion (APCA is *not* reproducible by grayscale+WCAG; a
CIEDE2000 chroma difference is another honest option).

```dart
import 'dart:math' as math;
import 'dart:ui';
import 'package:test/test.dart';

double wcag(Color fg, Color bg) {
  final a = fg.computeLuminance(), b = bg.computeLuminance();
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

void main() {
  for (final theme in kAllThemes) {
    group(theme.name, () {
      test('body text on surface meets WCAG AA', () {
        expect(wcag(theme.onSurface, theme.surface), greaterThanOrEqualTo(4.5));
      });
      test('the selected state is not a chroma-only signal', () {
        // Assert the two STATE colours differ in LUMINANCE, not just in chroma —
        // a grayscale-mode user perceives exactly this ratio. No gray() wrapper:
        // it would be an identity on luminance and prove nothing extra.
        expect(wcag(theme.selected, theme.surface), greaterThanOrEqualTo(1.3),
            reason: 'selected vs surface differ only in chroma; a grayscale-mode '
                'user sees no state change');
      });
    });
  }
}
```

Add APCA (Lc) as a second channel for an instrument-grade floor; validate any APCA
implementation against published reference pairs before trusting it. Rule: when a
floor fails, change the **colour**, never the floor — a lowered floor is the test
deleting itself.

## Custom guidelines: the API supports them, but usually don't

`AccessibilityGuideline` is a public abstract class (`const` constructor,
`FutureOr<Evaluation> evaluate(WidgetTester)`, `String get description`). Two
options first:

- **Reconfiguring beats subclassing.** For a stricter tap target, construct
  `MinimumTapTargetGuideline(size:, link:)` directly — it is public and
  `@visibleForTesting`. It still inherits the boundary skip, which is why the
  explicit `getSize` loop above is the gate.
- **`CustomMinimumContrastGuideline(finder:, minimumRatio:)`** scopes contrast to a
  subset — but it samples pixels and carries the same mis-attribution defect.
  Prefer the pure-Dart ratio test.

Write a subclass only for a property that is genuinely a whole-tree traversal. For
anything expressible as a direct `expect` on a `SemanticsNode`, assert it directly
— a better message, no boundary-skip surprises.

## What automation genuinely cannot cover — say so plainly

**Switch Access (Android) / Switch Control (iOS) cannot be tested automatically at
all.** No API simulates scanning, group selection, or point scanning. Traversal
order is a weak proxy: point scanning is coordinate-based with no order; group
selection reaches any of N items in `ceil(log2 N)` presses regardless of order.
A `FocusTraversalPolicy` test is a fine companion, but both are regression guards
on *intent*, never conformance evidence.

Do not build these — they find nothing:
- **Espresso `AccessibilityChecks`** walks the Android **View** hierarchy; Flutter
  is one opaque `FlutterView` rendering to a canvas. It sees no widgets.
- **CI a11y via `flutter drive`.** The semantics tree is not exposed to the
  platform unless an accessibility service is already running.

**Google's Accessibility Scanner and Xcode's Accessibility Inspector do work** —
both read Flutter's `AccessibilityBridge` virtual node tree — but are manual,
on-device, human-driven. They belong in a pre-release checklist, not CI. Manual-
only, each guarding a top-severity failure: TalkBack/VoiceOver actually announcing
labels and activating on double-tap; the focus/scan highlight visible against every
theme; escaping a modal or field using only a switch.

## Review checklist

- `expect()` on a `meetsGuideline` matcher → must be `await expectLater`.
- `containsSemantics` → use `isSemantics`.
- `start:` / `end:` on `simulatedAccessibilityTraversal` → `startNode:` / `endNode:`.
- A trailing `handle.dispose()` → `addTearDown(handle.dispose)`.
- A tap-target claim resting on `meetsGuideline` alone → add the `getSize` loop.
- A contrast claim resting on `textContrastGuideline` → add the pure-Dart ratio test.
- Any unpinned geometry test → `tester.useDevice(...)` first.
