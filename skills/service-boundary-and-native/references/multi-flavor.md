# Multi-flavor composition roots and the banned-dependency gate

Most apps ship one flavor and need none of this. Reach here only when the app genuinely builds in more than one flavor — free/pro, per-store, per-region, staging/prod with different backends — where the **live implementation of a boundary differs between builds**. The seam that makes one boundary injectable (see `SKILL.md`) is what makes multiple flavors a one-line-per-service change; this file is the flavor mechanism itself.

## One thin `main_<flavor>.dart` per flavor over a single flavor-blind `app.dart`

The flavor is chosen **at compile time, never at runtime**. Each entrypoint differs in **exactly one thing**: which concrete impl each provider is overridden with. Both mount the same flavor-blind `app.dart` over the same interfaces.

```dart
// lib/service_providers.dart — throwing placeholders, shared by every flavor.
// (The clock is not here: clockProvider self-defaults to const Clock() — see SKILL.md.)
final analyticsServiceProvider =
    Provider<AnalyticsService>((ref) => throw UnimplementedError('override in main_<flavor>.dart'));
final remoteConfigServiceProvider =
    Provider<RemoteConfigService>((ref) => throw UnimplementedError('override in main_<flavor>.dart'));
```

```dart
// lib/main_free.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ProviderScope(
    overrides: [
      analyticsServiceProvider.overrideWithValue(NoopAnalytics()),   // <-- only the RHS differs
      remoteConfigServiceProvider.overrideWithValue(BundledRemoteConfig()), // <-- only the RHS differs
    ],
    child: const App(), // SAME tree as main_pro.dart
  ));
}
```

```dart
// lib/main_pro.dart — SAME provider list, SAME order; only the impls change.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ProviderScope(
    overrides: [
      analyticsServiceProvider.overrideWithValue(VendorAnalytics()),
      remoteConfigServiceProvider.overrideWithValue(SignedCdnRemoteConfig()),
    ],
    child: const App(),
  ));
}
```

**Rule: the two `main`s must diff line-for-line** — same providers, same order, only each right-hand-side impl changes. A provider overridden in one flavor but forgotten in the other is a bug; the throwing placeholder turns it into a loud `UnimplementedError` at startup rather than silent null data. Never default a placeholder to a live service (it hides a missing override and can open real I/O at import).

## The split is a build fact — product flavors + schemes, no runtime detection

```gradle
// android/app/build.gradle.kts — the split as a build fact.
android {
  flavorDimensions += "tier"
  productFlavors {
    create("free") { dimension = "tier"; applicationIdSuffix = ".free" }
    create("pro")  { dimension = "tier" }
  }
}
dependencies {
  // A per-flavor-only native SDK is declared in that flavor's sourceSet ONLY.
  "proImplementation"("com.example.vendor:analytics:1.2.3") // NEVER in freeImplementation
}
```

iOS keeps matching build configurations / schemes. A binary is one flavor OR another, decided at build time:

```
flutter build appbundle --flavor pro  -t lib/main_pro.dart
flutter build appbundle --flavor free -t lib/main_free.dart
```

- **No `#if FLAVOR` / `String.fromEnvironment('FLAVOR')` fork inside feature, widget, or Notifier code.** The flavors diverge only at the composition root; scattering the split rots the tree.
- **No binary that detects its ecosystem and swaps SDKs at runtime.** The flavor is a build fact; there is no cross-flavor runtime switch.
- **Pin every per-flavor plugin** to an exact version and re-verify on each bump — these SDKs move independently, and one flavor pulling another's transitive dependency is exactly what the gate below catches.

## The banned-dependency graph gate

When a flavor must link **none** of some SDK set (a store that ships devices without a given service framework; a "no third-party analytics" build; a lite tier that must not pull a heavy SDK), a passing user journey proves nothing — the running code merely never *called* it. Only a static graph check proves the release *links* none.

```yaml
# .github/workflows/ci.yaml — run per flavor with that flavor's config.
- name: free flavor links none of the pro-only SDKs
  run: scripts/check-flavor-graph.sh 'vendor_analytics|signed_cdn_config'
```

The check resolves the flavor's dependency graph (`flutter pub deps --style=compact --no-dev`) and fails if any banned package name is reachable. Keep it symmetric where it matters: also fail the other flavor if it pulls this flavor's exclusive SDK. See `scripts/check-flavor-graph.sh`.

## Tests are flavor-blind

No flavor `main` runs in tests. A widget/Notifier test overrides the same providers with deterministic fakes through `ProviderScope(overrides:)` — no emulator, no network, no real SDK — so every flavor's behaviour is asserted headlessly against the same tree. This is the payoff of the seam: the flavor list is data at the composition root, and everything below is proven once.

See `ci-pipeline-and-gates` for wiring the graph gate into CI and `dependency-hygiene` for pinning and vetting per-flavor plugins.
