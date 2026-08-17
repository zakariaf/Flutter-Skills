---
name: service-boundary-and-native
description: Wires every side effect and native channel as an injectable interface behind a Provider that throws UnimplementedError until the composition root overrides it, with one live impl per flavor, value-typed signatures returning typed results, hand-written contract-honouring fakes over mocks, MethodChannel quarantined to one lib/native/ directory, and versioned cross-language contracts edited on both sides in one commit. Use when adding or changing a ShareService/AnalyticsService/RemoteConfigService or any side-effect port, injecting a Clock (package:clock) via clockProvider, a MethodChannel/platform channel or native widget bridge, a flavor entrypoint (main_*.dart) or per-flavor provider override, a shared-file/JSON contract mirrored in Kotlin/Swift, replacing a stray DateTime.now() or direct SDK call inside a widget/notifier/repository, or wiring a fake via ProviderScope(overrides:) in tests.
---

# Service boundary and native

Every platform capability — reading "now", sharing, logging an event, fetching remote flags, calling a MethodChannel — crosses the app's layers as an **injected interface**. The interface names value types only; the concrete SDK lives in exactly one class; the composition root (`main`) wires one live impl; tests wire a deterministic fake. **Abstract exactly what cannot run in a test — nothing more.** This is the seam that keeps features pure, SDKs swappable, and the whole app testable headlessly.

Read the reference for the task at hand:
- `references/service-interface.md` — typed outcomes vs bool/throw, exhaustiveness, `@useResult`, hand-written env-fakes, the arrow-callback Future-drop hole, single write path.
- `references/native-channels.md` — MethodChannel placement, the cross-language contract ownership table, versioned-file-vs-`shared_preferences` traps, native-fast-path independence, the round-trip `integration_test`.
- `references/multi-flavor.md` — line-for-line composition roots, build flavors over runtime detection, per-flavor plugin pins, the banned-dependency CI graph gate.

Run `scripts/check-service-boundaries.sh` and `scripts/check-flavor-graph.sh` before a PR.

## Non-negotiable rules

1. **Every side effect is an injected interface, never a concrete SDK at the call site.** Features, Notifiers, and repositories depend on the *interface*; the app imports the real SDK in exactly one live-impl class. WHY: one seam to swap, one place to quarantine platform quirks, zero SDK reach into pure code.
2. **Abstract only what cannot run in `flutter test`.** One interface + one real impl + one fake = justified. One interface + one impl + no fake = delete the interface. WHY: interfaces "for symmetry" are dead weight that hide where the real risk (untestable I/O) is.
3. **Interface signatures reference value types only.** Name a `DateTime`, a domain value object, a sealed outcome — never a plugin type, never a `dart:io` symbol. WHY: keeps the interface nameable from any layer and the SDK confined to one class.
4. **Every method returns a typed result — failure is control flow, not a swallowed exception.** Model a cancel, an empty fetch, an unavailable target as a sealed outcome or `Result<T, F extends Failure>`, never a thrown-and-forgotten exception. WHY: Dart requires no `throws` declaration, so an unhandled failure silently vanishes. See `error-handling-typed-results` for the `Result`/`Failure` spine.
5. **The provider throws `UnimplementedError` until overridden — the provider IS the DI.** No `get_it`, no service locator, no second container, no business logic in the provider body. WHY: a forgotten wiring becomes a loud startup failure instead of silent null data or a live SDK opening at import.
6. **Wire exactly one live impl per interface at the composition root.** `main` (per flavor) is the *only* place a live SDK is constructed; `app.dart` and every widget below are wiring-blind. WHY: the composition root is the single seam where the real world is chosen.
7. **Tests install a hand-written fake that honours the contract — fakes over mocks.** The fake's failure path must be reachable; a fake that always succeeds is a happy-path lie. `implements` (not `extends`) so a new interface method breaks the build. WHY: a passing test must reflect real behaviour, including the failure it exists to guard.
8. **The clock is injected via `clockProvider` (a `Clock` from `package:clock`) — "now" has exactly one source.** No `DateTime.now()` / `math.Random()` reachable from a view, Notifier, repository, or pure core; feature code reads `ref.read(clockProvider).now()`, pure core takes a `Clock` or the ambient `clock`. Never a bespoke `ClockService`/`SystemClock`. WHY: this is what makes date/streak/expiry logic deterministic by overriding with `Clock.fixed(...)`. See `value-objects-money-and-units` for the injected `Clock`.
9. **A mutating service feeds the single write path — persist before publish.** A service that changes durable state is consumed by a repository method that commits (one transaction) before any state republishes. WHY: a crash mid-flow must never leave "acknowledged but not durable".
10. **Every MethodChannel lives under one `lib/native/` directory; nothing else creates one.** A channel born inside a widget, repository, or Notifier is a defect regardless of how well it works. WHY: platform channels are the least testable code in the app and must be found in one place.
11. **A cross-language shared format is a versioned contract with one owner per side, edited on both sides in the same commit, and proven by an `integration_test`.** WHY: no compiler, analyzer, or unit test catches a renamed key across the language boundary — only a real round-trip does.

## The interface and its provider (Riverpod DI)

The interface is small, value-typed, and returns a typed outcome. The provider is a thin throwing wire.

```dart
// lib/services/share_service.dart — value types only, no plugin symbol.
sealed class ShareResult { const ShareResult(); }
final class Shared extends ShareResult { const Shared(); }
final class ShareDismissed extends ShareResult { const ShareDismissed(); }
final class ShareUnavailable extends ShareResult {
  const ShareUnavailable(this.code); // a stable code, never a localized string
  final String code;
}

abstract interface class ShareService {
  Future<ShareResult> share(String text); // a dismiss/unavailable is data, not a throw
}
```

```dart
// lib/services/service_providers.dart — the Provider IS the DI. It throws until
// the composition root overrides it, so a forgotten wiring fails loudly at startup.
final shareServiceProvider = Provider<ShareService>(
  (ref) => throw UnimplementedError('override shareServiceProvider in main.dart'),
);
```

The canonical smallest boundary is time — read everywhere, `DateTime.now()` nowhere. The one time type is **`Clock` from `package:clock`**, injected via `clockProvider`. Unlike an SDK-backed port, the clock provider safely defaults to the real thing (`const Clock()` opens no I/O and reaches no SDK), so it needs no override to run; tests override it with `Clock.fixed(...)`. Do NOT define a bespoke `ClockService`/`SystemClock`.

```dart
import 'package:clock/clock.dart';

// The ONE time seam. Feature/Notifier code reads ref.watch(clockProvider).now();
// pure core takes a Clock param or uses the ambient `clock` (testable via withClock).
final clockProvider = Provider<Clock>((ref) => const Clock());
```

## One live impl at the composition root

`main` is the only place a live SDK is constructed. The concrete SDK import appears only inside the live-impl class.

```dart
// lib/main.dart — the composition root. app.dart below is wiring-blind.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ProviderScope(
    overrides: [
      shareServiceProvider.overrideWithValue(const OsShareService()), // the ONE live impl
      // clockProvider self-defaults to const Clock() — no override needed outside tests.
    ],
    child: const App(),
  ));
}
```

> **When multi-package (workspace):** the interface lives in a shared foundation package; the live impl and `main` live in the app package. In a single-package app all three are folders under `lib/`. See `project-structure-and-packages`.

> **When multi-flavor:** ship one thin `main_<flavor>.dart` per flavor over a single flavor-blind `app.dart`. Each `main` overrides the **same** provider list in the **same** order — only the impl on each right-hand side changes — so the two files diff line-for-line. Real build flavors (Android product flavors + iOS schemes), never runtime detection. See `references/multi-flavor.md`.

## Fakes over mocks

A hand-written fake that `implements` the interface and models the ways the world breaks. No mock framework; no codegen.

```dart
// lib/services/testing/fake_share_service.dart
final class FakeShareService implements ShareService {
  FakeShareService(this._next);
  final ShareResult _next;
  int calls = 0;
  factory FakeShareService.succeeding() => FakeShareService(const Shared());
  factory FakeShareService.unavailable() => FakeShareService(const ShareUnavailable('no_target'));

  @override
  Future<ShareResult> share(String text) async {
    calls++;
    return _next; // resolves instantly — no plugin, no OS sheet; failure path reachable
  }
}
```

The clock needs no hand-written fake — `package:clock` supplies `Clock.fixed(...)` (and `withClock` for pure code):

```dart
// test — no emulator, no network, no real SDK. ProviderContainer.test() auto-disposes.
test('sharing an unavailable target surfaces a code, never throws', () async {
  final container = ProviderContainer.test(overrides: [
    shareServiceProvider.overrideWithValue(FakeShareService.unavailable()),
    clockProvider.overrideWithValue(Clock.fixed(DateTime.utc(2026, 7, 21))),
  ]);
  final result = await container.read(shareServiceProvider).share('hello');
  expect(result, isA<ShareUnavailable>());
});
```

## The native boundary

A MethodChannel is quarantined to `lib/native/`, wrapped by a thin **`Gateway`**, and exposed through the same injectable-interface seam. (A `Gateway` names a thin wrapper over a specific plugin/SDK or a `MethodChannel`; a `Service` names a capability interface you define — see `naming-conventions`.) Keep the native side able to run without the Dart engine alive where latency demands it.

```dart
// lib/native/item_widget_bridge.dart — the ONLY MethodChannel owner for this feature.
class ItemWidgetBridge {
  static const _channel = MethodChannel('app/item_widget');
  Future<void> publish(Map<String, Object?>? contractJson) =>
      _channel.invokeMethod('publish', contractJson);
}

// lib/native/item_widget_contract.dart — SOLE Dart owner of the shared format.
// Mirror: android/.../ItemWidgetContract.kt  (edit BOTH files in the same commit).
const int kItemWidgetContractVersion = 1;
Map<String, Object?> itemToContractJson(String title, DateTime updatedAtUtc) => {
      'v': kItemWidgetContractVersion, // a versioned file we own, not shared_preferences
      'title': title,
      'updatedAtUtc': updatedAtUtc.toIso8601String(),
    };
```

Every write path that changes a mirrored value republishes as part of the write, never as a follow-up someone remembers — a delete/clear republishes exactly as hard as a save. See `references/native-channels.md` for the ownership table, the `shared_preferences` traps, and the round-trip test that proves the mirror.

## Anti-patterns

- **Calling a plugin/SDK from a feature, Notifier, or repository.** The real SDK is imported only inside its live impl — never in a widget, controller, or repository body.
- **`DateTime.now()` / `math.Random()` reachable from a view, Notifier, repository, or pure core.** "Now" has one source, the injected clock; anything else defeats deterministic time tests.
- **A provider that defaults to a live service** instead of throwing — it hides a missing override and can open real I/O at import.
- **Reaching for a mock framework to fake a boundary**, or a fake that always succeeds so the failure path is never exercised.
- **`onTap: () => service.doThing()`** — the arrow closure returns the `Future` into a `VoidCallback`, so the Future *and its error* are dropped and **no lint catches it**. Route through a `void`-returning handler that `unawaited(...)`s with a `catchError`. See `references/service-interface.md`.
- **A MethodChannel created outside `lib/native/`**, or renaming a contract key on one side of the language boundary without the other in the same commit.
- **Business logic inside the provider**, or a second DI container (`get_it`, `package:provider`) alongside Riverpod.
- **User-facing copy inside a service.** The boundary returns a typed failure with a stable code; the feature layer maps it to localized copy.
- **A `#if FLAVOR` / `String.fromEnvironment('FLAVOR')` fork inside feature code**, or a binary that detects its ecosystem and swaps SDKs at runtime — flavors diverge only at the composition root.

## Definition of done

- [ ] The boundary is an `abstract interface class`; its signatures reference value types only — no plugin type, no `dart:io` symbol.
- [ ] The interface exists only because it cannot run in a test (has a real impl AND a fake); no interface added "for symmetry".
- [ ] Every method returns a typed result (sealed outcome / `Result<T, F extends Failure>`); cancel/unavailable/empty are control flow, not thrown exceptions; a failure carries a stable code, never a localized string.
- [ ] The provider throws `UnimplementedError` until overridden; consumers `ref.watch`/`ref.read` it; no `get_it`, no second container, no logic in the provider.
- [ ] Exactly one live impl per interface is wired in `main` (per flavor); `app.dart` imports no concrete SDK; multi-flavor `main`s diff line-for-line.
- [ ] A hand-written fake `implements` the interface, honours the contract (failure path reachable), and is installed via `overrideWithValue` — no mock framework.
- [ ] No `DateTime.now()` / `math.Random()` is reachable from a view, Notifier, repository, or pure core; time enters only through the injected `Clock` (`clockProvider`), never a bespoke `ClockService`.
- [ ] A mutating service feeds the single write path — persist before publish.
- [ ] Every MethodChannel lives under `lib/native/`; the live impl is the only SDK importer; `scripts/check-service-boundaries.sh` is green.
- [ ] Any cross-language shared format is versioned, owned once per side, edited on both sides in the same commit, and covered by a round-trip `integration_test`.
- [ ] If flavors exist, the banned-dependency CI graph gate (`scripts/check-flavor-graph.sh`) proves each flavor links none of its forbidden SDKs.

## Related skills

- See `state-management-riverpod` for Notifier/AsyncNotifier discipline and the watch/read/listen split that consumes these providers.
- See `error-handling-typed-results` for the sealed `Result`/`Failure` spine every boundary method returns.
- See `async-safety` for the void-handler pattern that closes the arrow-callback Future-drop hole and the `mounted`/`BuildContext` guards.
- See `app-startup-and-bootstrap` for the composition-root ordering (error handlers, settings, DI overrides) that hosts these overrides.
- See `project-structure-and-packages` for where the interface, live impl, and `main` sit in a single-package vs workspace layout.
- See `dependency-hygiene` for vetting and pinning the plugin behind each live impl.
- See `testing-strategy` for fakes-over-mocks and the acceptance-gate posture.
- See `value-objects-money-and-units` for the injected `Clock` (`package:clock`) and canonical value types these signatures name.
- See `naming-conventions` for the `Service` (capability interface you define) vs `Gateway` (wrapper over a specific plugin/SDK or `MethodChannel`) suffix rule.
- See `ads-and-iap-monetization` for the policy that rides on the ads/billing boundaries — including why the entitlement must be restored before the ad SDK is initialized.
- See `data-export-and-restore` for the share/file-picker Gateway and its fake, and `release-and-store-shipping` for the permissions and store declarations each new plugin brings with it.

## Provider / ChangeNotifier appendix

The same rules hold with the official Flutter-guide stack; only the wiring mechanism changes. Rules 1–4, 7–11 are identical. The interface and typed outcome are unchanged.

- **DI is `package:provider` at the composition root, injecting the *interface*.** There is no throw-until-overridden idiom, so provide the real impl at the root and never construct an SDK below it:

```dart
void main() {
  runApp(MultiProvider(
    providers: [
      Provider<Clock>.value(value: const Clock()), // package:clock, not a bespoke ClockService
      Provider<ShareService>.value(value: const OsShareService()),
    ],
    child: const App(),
  ));
}
```

- **A ViewModel `ChangeNotifier` receives the interface by constructor, never reaches a global**, and exposes intent methods over immutable state:

```dart
final class ShareViewModel extends ChangeNotifier {
  ShareViewModel(this._share, this._clock);
  final ShareService _share;
  final Clock _clock;
  // intent method; keeps the single write path and the injected clock
}
```

- **Tests override by wrapping the widget in a `Provider<Interface>.value(value: FakeShareService...())`** (or passing the fake straight into the ViewModel constructor). Same hand-written fake, same failure-path coverage.
- **Do not mix `get_it`/`injectable` in as a second container.** One DI mechanism; the interface is the seam either way.

## References

- Flutter — [Guide to app architecture](https://docs.flutter.dev/app-architecture/guide) and [Architecture recommendations](https://docs.flutter.dev/app-architecture/recommendations) (dependency injection strongly recommended).
- Flutter — [Build flavors (Android)](https://docs.flutter.dev/deployment/flavors) and [iOS build flavors](https://docs.flutter.dev/deployment/flavors-ios).
- Flutter — [Writing custom platform-specific code (MethodChannel)](https://docs.flutter.dev/platform-integration/platform-channels).
- Riverpod — [Testing your providers](https://riverpod.dev/docs/essentials/testing) and [What's new in Riverpod 3.0](https://riverpod.dev/docs/whats_new).
- pub.dev — [`clock`](https://pub.dev/packages/clock) (the `Clock`/`withClock` time seam), [`provider`](https://pub.dev/packages/provider), [`mocktail`](https://pub.dev/packages/mocktail) (one-off stubs only), [`home_widget`](https://pub.dev/packages/home_widget) (data bridge only).
