---
name: widget-golden-and-a11y-testing
description: Enforces a disciplined widget/layout/golden/a11y test surface — one pumpApp harness that pins tester.view.physicalSize x devicePixelRatio and layers MediaQuery (textScaler/boldText/accessibleNavigation) above MaterialApp, an overflow net that never suppresses (one testWidgets per device x scale x bold tuple because overflow reports once per RenderObject), a computed getSize/getRect fit-and-geometry gate instead of goldens, two golden lanes (Ahem geometry + one pinned-OS real-font) with loadAppFonts and blocked --update-goldens, RTL goldens under Directionality, pure-Dart WCAG/APCA contrast on colour VALUES, and honest limits on meetsGuideline. Use when writing test/support/harness.dart, calling pumpWidget/pumpApp, chasing an "overflowed by N pixels" failure, reaching for takeException/ignoreOverflowErrors/FittedBox/withClampedTextScaling, adding matchesGoldenFile, or writing a11y_test.dart with isSemantics/simulatedAccessibilityTraversal/meetsGuideline.
---

# Widget, golden and accessibility testing

One harness pins the surface; layout and accessibility are asserted by **computed
geometry on the real widget tree**, not by blessed pixels. Goldens are a narrow,
honest safety net for glyph shaping and mirroring — never the layout gate. This
skill covers the widget tier; for the pure-core / Drift / Notifier tiers see
`testing-strategy`.

Read the reference for the task at hand:
- `references/harness-and-mediaquery.md` — pumpApp, Device presets, the four load-bearing lines, driving MediaQuery flags, finder policy.
- `references/overflow-and-textscale.md` — the two overflow classes, the three traps, the matrix, the fit assertion, and the four wrong fixes.
- `references/a11y-guidelines-and-limits.md` — the four built-in guidelines and their defects, the semantics/traversal gate, pure-Dart contrast, and what automation genuinely cannot cover.
- `references/golden-two-lanes.md` — the golden-refusal argument, the Ahem-vs-real-font lanes, RTL goldens, and blocking accidental blessing.

Run `scripts/check-test-hygiene.sh` before a PR.

## Non-negotiable rules

1. **Pin the device on every layout/geometry test.** The default widget surface
   is **800x600 logical** — wider than any phone. Unpinned, content is ~2x too
   wide, everything fits, the suite is green, and the shipped phone is broken.
   `useDevice(...)` first, `pumpApp(...)` second.
2. **`physicalSize` is in PHYSICAL pixels — always multiply by DPR.**
   `view.physicalSize = Size(320, 640)` at the default DPR 3.0 is a 107x213
   logical surface, not a phone. Set `devicePixelRatio` and
   `physicalSize = logical * dpr`, then `addTearDown(view.reset)` — a leaked size
   poisons every later test in the file.
3. **Layer `MediaQuery` ABOVE `MaterialApp`, built from `.copyWith`.**
   `MaterialApp` inserts no MediaQuery of its own; the one from `pumpWidget`'s
   `View` is nearest. A bare `MediaQueryData()` zeroes the view-derived size the
   device just pinned — the test then measures a 0x0 screen and passes.
4. **`pump()`, never `pumpAndSettle()` as an animation wait.** `pumpAndSettle`
   carries a 10-minute timeout and truncates its stack trace, and hangs forever
   on an infinite splash/shimmer/spinner. Use `pump()` for state changes and
   `pump(duration)` / `fakeAsync` for timer-driven async — `pump()` does **not**
   advance the fake clock.
5. **Never suppress overflow.** A `RenderFlex` overflow already **fails** a
   widget test (it routes through `FlutterError.reportError` and the binding
   rethrows at test end). Never call `takeException()` to swallow it, never assign
   `FlutterError.onError`, never copy `ignoreOverflowErrors`, and never
   `takeException()` in a global `tearDown` — each disarms the whole net.
6. **One `testWidgets` per (device, scale, bold) tuple — never a loop inside a
   test.** Overflow is reported **once per RenderObject** (the flag resets only on
   `reassemble()`), so looping scales inside one test silently under-reports every
   scale after the first. Loop *around* the `testWidgets` call.
7. **Assert the fit, not just absence of overflow.** A clipped `Text` reports
   nothing — `RenderParagraph` has no overflow indicator. `takeException(), isNull`
   is necessary but not sufficient; add a `getSize`/`getRect` assertion that the
   label fits inside its computed cell.
8. **Prefer computed geometry over goldens for layout.** Assert cells in a row
   share a `top` and cells in a column share a `left` (`moreOrLessEquals`,
   `epsilon: 0.5`); assert tap targets with a `getSize` loop. These fail with a
   sentence a human can act on. Goldens cannot *assert* anything — a blessed
   screen of clipped, unreadable text passes forever.
9. **Assert contrast on colour VALUES in pure Dart, never on pixels.**
   `meetsGuideline(textContrastGuideline)` screenshots and histograms the layer —
   white text on `#FAFAFA` **passes** (an open Flutter defect). A pure-Dart WCAG +
   APCA test on the theme's colours cannot false-pass. For a state pair
   distinguished only by chroma (selected vs surface at equal luminance), assert
   `wcag(theme.selected, theme.surface)` directly — a grayscale-mode user perceives
   exactly that luminance gap, so no separate grayscale channel is needed.
10. **`await expectLater(...)` for `meetsGuideline` — it returns an
    `AsyncMatcher`.** A plain `expect()` looks right and asserts nothing. Keep the
    four built-in guidelines only as advisory tripwires; the geometry and
    pure-Dart contrast tests are the gate.
11. **Two golden lanes, both `loadAppFonts()`; block accidental
    `--update-goldens`.** Ahem squares are byte-stable cross-OS and prove
    geometry/mirroring but **not** glyph shaping; one narrow real-font lane on a
    pinned OS proves script joining and numeral glyphs. Tag every golden
    `@Tags(['golden'])` and generate blessed files in one pinned environment only.
12. **Never clamp `TextScaler`.** `withClampedTextScaling`, `textScaleFactor`, and
    `FittedBox` defeat the matrix while contrast and tap-target stay green, and
    override the user's own OS setting. Fix the layout, not the text.

## The harness — one file, imported by every test

`test/support/harness.dart` holds a `Device` value type and a `pumpApp` extension.
Seams throw until overridden, so an un-overridden dependency fails loudly instead
of quietly constructing a live service in a test. See
`references/harness-and-mediaquery.md` and `examples/harness.dart`.

```dart
class Device {
  const Device(this.name, this.logicalSize, this.dpr);
  final String name;
  final Size logicalSize;
  final double dpr;

  // Neutral presets; name them by measured size, not a marketing model.
  static const compact = Device('compact_320', Size(320, 640), 2.0);
  static const small = Device('small_360', Size(360, 800), 3.0);
  static const medium = Device('medium_412', Size(412, 915), 2.625);
  static const all = <Device>[compact, small, medium];
}

extension TestHarness on WidgetTester {
  void useDevice(Device d) {
    view.devicePixelRatio = d.dpr;
    view.physicalSize = d.logicalSize * d.dpr; // physical px — multiply by DPR
    addTearDown(view.reset);                    // one call; nothing forgotten
  }

  Future<void> pumpApp({
    List<Override> overrides = const <Override>[],
    TextScaler textScaler = TextScaler.noScaling,
    bool boldText = false,
    bool accessibleNavigation = false,
  }) async {
    await pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith( // copyWith, NOT MediaQueryData()
              textScaler: textScaler,
              boldText: boldText,
              accessibleNavigation: accessibleNavigation,
            ),
            child: const App(),
          ),
        ),
      ),
    );
    await pump(); // one frame; never pumpAndSettle
  }
}
```

## The overflow + fit matrix

`Device.all` x `[1.0, 1.3, 1.5, 2.0, 3.0]` x `[false, true]` bold = one
`testWidgets` per tuple. `TextScaler.linear` is a deliberate over-approximation
(Android 14+ scales large text *less*) — conservative, not device-faithful. 1.3
and 1.5 are in the list precisely because nonlinear device scaling makes the
mid-range the non-obvious part. `boldText` widens advance widths — **but only when
a real proportional font is loaded**. Under the default Ahem test font every glyph
is a fixed em-square regardless of weight, so the bold axis is a no-op unless the
matrix calls `loadAppFonts()` first; with real fonts loaded it overflows content
that passes unbolded, and stresses real character widths the em-square hides.

```dart
// Real proportional fonts, or the bold + character-width axes are inert under Ahem.
setUpAll(loadAppFonts);

for (final device in Device.all) {
  for (final scale in const <double>[1.0, 1.3, 1.5, 2.0, 3.0]) {
    for (final bold in const <bool>[false, true]) {
      testWidgets('no overflow @ ${device.name} x$scale${bold ? ' bold' : ''}',
          (tester) async {
        tester.useDevice(device);
        await tester.pumpApp(textScaler: TextScaler.linear(scale), boldText: bold);
        // Explicit for a readable message; the binding also rethrows at test end.
        expect(tester.takeException(), isNull,
            reason: 'content overflowed at ${device.name} x$scale');
      });
    }
  }
}
```

The fit assertion is the real gate — it catches the *silent* class a clipped
`Text` never reports. See `references/overflow-and-textscale.md` and
`examples/overflow_matrix_test.dart`.

## The accessibility gate

Semantics is ON by default in `testWidgets`. Assert the node's role and label
directly with `isSemantics` (not the deprecated `containsSemantics`), measure tap
targets with an explicit `getSize` loop (the built-in guideline skips every node
flush with the view edge), and assert contrast on colour values in pure Dart.

```dart
testWidgets('each item exposes a button labelled by its display name',
    (tester) async {
  await tester.pumpApp();
  final node = tester.getSemantics(find.byKey(const ValueKey('item_0')));
  expect(node, isSemantics(
    label: 'First item',
    isButton: true,
    hasEnabledState: true,
    isEnabled: true,
    hasTapAction: true,
  ));
});
```

Be honest: Flutter ships **four** machine-checkable guidelines (one known-broken),
covering a small minority of real accessibility. Never claim a suite "tests
accessibility". Switch Access / Switch Control cannot be tested automatically at
all. See `references/a11y-guidelines-and-limits.md` and `examples/a11y_test.dart`.

## Golden lanes

Layout is proven by computed geometry, so goldens are narrow: glyph shaping,
mirroring, and numeral rendering that geometry cannot see. Two lanes, both call
`loadAppFonts()`; RTL goldens pump under `Directionality`. See
`references/golden-two-lanes.md`.

```dart
@Tags(['golden'])
library;

testWidgets('card mirrors correctly in RTL', (tester) async {
  await tester.pumpWidget(const Directionality(
    textDirection: TextDirection.rtl,
    child: _CardHarness(),
  ));
  await expectLater(find.byType(ItemCard),
      matchesGoldenFile('goldens/item_card_rtl.png'));
});
```

## Anti-patterns

- **Unpinned layout test.** Passes on 800x600, ships a broken 360dp phone. Rule 1.
- **`for` loop over scales inside one `testWidgets`.** Overflow reports once per
  RenderObject; scales 2..n are silently unchecked. Rule 6.
- **`takeException()` in a global `tearDown`.** Clears `_pendingExceptionDetails`
  before the binding rethrows — turns the entire overflow net into a no-op.
- **`ignoreOverflowErrors` / `FlutterError.onError = ...` in a layout test.** The
  popular helper that loses the net that already exists.
- **`FittedBox` / `TextOverflow.ellipsis` / `withClampedTextScaling` to green a
  red matrix.** Makes the most complex label the smallest, cancels the user's
  TextScaler, and passes while the product is unreadable. Fix the layout.
- **`expect(tester, meetsGuideline(...))` without `await expectLater`.** Asserts
  nothing — the matcher is async.
- **Tap-target claim resting on `meetsGuideline` alone.** It skips every node
  flush with the view edge; add the explicit `getSize` loop.
- **Contrast claim resting on `textContrastGuideline`.** Open false-negative on
  low-variance backgrounds; assert the colour ratio in pure Dart.
- **`find.byType(SomeWidget)` for behaviour or geometry.** Couples the test to the
  class hierarchy; a rename reds the suite for nothing. Use `find.bySemanticsLabel`
  for behaviour, `find.byKey` for geometry.
- **A layout golden as the gate.** It blesses whatever shipped, including clipped
  text, and reds on any host that rasterizes fonts differently.

## Definition of done

- Every layout/geometry test — and any a11y test that measures size or position —
  calls `useDevice(...)` before `pumpApp(...)`. Pure-semantics tests (role/label,
  traversal) need no device.
- Overflow matrix exists as one `testWidgets` per (device, scale, bold) tuple; no
  suppression anywhere in `test/`.
- A fit assertion (`getSize`/`getRect` inside the computed cell) backs the
  overflow matrix; a geometry invariant replaces the layout golden.
- Tap targets measured with an explicit `getSize` loop; `meetsGuideline` used only
  as advisory, always via `await expectLater`.
- Semantics asserted with `isSemantics`; label carries the display name, not
  internal data; traversal order asserted if it is a deliberate design decision.
- Contrast asserted in pure Dart (WCAG + APCA) over theme colour values, looped
  over every theme; chroma-only state pairs assert `wcag` between the two state
  colours directly.
- Goldens (if any) are tagged `@Tags(['golden'])`, both lanes call `loadAppFonts`,
  RTL goldens exist, and CI blocks `--update-goldens`.
- `scripts/check-test-hygiene.sh` passes.

## Related skills

- See `testing-strategy` for the overall test doctrine (pure clock-injected core,
  fakes-over-mocks, real in-memory DB, coverage policy) this widget tier sits on.
- See `accessibility-as-code` for authoring the Semantics/roles/labels these tests
  assert, and `i18n-rtl-l10n` for the Directional geometry the RTL goldens verify.
- See `design-system-structure` for the theme/ColorScheme the pure-Dart contrast
  gate reads, and `flutter-performance` for the const/rebuild rules layout tests
  should not try to re-prove.
- See `state-management-riverpod` for the `ProviderScope`/override seam `pumpApp`
  uses, and `ci-pipeline-and-gates` for wiring the golden lanes and greps into CI.
- See `run-goldens-rebaseline` for the one sanctioned ritual that overwrites
  committed golden images, and `ui-states-and-feedback` for the four screen states
  each golden and widget test pumps.

## References

- Flutter — Widget testing introduction: https://docs.flutter.dev/cookbook/testing/widget/introduction
- Flutter API — `matchesGoldenFile` (OS/font/version sensitivity, `--update-goldens`): https://api.flutter.dev/flutter/flutter_test/matchesGoldenFile.html
- Flutter API — `WidgetTester` / `TestFlutterView`: https://api.flutter.dev/flutter/flutter_test/WidgetTester-class.html
- Flutter — Accessibility guidelines / `meetsGuideline`: https://api.flutter.dev/flutter/flutter_test/AccessibilityGuideline-class.html
- Flutter — Semantics matchers (`isSemantics`, `matchesSemantics`): https://api.flutter.dev/flutter/flutter_test/matchesSemantics.html
- `alchemist` — golden testing (`loadAppFonts`, CI vs platform lanes): https://pub.dev/packages/alchemist
- WCAG 2.2 contrast (1.4.3 / 1.4.6) and APCA: https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html
