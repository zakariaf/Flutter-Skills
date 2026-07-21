# Native channels and cross-language contracts

Deep-dive for MethodChannel placement, the shared-format contract, and the tests that can and cannot prove it.

## Every MethodChannel lives under `lib/native/`

A channel created inside a widget, repository, or Notifier is a defect regardless of how well it works. Platform channels are the least testable code in the app; keeping them in one directory means a reviewer can find every native touchpoint by listing one folder.

Wrap each channel in a thin **bridge** class (the only `MethodChannel(...)` construction), then expose the capability through the same injectable-interface seam so features stay channel-blind and testable:

```dart
// lib/native/item_widget_bridge.dart — the ONLY MethodChannel owner for this feature.
class ItemWidgetBridge {
  static const _channel = MethodChannel('app/item_widget');
  Future<void> publish(Map<String, Object?>? contractJson) =>
      _channel.invokeMethod('publish', contractJson);
}

// lib/services/widget_gateway.dart — the injectable port features depend on.
abstract interface class WidgetGateway {
  Future<void> publish(ItemSnapshot? snapshot);
}

// lib/native/native_widget_gateway.dart — the ONE live impl; bridges to the channel.
final class NativeWidgetGateway implements WidgetGateway {
  const NativeWidgetGateway(this._bridge);
  final ItemWidgetBridge _bridge;
  @override
  Future<void> publish(ItemSnapshot? s) => _bridge.publish(s?.toContractJson());
}
```

**Do not make the native feature a federated plugin** unless a third party will extend it. Federation buys a platform_interface, version lockstep, and a publishing story — in exchange for nothing when one team owns both sides.

## The delegate rule: keep the framework-lifecycled class too small to hold a bug

Native entry points lifecycled by the OS (an Android `TileService`/`BroadcastReceiver`, an iOS `AppIntent`/widget extension) are hard or impossible to unit-test. Keep the framework subclass to ~5 lines that immediately delegate to a plain class that IS unit-testable:

```kotlin
// WRONG — logic inside the OS-lifecycled class. Untestable anywhere.
override fun onReceive(context: Context, intent: Intent) {
  val json = File(...).readText()
  val title = JSONObject(json).getString("title")
  // ...business logic...
}

// RIGHT — delegate immediately. ItemWidgetRenderer is plain-JUnit testable with a fake IO.
override fun onReceive(context: Context, intent: Intent) = renderer.render(context)
```

Everything that can be wrong lives in the plain class; the subclass holds no logic. What only a real device can prove becomes a **manual-checklist step** — write the step, do not fake the test.

## The cross-language contract: one owner per side, edited together

A shared storage format read by both Dart and native code has **zero compiler enforcement**. It gets exactly one owner per side and no others:

| Side | Sole owner |
|---|---|
| Dart | `lib/native/item_widget_contract.dart` — the only writer of the contract file |
| Kotlin | `ItemWidgetContract.kt` — mirrors the Dart file **by hand** |
| Swift | `ItemWidgetContract.swift` — mirrors the Dart file **by hand** |

Rename a key on one side without the other and the native surface reads nothing — no compiler, no analyzer, no unit test, and (if the surface has no telemetry) no crash report catches it. **Any edit to one owner is an edit to all owners, in the same commit.**

## Use a versioned file you own — not `shared_preferences`

Two independent traps make the obvious choice wrong when native code must read what Dart wrote:

- `SharedPreferencesAsync` is backed by **Jetpack DataStore**, not `FlutterSharedPreferences.xml`; native `getSharedPreferences(...)` reads **nothing**.
- The legacy API prefixes every key with `flutter.`, so native `getString("title")` returns null — the real key is `flutter.title`.

Both failures are silent. An explicit file with a schema version sidesteps both, survives a `shared_preferences` major bump, and is readable by a stranger with `cat`:

```dart
// lib/native/item_widget_contract.dart — SOLE Dart owner.
const int kItemWidgetContractVersion = 1;

Map<String, Object?> itemToContractJson(String title, DateTime updatedAtUtc) => {
      'v': kItemWidgetContractVersion,
      'title': title,
      'updatedAtUtc': updatedAtUtc.toIso8601String(),
    };
```

Reject young "zero-native-code widget" packages for a shipping feature. Use a data-bridge package (e.g. `home_widget`) as a **data bridge only** — the widget UI is hand-written SwiftUI/WidgetKit or Jetpack Glance regardless — and never route a latency-critical path through its background-isolate/app-boot code paths.

## The mirror invariant: every write republishes

Every write path that can change a mirrored value republishes as **part of the write**, not a follow-up someone remembers. A delete or clear republishes exactly as hard as a save:

```dart
// WRONG — the mirror silently rots; the native surface shows a value the user retracted.
Future<void> clearItem(int id) => _db.clear(id);

// RIGHT — the mirror is part of the write.
Future<void> clearItem(int id) async {
  await _db.clear(id);
  await _widgetGateway.publish(null);
}
```

## The test that looks right and is worthless

`SharedPreferences.setMockInitialValues` is **in-memory only**. A Dart unit test asserting "edit → the stored value changed" asserts *a fake mutated a fake* — green while the native read path is broken. That is manufactured false confidence in exactly the silent failure it claims to guard.

```dart
// WRONG — a fake mutated a fake. Green while native reads nothing.
test('edit republishes', () async {
  SharedPreferences.setMockInitialValues({});
  await repo.setTitle('Hi');
  expect((await SharedPreferences.getInstance()).getString('title'), 'Hi');
});

// RIGHT — integration_test: write from Dart, read back through the real native path.
testWidgets('mirror round-trips through native', (tester) async { /* ... */ });
```

The mirror invariant requires an **`integration_test`** that writes from Dart and reads back through the real native path. Never accept a unit test in its place.

## Native fast paths stay independent of the Dart engine

If a native surface must be instant (reachable while the app process is dead), **it must not depend on the Dart side being alive** — no engine handle, no background isolate, no MethodChannel callback into Dart, no waiting on a Flutter-owned lock or database, and never a migration or DB-open on that path. It reads the shared file and acts in pure native code. This makes its latency a *native* code budget, and it means **no Flutter test of any level can reach it** — that is the accepted price, mitigated by the delegate rule and a manual checklist, not by faking a test.

Package-visibility / target-membership gotchas that produce a green simulator and a broken device:

- Android 11+ package visibility can hide a system service unless declared in a `<queries>` block in `AndroidManifest.xml`; the plugin then returns an empty result with only a log line. Assert the manifest contains the required intent with a plain Dart test.
- iOS shared code must be a member of **both** the app target and the extension target, or it works in the Simulator and fails on device. Verify target membership before trusting a green Simulator run.

## Before finishing native work, confirm

- Any latency-critical native path touches no Dart, no isolate, no engine, no DB-open, no migration.
- Both (all) contract owners changed together, or none did.
- Every write path that can change a mirrored value — save, clear, delete, reorder, import — republishes.
- Native logic sits in a plain, unit-tested class; the OS-lifecycled subclass is a thin delegate.
- The invariant only a device can prove has a manual-checklist step written for it.
- No `MethodChannel` was born outside `lib/native/`.
