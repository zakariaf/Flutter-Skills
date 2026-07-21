// Demonstrates one complete side-effect boundary: a value-typed interface returning a
// typed outcome, a throwing provider (Riverpod IS the DI), the one live impl, a
// hand-written contract-honouring fake, and a headless test. Also shows the injected
// clock and the void-returning handler that closes the arrow-callback Future-drop hole.
//
// Neutral domain: an AnalyticsService (logs an event) and the injected Clock (reads "now").
// Everything except flutter_riverpod/clock resolves inside a real app; opened alone it shows
// unresolved-import errors, which is expected.

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// 1. THE INTERFACE + TYPED OUTCOME — value types only, no plugin symbol.
// ---------------------------------------------------------------------------

sealed class LogResult {
  const LogResult();
}

final class Logged extends LogResult {
  const Logged();
}

final class LogDropped extends LogResult {
  const LogDropped(this.code); // a STABLE code, never a localized string
  final String code;
}

/// Records product analytics events. The concrete vendor SDK lives behind this
/// seam; features depend on this interface, never on the SDK.
abstract interface class AnalyticsService {
  /// Records [name] with [params]. A dropped event (offline queue full, consent
  /// withheld) is ordinary control flow, not a thrown-and-swallowed exception.
  Future<LogResult> log(String name, {Map<String, Object?> params});
}

// ---------------------------------------------------------------------------
// 2. THE PROVIDERS — the SDK-backed port is a thin throwing wire (read un-overridden
//    -> loud startup failure). The clock is the ONE boundary that safely self-defaults:
//    `Clock` from package:clock opens no I/O, so const Clock() is a fine default; tests
//    override with Clock.fixed(...). No bespoke ClockService/SystemClock.
// ---------------------------------------------------------------------------

final analyticsServiceProvider = Provider<AnalyticsService>(
  (ref) => throw UnimplementedError('override analyticsServiceProvider in main.dart'),
);

final clockProvider = Provider<Clock>((ref) => const Clock());

// ---------------------------------------------------------------------------
// 3. THE LIVE IMPL — the ONLY place the real SDK is touched.
//    Constructed only at the composition root (see main() below).
// ---------------------------------------------------------------------------

/// Stand-in for a vendor-backed impl. In a real app this would
/// `import 'package:some_vendor_sdk/...'` and check every return code by hand.
final class VendorAnalytics implements AnalyticsService {
  const VendorAnalytics();
  @override
  Future<LogResult> log(String name, {Map<String, Object?> params = const {}}) async {
    // ... real SDK call, timeout guard, PlatformException -> LogDropped('...') ...
    return const Logged();
  }
}

// ---------------------------------------------------------------------------
// 4. THE COMPOSITION ROOT — one live impl per interface, only here.
// ---------------------------------------------------------------------------

void bootstrap() {
  runApp(ProviderScope(
    overrides: [
      analyticsServiceProvider.overrideWithValue(const VendorAnalytics()),
      // clockProvider self-defaults to const Clock() — no override needed outside tests.
    ],
    child: const _AppPlaceholder(),
  ));
}

// ---------------------------------------------------------------------------
// 5. A VOID-RETURNING HANDLER — closes the Future-drop hole by construction.
//    A fire-and-forget side effect (analytics) must never block or crash the UI.
// ---------------------------------------------------------------------------

final class AnalyticsController {
  AnalyticsController(this._ref);
  final Ref _ref;

  /// Returns void ON PURPOSE. The callback holds no Future, so nothing can be
  /// dropped. Do not "fix" this into Future<void>.
  void track(String name) {
    final clock = _ref.read(clockProvider);
    final service = _ref.read(analyticsServiceProvider);
    unawaited(
      service.log(name, params: {'at': clock.now().toIso8601String()}).then((result) {
        switch (result) {
          case Logged():
            return;
          case LogDropped():
          // feature layer decides what to do with a stable code (usually nothing)
        }
      }).catchError((Object _) {/* analytics must never surface to the user */}),
    );
  }
}

/// The controller is itself wired behind a provider — the `Ref` it needs is the
/// provider's own `ref`, and tests read it from the container (a ProviderContainer
/// is NOT a Ref, so never construct the controller with one directly).
final analyticsControllerProvider =
    Provider<AnalyticsController>((ref) => AnalyticsController(ref));

// ---------------------------------------------------------------------------
// 6. THE FAKE — hand-written, `implements`, failure path reachable.
// ---------------------------------------------------------------------------

final class FakeAnalytics implements AnalyticsService {
  FakeAnalytics(this._next);
  final LogResult _next;
  final List<String> logged = [];
  factory FakeAnalytics.recording() => FakeAnalytics(const Logged());
  factory FakeAnalytics.dropping() => FakeAnalytics(const LogDropped('offline'));

  @override
  Future<LogResult> log(String name, {Map<String, Object?> params = const {}}) async {
    logged.add(name);
    return _next; // resolves instantly; failure path reachable via .dropping()
  }
}

// The clock needs no hand-written fake — package:clock supplies Clock.fixed(...)
// (and withClock for pure code).

// ---------------------------------------------------------------------------
// 7. A HEADLESS TEST — no emulator, no network, no real SDK.
//    (Illustrative; real tests live under test/.)
// ---------------------------------------------------------------------------

void exampleTest() {
  final container = ProviderContainer.test(overrides: [
    analyticsServiceProvider.overrideWithValue(FakeAnalytics.recording()),
    clockProvider.overrideWithValue(Clock.fixed(DateTime.utc(2026, 7, 21))),
  ]);
  container.read(analyticsControllerProvider).track('item_opened');
  // assert against the fake's recorded state — deterministic time, no wall clock.
}

// --- placeholders so this file reads coherently in isolation ---
void runApp(Object widget) {}

final class _AppPlaceholder {
  const _AppPlaceholder();
}
