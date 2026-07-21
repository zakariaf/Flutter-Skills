# Overflow and text-scale testing

Users at 200%+ text are a supported audience, not an edge case. The scale matrix
is what stands between them and content that is clipped where it cannot be read.

## Two overflow classes — one loud, one silent

**Loud: a `RenderFlex` overflow already FAILS a widget test.** It is not merely a
yellow-black banner and a log line. `DebugOverflowIndicatorMixin` calls
`FlutterError.reportError`; `TestWidgetsFlutterBinding` captures it; `testWidgets`
rethrows at test end unless something clears it. The entire blog genre on this
topic is about how to **suppress** it. So the rule inverts from intuition: the job
is not to *make* overflow fail, it is to **never lose the net that already exists**.

> Never `takeException()` to swallow. Never assign `FlutterError.onError` in a
> layout test. Never copy the popular `ignoreOverflowErrors` helper. Never
> `takeException()` in a global `tearDown` — it clears the pending exception
> before `testWidgets` rethrows, silently converting the whole suite's overflow
> net into a no-op.

**Silent: a clipped `Text` reports nothing, ever.** `RenderParagraph` has no
overflow indicator. A label that runs past a fixed height inside a `SizedBox` +
clip produces zero errors, a green test, and unreadable words on a real phone.
Only a `Flex` child reports. This is why `takeException(), isNull` is necessary
and **not sufficient**, and why the fit assertion below is the real gate.

## Three traps that make an overflow suite pass while checking nothing

1. **The 800x600 default surface.** Wider than any phone. Unpinned, content comes
   out ~2x too wide, text fits, the suite is green, and the shipped 360dp phone is
   broken. Pin a `Device` in every layout test.
2. **Overflow is reported ONCE per `RenderObject`.** The internal
   `_overflowReportNeeded` flag goes false after the first report and resets only
   on `reassemble()`. Looping scales inside one `testWidgets` silently
   under-reports scales 2..n. → **Generate one `testWidgets` per tuple.** Loop
   *around* the `testWidgets` call, never inside it.
3. **It only reports if the widget PAINTS.** `Offstage` subtrees and content
   scrolled outside a viewport never report. (Clipped content *does* still
   report — `RenderFlex` paints its indicator after pushing its own clip.) So a
   screen behind a tab, a collapsed sheet, or an alternate mode needs its **own
   pumped test** — the default screen's test will never reach it.

## The matrix

`Device.all` x `[1.0, 1.3, 1.5, 2.0, 3.0]` x `[false, true]` bold. Three devices x
five scales x two bold = 30 tests; each pumps one frame, so the cost is nothing and
the coverage is the product.

The matrix **must `loadAppFonts()`** or half of it is inert: under the default Ahem
test font every glyph is a fixed em-square with no bold variant, so `boldText:true`
lays out identically to `boldText:false` and character-width differences vanish. Load
a real proportional font once and the bold axis — and real advance widths — become
live.

```dart
setUpAll(loadAppFonts); // real fonts; without this the bold axis is a no-op

for (final device in Device.all) {
  for (final scale in const <double>[1.0, 1.3, 1.5, 2.0, 3.0]) {
    for (final bold in const <bool>[false, true]) {
      testWidgets('no overflow @ ${device.name} x$scale${bold ? ' bold' : ''}',
          (tester) async {
        tester.useDevice(device);
        await tester.pumpApp(textScaler: TextScaler.linear(scale), boldText: bold);
        expect(tester.takeException(), isNull,
            reason: 'content overflowed at ${device.name} x$scale');
      });
    }
  }
}
```

`TextScaler.linear` is a deliberate over-approximation: Android 14+ scales large
text *less* than small, so linear stresses large labels harder than a device would
— wanted conservatism, but do not claim these tests are device-faithful. `1.3` and
`1.5` are in the list because nonlinear device scaling makes the mid-range the
non-obvious part; `3.0` is Larger-Accessibility-Sizes / iOS AX5 territory.
`boldText` widens advance widths and overflows content that passes unbolded — one
bool in the tuple. It only bites once `loadAppFonts()` has loaded a real
proportional font (above); under Ahem it is metrically inert, so do not treat the
bold half of an unloaded matrix as coverage.

## The fit assertion — the real constraint

Assert that the label actually fits inside its computed cell, at every scale. This
catches the *silent* class the overflow net cannot see.

```dart
int linesOf(WidgetTester tester, Finder text) => tester
    .renderObject<RenderParagraph>(text)
    .computeLineMetrics()
    .length;

for (final scale in const <double>[1.0, 1.3, 1.5, 2.0, 3.0]) {
  testWidgets('every item label fits its cell @ x$scale', (tester) async {
    tester.useDevice(Device.small); // the tightest shipped layout
    await tester.pumpApp(textScaler: TextScaler.linear(scale));
    expect(tester.takeException(), isNull); // the loud class

    for (final item in kTestItems) {
      final cell = tester.getRect(find.byKey(ValueKey('item_${item.id}')));
      final label = find.text(item.name);
      final text = tester.getSize(label);

      // Inset is symmetric padding on every side (read the real value from the
      // theme/tokens — do not hardcode a design number here).
      expect(text.height, lessThanOrEqualTo(cell.height - kCellInset * 2),
          reason: '"${item.name}" needs ${text.height}dp inside a '
              '${cell.height}dp cell at x$scale — it is being clipped silently');
      expect(text.width, lessThanOrEqualTo(cell.width - kCellInset * 2));
      expect(linesOf(tester, label), lessThanOrEqualTo(3),
          reason: '"${item.name}" wrapped past its line ceiling at x$scale');
    }
  });
}
```

## Geometry invariants replace the layout golden

Pin the layout with computed edges, not blessed pixels. These fail with a sentence
naming which cell moved.

```dart
testWidgets('a row shares a top edge and a column shares a left edge @ 2.0x',
    (tester) async {
  tester.useDevice(Device.small);
  await tester.pumpApp(textScaler: const TextScaler.linear(2.0));

  final r0c0 = tester.getRect(find.byKey(const ValueKey('cell_0_0')));
  final r0c1 = tester.getRect(find.byKey(const ValueKey('cell_0_1')));
  final r1c0 = tester.getRect(find.byKey(const ValueKey('cell_1_0')));

  expect(r0c1.top, moreOrLessEquals(r0c0.top, epsilon: 0.5));  // same row
  expect(r1c0.left, moreOrLessEquals(r0c0.left, epsilon: 0.5)); // same column
});
```

## The anti-clamp behavioural check

The grep catches the named API; this catches a clamp built by hand. No guideline
catches it — contrast and tap-target both stay green while the text stops growing.

```dart
testWidgets('text scale is honored, never clamped', (tester) async {
  tester.useDevice(Device.small);
  await tester.pumpApp();
  final base = tester.getSize(find.text('First item')).height;

  await tester.pumpApp(textScaler: const TextScaler.linear(2.0));
  final scaled = tester.getSize(find.text('First item')).height;

  // 1.8, not 2.0: tolerate line-height rounding, still fail hard on a clamp.
  expect(scaled, greaterThan(base * 1.8),
      reason: 'Text did not grow at 2.0x — someone clamped TextScaler.');
});
```

## Fixing a red matrix — the four wrong fixes

Each turns the test green and the product worse. The correct fix is always the
layout, the copy, or a layout *setting*.

| Reach for | Why it is banned |
|---|---|
| `MediaQuery.withClampedTextScaling`, `textScaleFactor` | Defeats the entire matrix while contrast and tap-target still pass green, and overrides the user's own OS setting — the setting they need. |
| `FittedBox`, any auto-shrink | Backwards: makes the **longest** (most complex) string the **smallest**, destroys uniform rhythm, and silently cancels the user's TextScaler. |
| `TextOverflow.ellipsis`, `maxLines` truncation | Hides the failure instead of fixing it; a truncated label is a different label. If content is genuinely unbounded, make the region **scroll** and assert that. |
| A smaller font on the offending element | One uniform size is usually load-bearing; variable line count reads fine, variable size reads as broken. |

Legitimate resolutions: shorten the copy, add a hand-set line break, adjust the
shared component's role, make the region scrollable past a threshold, or accept a
denser layout variant — and run the matrix against **both** variants, never the
roomy one alone with the dense one treated as an untested escape hatch.

## Make the ban structural

No lint covers any of this. Pin it with `scripts/check-test-hygiene.sh` (greps
`lib/` for clamps and `test/` for suppression) so a single hit fails CI, not a
2am reviewer's attention.
