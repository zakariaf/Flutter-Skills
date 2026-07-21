// Demonstrates the overflow-and-fit net: ONE testWidgets per (device, scale, bold)
// tuple (because RenderFlex overflow is reported once per RenderObject), a fit
// assertion that catches the SILENT class a clipped Text never reports, a getRect
// geometry invariant that replaces a layout golden, and the anti-clamp check no
// guideline catches. No suppression anywhere.
//
// Put this under test/ui/. It imports the harness from examples/harness.dart in
// this skill; in a real app it is test/support/harness.dart.

import 'package:alchemist/alchemist.dart'; // loadAppFonts
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

// A neutral fixture: a grid of items keyed by id, each showing a display name.
class _Item {
  const _Item(this.id, this.name);
  final String id;
  final String name;
}

const List<_Item> kTestItems = <_Item>[
  _Item('0', 'First item'),
  _Item('1', 'Second item'),
  _Item('2', 'A rather longer third item name'),
];

// Read the real inset from the app's theme/tokens; hardcoded here only for the
// example. NEVER treat this as a design value to prescribe.
const double kCellInset = 12.0;

int _linesOf(WidgetTester tester, Finder text) => tester
    .renderObject<RenderParagraph>(text)
    .computeLineMetrics()
    .length;

void main() {
  // Load real proportional fonts BEFORE any test. Without this the whole suite
  // runs in Ahem, where every glyph is a weight-independent em-square: boldText
  // would lay out identically to non-bold (the bold axis becomes a no-op) and real
  // character widths are hidden. loadAppFonts() is what makes the bold half count.
  setUpAll(loadAppFonts);

  // 1. THE OVERFLOW MATRIX — one testWidgets per tuple; the loop is OUTSIDE.
  for (final Device device in Device.all) {
    for (final double scale in const <double>[1.0, 1.3, 1.5, 2.0, 3.0]) {
      for (final bool bold in const <bool>[false, true]) {
        testWidgets(
          'no overflow @ ${device.name} x$scale${bold ? ' bold' : ''}',
          (WidgetTester tester) async {
            tester.useDevice(device);
            await tester.pumpApp(
              textScaler: TextScaler.linear(scale),
              boldText: bold,
            );
            // The binding rethrows at test end; this is explicit for a readable
            // message and to document that suppression is banned.
            expect(
              tester.takeException(),
              isNull,
              reason: 'content overflowed at ${device.name} x$scale',
            );
          },
        );
      }
    }
  }

  // 2. THE FIT ASSERTION — the real gate. A clipped Text produces no exception,
  //    so absence of overflow is necessary but not sufficient.
  for (final double scale in const <double>[1.0, 1.3, 1.5, 2.0, 3.0]) {
    testWidgets('every item label fits its cell @ x$scale',
        (WidgetTester tester) async {
      tester.useDevice(Device.small); // the tightest shipped layout
      await tester.pumpApp(textScaler: TextScaler.linear(scale));
      expect(tester.takeException(), isNull); // the loud class first

      for (final _Item item in kTestItems) {
        final Rect cell =
            tester.getRect(find.byKey(ValueKey<String>('item_${item.id}')));
        final Finder label = find.text(item.name);
        final Size text = tester.getSize(label);

        expect(
          text.height,
          lessThanOrEqualTo(cell.height - kCellInset * 2),
          reason: '"${item.name}" needs ${text.height}dp inside a '
              '${cell.height}dp cell at x$scale — it is clipped silently',
        );
        expect(text.width, lessThanOrEqualTo(cell.width - kCellInset * 2));
        expect(_linesOf(tester, label), lessThanOrEqualTo(3),
            reason: '"${item.name}" wrapped past its line ceiling at x$scale');
      }
    });
  }

  // 3. GEOMETRY INVARIANT — replaces a layout golden, and names which cell moved.
  testWidgets('a row shares a top edge and a column shares a left edge @ 2.0x',
      (WidgetTester tester) async {
    tester.useDevice(Device.small);
    await tester.pumpApp(textScaler: const TextScaler.linear(2.0));

    final Rect c00 = tester.getRect(find.byKey(const ValueKey<String>('cell_0_0')));
    final Rect c01 = tester.getRect(find.byKey(const ValueKey<String>('cell_0_1')));
    final Rect c10 = tester.getRect(find.byKey(const ValueKey<String>('cell_1_0')));

    expect(c01.top, moreOrLessEquals(c00.top, epsilon: 0.5)); // same row
    expect(c10.left, moreOrLessEquals(c00.left, epsilon: 0.5)); // same column
  });

  // 4. ANTI-CLAMP — no guideline catches this; contrast and tap-target stay green
  //    while the text quietly stops growing.
  testWidgets('text scale is honored, never clamped', (WidgetTester tester) async {
    tester.useDevice(Device.small);

    await tester.pumpApp();
    final double base = tester.getSize(find.text('First item')).height;

    await tester.pumpApp(textScaler: const TextScaler.linear(2.0));
    final double scaled = tester.getSize(find.text('First item')).height;

    // 1.8, not 2.0: tolerate line-height rounding, still fail hard on a clamp.
    expect(scaled, greaterThan(base * 1.8),
        reason: 'Text did not grow at 2.0x — someone clamped TextScaler.');
  });
}
