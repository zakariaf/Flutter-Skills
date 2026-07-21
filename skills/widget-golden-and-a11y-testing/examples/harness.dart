// Demonstrates the one widget-test harness: a Device value type that pins
// tester.view.physicalSize x devicePixelRatio, and a pumpApp extension that layers
// MediaQuery ABOVE MaterialApp (built from copyWith so pinned geometry survives),
// drives the accessibility axes, and takes ProviderScope overrides for its seams.
//
// Put this at test/support/harness.dart. Tests import it and nothing else of their
// own. `App`, the providers, and the fakes below stand in for the real ones.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

// import 'package:my_app/app.dart';        // the real root widget
// import 'package:my_app/providers.dart';  // itemsProvider, actionQueueProvider, ...

/// A test surface described in LOGICAL size + DPR. `view.physicalSize` is in
/// PHYSICAL pixels, so it must be multiplied by the DPR — `Size(320, 640)` at the
/// default DPR of 3.0 is a 107x213 logical surface, not a phone.
///
/// Presets are named by their measured size, not a marketing model.
class Device {
  const Device(this.name, this.logicalSize, this.dpr);

  final String name;
  final Size logicalSize;
  final double dpr;

  static const compact = Device('compact_320', Size(320, 640), 2.0);
  static const small = Device('small_360', Size(360, 800), 3.0);
  static const medium = Device('medium_412', Size(412, 915), 2.625);

  /// The matrix iterates this list — the tightest surface plus a couple of
  /// common ones. Add a tablet width only if the app ships a distinct layout.
  static const all = <Device>[compact, small, medium];

  @override
  String toString() => name;
}

extension TestHarness on WidgetTester {
  /// Pin the surface. Call BEFORE pumpApp, and always in this pair — a leaked
  /// view size poisons every later test in the file.
  void useDevice(Device d) {
    view.devicePixelRatio = d.dpr;
    view.physicalSize = d.logicalSize * d.dpr;
    addTearDown(view.reset); // one call; prefer over resetPhysicalSize/resetDPR
  }

  /// Pump the app under a pinned MediaQuery and a ProviderScope.
  ///
  /// Four things here are load-bearing:
  ///  * MediaQuery is ABOVE MaterialApp (MaterialApp inserts none of its own, so
  ///    this is the nearest ancestor and wins).
  ///  * it is built from `MediaQuery.of(context).copyWith(...)`, NOT a bare
  ///    `MediaQueryData()`, which would zero the size useDevice just pinned.
  ///  * seams are supplied through `overrides`, not constructed live.
  ///  * a single `pump()` — never `pumpAndSettle()`.
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
          builder: (BuildContext context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: textScaler,
              boldText: boldText,
              accessibleNavigation: accessibleNavigation,
            ),
            child: const _AppUnderTest(),
          ),
        ),
      ),
    );
    await pump();
  }
}

// --- Stand-ins so this file is self-contained; delete and import the real ones. -

class _AppUnderTest extends StatelessWidget {
  const _AppUnderTest();

  @override
  Widget build(BuildContext context) {
    // In a real app: `return const App();`
    return const MaterialApp(home: Scaffold(body: SizedBox.shrink()));
  }
}

/// A fake that records what it was told to do, so a test can assert on the
/// EFFECT (which id was enqueued) rather than merely that a method was called.
class FakeActionQueue {
  final List<String> enqueued = <String>[];
  void enqueue(String id) => enqueued.add(id);
}
