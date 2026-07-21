// Demonstrates the accessibility gate: assert the SemanticsNode directly with
// isSemantics (role + label, and that the label does NOT leak internal data),
// measure tap targets with an explicit getSize loop (meetsGuideline skips edge
// nodes), assert deliberate traversal order, and keep the four built-in guidelines
// only as advisory tripwires via `await expectLater`. The pure-Dart contrast test
// is a SEPARATE file (see below) because the built-in contrast guideline
// false-passes on low-variance backgrounds.

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

class _Item {
  const _Item(this.id, this.name, this.priority);
  final String id;
  final String name;
  final int priority;
}

const List<_Item> kTestItems = <_Item>[
  _Item('0', 'First item', 2),
  _Item('1', 'Second item', 0),
  _Item('2', 'Third item', 1),
];

// The order a screen reader should visit, if traversal is a design decision.
final List<_Item> kByPriority = <_Item>[...kTestItems]
  ..sort((a, b) => a.priority.compareTo(b.priority));

void main() {
  // (1) ROLE + LABEL — the check no guideline makes well.
  testWidgets('each item is a button labelled by its display name',
      (WidgetTester tester) async {
    await tester.pumpApp();

    for (final _Item item in kTestItems) {
      final SemanticsNode node =
          tester.getSemantics(find.byKey(ValueKey<String>('item_${item.id}')));

      // isSemantics — NOT containsSemantics, which is deprecated.
      expect(
        node,
        isSemantics(
          label: item.name,
          isButton: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasTapAction: true,
        ),
      );

      // The label must not leak internal ids/data.
      expect(node.label, isNot(contains(item.id)),
          reason: 'item "${item.name}" leaks its id into the semantic label');
    }
  });

  // (2) TAP TARGET — explicit geometry, because meetsGuideline skips edge nodes.
  testWidgets('every item is >= 48x48 dp at 200% on the smallest phone',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(textScaler: const TextScaler.linear(2.0));

    for (final _Item item in kTestItems) {
      final Size size =
          tester.getSize(find.byKey(ValueKey<String>('item_${item.id}')));
      expect(size.width, greaterThanOrEqualTo(48.0),
          reason: '"${item.name}" is ${size.width}dp wide; minimum is 48dp');
      expect(size.height, greaterThanOrEqualTo(48.0));
    }
  });

  // (3) TRAVERSAL ORDER — only assert if it is a deliberate design decision.
  testWidgets('the screen reader visits items in priority order',
      (WidgetTester tester) async {
    await tester.pumpApp();

    // startNode:/endNode: — start:/end: are deprecated.
    final Iterable<SemanticsNode> ordered =
        tester.semantics.simulatedAccessibilityTraversal(
      startNode: find.semantics.byLabel(kByPriority.first.name),
      endNode: find.semantics.byLabel(kByPriority.last.name),
    );

    expect(
      ordered.map((SemanticsNode n) => n.label).toList(),
      kByPriority.map((_Item i) => i.name).toList(),
      reason: 'traversal order changed — someone dropped the sortKey',
    );
  });

  // (4) ADVISORY tripwire — never the gate. `await expectLater`, because
  //     meetsGuideline returns an AsyncMatcher.
  testWidgets('meets the built-in guidelines (advisory)',
      (WidgetTester tester) async {
    tester.useDevice(Device.compact);
    await tester.pumpApp(
      textScaler: const TextScaler.linear(2.0),
      accessibleNavigation: true,
    );

    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
  });
}

// ---------------------------------------------------------------------------
// CONTRAST — belongs in its OWN pure-Dart file (test/ui/contrast_test.dart) run
// with package:test, no widget tree. Asserts on colour VALUES, never pixels, so
// it cannot false-pass the way meetsGuideline(textContrastGuideline) does.

double contrastRatio(Color fg, Color bg) {
  final double a = fg.computeLuminance();
  final double b = bg.computeLuminance();
  return (math.max(a, b) + 0.05) / (math.min(a, b) + 0.05);
}

/// A chroma-only state — selected at (near-)equal luminance to its background —
/// is invisible to a grayscale-mode user. There is NO independent "grayscale
/// channel" to add: `computeLuminance()` is chroma-blind, so any correct grey of a
/// colour preserves its luminance exactly and `contrastRatio(gray(a), gray(b))`
/// equals `contrastRatio(a, b)` for all a, b — the gray() wrapper proves nothing.
/// Instead assert the LUMINANCE ratio between the two STATE colours directly; that
/// is exactly what survives grayscale. Pair with APCA (Lc) for a genuine
/// perceptual second channel that grayscale+WCAG cannot reproduce.
void expectStateIsNotChromaOnly(Color state, Color surface) {
  expect(contrastRatio(state, surface), greaterThanOrEqualTo(1.3),
      reason: 'state vs surface differ only in chroma; a grayscale-mode user '
          'sees no state change');
}
