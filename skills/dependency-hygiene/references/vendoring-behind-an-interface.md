# Vendoring a bus-factor-1 plugin behind an interface

Some apps have exactly one dependency whose failure means the app cannot build at all — usually a single-maintainer native plugin wrapping a platform API (TTS, audio session, biometrics, a scanner, secure storage). This is how you make that dependency swappable without betting the app on an upstream maintainer.

## The interface is day-one; the vendor is later

Author the seam **now**, vendor **only when it breaks**. Pre-emptive vendoring buys a permanent maintenance burden against a break that has not happened. The interface is the cheap insurance:

```dart
// The port the app depends on. The plugin lives entirely behind this.
abstract interface class SecureStorageGateway {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
  Future<void> delete(String key);
}
```

The whole app — every call site, every test — depends on `SecureStorageGateway`, never on the plugin's own classes. The `Gateway` suffix is deliberate: it marks a thin wrapper over a specific plugin, as opposed to a `Service` capability interface you define — `naming-conventions` owns that distinction. The one thin implementation file that calls the plugin is the only place the package name appears. See `service-boundary-and-native` for injecting the live impl at the composition root and faking it in tests, and `examples/vendored_plugin_behind_interface.dart`.

Because only the methods on the interface are ever called, the surface you would have to vendor is tiny — usually a handful of calls over one platform API.

## The vendoring triggers

Vendor when *either* is true — not before:

1. It **stops building** against a Flutter/Gradle/SDK release (e.g. a plugin still applying a deprecated Gradle plugin that a future Flutter turns from warning into error).
2. A **regression ships** and upstream is unresponsive for a few weeks.

Check the first trigger on **every Flutter upgrade** — a build *warning* naming your critical plugin is a countdown, not noise. Do not let vendoring become an emergency discovered on the day you need a Flutter upgrade for something unrelated.

## Procedure

1. `git clone` upstream at the **last-good tag** into `third_party/<plugin>/`. Record the exact commit SHA.
2. Point the pubspec at it — path dependencies work for plugins with native code:
   ```yaml
   dependencies:
     the_plugin:
       path: third_party/the_plugin
   ```
   **`lib/` does not change at all.** That is the entire payoff of the interface.
3. **Read `third_party/<plugin>/LICENSE` and confirm it permits redistribution before you commit the copy.** Keep the file — a permissive licence requires retaining the notice and licence text in redistributed source. Do this first; the file is open anyway.
4. Write `third_party/<plugin>/VENDORED.md`: upstream URL, vendored SHA, date, why, and every line changed.
5. **Patch, don't refactor.** Every line you touch is a line you own forever. Fix the break, ship, stop. Do not tidy the native code, rename anything, or "modernise" its API.
6. Re-run the manual real-device pass. No test in the suite can establish that the vendored copy still exercises the native capability.

## What must not move

The interface (`SecureStorageGateway` and its method signatures) and everything above it. If a vendoring diff touches anything outside `third_party/` and the single thin implementation file, it has gone wrong — the surrounding code exists precisely so the plugin can be swapped underneath it without moving.

If upstream revives, diff your patch against the new release and go back to the pub dependency. If it does not, the app now owns a handful of methods over one platform API — which was always the real dependency.
