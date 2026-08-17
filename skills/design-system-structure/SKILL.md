---
name: design-system-structure
description: Structures a Flutter design system as tokens→theme→modifiers→shapes with two-tier tokens (primitives named by measured value, semantic slots named by role) exposed through a ThemeExtension read via an asserting of(context); hand-authors both light and dark ColorScheme instead of ColorScheme.fromSeed, keeps every raw color/hex/Colors./Curves./Duration/BorderRadius/fontSize inside lib/theme/ behind a no-raw-values gate, collapses animation to zero under reduced motion, restores the persisted theme before first paint, bundles fonts (never google_fonts/dynamic_color), and derives each stateful meaning's supporting color last so color is never its sole signal. Use when creating or editing ThemeData/ThemeExtension/ColorScheme, adding or renaming a design token, wiring theme injection or theme-mode persistence, reaching for fromSeed/dynamic_color/google_fonts/FontVariation, structuring a theme/ or DesignSystem/ folder, or reviewing any widget that renders a color, radius, duration, or font.
---

# design-system-structure

A design system is code that is *incapable of holding a stray opinion*: every aesthetic value lives in one directory, and every widget reads it back through a named slot. This skill owns how tokens, themes, components, and shapes are **structured and consumed** — not which colors or radii to pick (that belongs to your design source of truth). Getting the structure right makes a reskin a `diff lib/theme/` and turns a stray `Color(0xFF…)` in feature code into a build failure instead of a style nit.

Read the reference for the task at hand:
- `references/token-tiers-and-themeextension.md` — two-tier token naming, ThemeExtension mechanics, the asserting `of()`, hand-authored `ColorScheme` vs `fromSeed`, honest `lerp`.
- `references/motion-and-reduced-motion.md` — the three animations Material mounts by default, why `NoSplash` is not enough, reduced-motion-means-zero, `pumpAndSettle` bans in tests.
- `references/typography-and-fonts.md` — bundling fonts, `LicenseRegistry`, `FontWeight` drives `wght`, silent `FontVariation` no-ops, subsetting without instancing, per-script fallback cascades.
- `references/contrast-and-redundant-encoding.md` — AA as a unit test, ≥3 grayscale-legible signals per meaning, reading a11y flags from `MediaQuery`.

Run `scripts/check_raw_values.sh` and `scripts/check_font_bundling.sh` before a PR.

## Non-negotiable rules

1. **No raw aesthetic value outside `lib/theme/**` — the gate is the law.** A `Color(0x…)` / `Colors.*` (except `transparent`) / `Curves.*` / `Duration(milliseconds:|seconds:` (except `Duration.zero`) / literal `BorderRadius.circular(n)` / `fontSize: n` in feature or shared UI code fails `scripts/check_raw_values.sh`. A legitimate new need is a **new token slot, never a `// ignore`** — one place to diff is the whole point.
2. **Two token tiers; widgets read only the semantic tier.** Tier 1 = primitives named by the **measured value** (`neutral12` = OKLCH lightness ×100), never by rank (`grey700`), appearance (`darkGrey`), or brand (`brandPrimary`). Tier 2 = semantic slots named by role (`surface`, `onSurface`, `hairline`, `accent`). A widget that reaches a Tier-1 primitive has hardcoded one theme. WHY: rank scales have no room to insert and lie in dark mode; appearance names invert catastrophically; brand names die with the brand.
3. **Read tokens through a `ThemeExtension` and an asserting `of(context)`.** Never a static `const` class, never an `InheritedWidget` side channel. `of()` asserts on a missing extension — it does **not** `?? fallback`. WHY: `MaterialApp` drives light/dark switching and correct-by-construction invalidation; a fallback silently ships a theme no test verified, and loud-in-debug beats wrong-in-field.
4. **Hand-author `ColorScheme`; never `ColorScheme.fromSeed` (or `dynamic_color`) for identity.** `fromSeed`'s per-role overrides do **not** propagate — override `surface` and `surfaceContainerHigh` stays seed-derived. State every role you consume, keep the M3 role names so Material widgets theme themselves, and let unstated roles take `ColorScheme`'s own defaults, not a seed's opinion. WHY: "seed plus a few overrides" means owning the ~9 roles you chose *and* every seam of the ~40 you didn't.
5. **Layer the system: tokens → theme → modifiers/components → shapes.** Author light **and** dark by hand (dark is never an auto-flip), each passing AA independently, and attach every extension to **both** `ThemeData`s. Inject the theme exactly once, at the composition root. WHY: theming the app must touch one directory; a palette-only dark theme ships light's ratios into the dark.
6. **`lerp` honestly or snap deliberately; `copyWith` is mandatory.** Interpolate colors and doubles; snap non-interpolables (font families, `ShapeBorder`) at `t < 0.5`. If your app bans theme animation and you snap everything, leave a comment — a bare step-`lerp` reads as unfinished and the next reader will "fix" it. WHY: a new field silently forgotten in `lerp` is the classic design-system rot.
7. **Color is a derived token, computed LAST — never a status's only channel.** Color is a pure function of a canonical value object (an enum/small class), resolved through a semantic slot at the end; status is never read *from* color, and the supporting color is a slot read, not a literal. The never-color-alone floor itself — ≥3 non-color signals (glyph, label, weight/position) per stateful meaning — is owned by `accessibility-as-code`; this skill only enforces that the color reinforcing them is a derived slot. WHY: a color not derived from the value object drifts out of sync, and a widget that leans on color alone dies in grayscale.
8. **Reduced motion collapses to zero, not "gentler."** Read `MediaQuery.disableAnimationsOf(context)` and resolve to `Duration.zero` / a cross-fade to the end state — never a shorter duration or a softer curve. Motion is never the only signal for a state change. WHY: a user who asked the OS to stop animations asked for stop.
9. **Restore the persisted theme before first paint.** Load the saved theme mode / variant **before** `runApp`, from the same versioned settings the rest of the app uses (not an async `shared_preferences` read that lands a frame late). An unknown or corrupt stored value falls back **explicitly and visibly**, never to a `null` that leaves `of()` asserting on a device with no debugger. WHY: a flash of the wrong theme is a sudden luminance change the user did not cause.
10. **Bundle fonts; never `google_fonts` at runtime.** Declare fonts in `pubspec.yaml`, ship the license text and register it via `LicenseRegistry`, and drive weight with `FontWeight` (which drives the `wght` axis) — not a redundant `FontVariation('wght', …)`. Declare a per-script `fontFamilyFallback` cascade that ends in a known-good face. WHY: `google_fonts` ships an HTTP code path by default; `FontVariation('opsz'|'ital', …)` silently no-ops on a font that lacks the axis, so a "working" italic is invisible in review.
11. **Painters snapshot tokens; `paint()` never reads `BuildContext`.** Resolve `Theme.of(context).extension<T>()` once at the widget layer and pass the values into the `CustomPainter`/`Scene` fields. WHY: keeps `paint()` allocation-free and testable without a `MaterialApp`; see `custom-canvas-and-gestures`.
12. **The reduced-motion flag is read from `MediaQuery` (`disableAnimationsOf`), never app state** — it feeds `resolveMotion` (this skill's helper, below). Reading the *other* platform a11y flags (`boldTextOf`, `highContrastOf`, `textScaler`) from `MediaQuery` rather than a stale app-state copy is owned by `accessibility-as-code`.

## The token layering

`tokens → theme → modifiers → shapes`. Primitives carry values; a `ThemeExtension` names semantic slots; a `ThemeData` builder folds slots into Material's `ColorScheme` and component themes; shape *factories* live on their own extension so a component asks for a silhouette, not a radius.

```dart
// lib/theme/primitives.dart — TIER 1. The ONLY file allowed a raw color literal.
// Named by MEASURED value; values are placeholders owned by your design authority.
abstract final class Primitives {
  static const neutral08 = Color(0xFF141414); // L .08 — ink
  static const neutral96 = Color(0xFFF4F4F4); // L .96 — paper
  static const neutral40 = Color(0xFF636363);
  static const accent45  = Color(0xFF3A6FF0);
}

// lib/theme/app_colors.dart — TIER 2. Widgets read THESE, never a primitive.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({required this.surface, required this.onSurface, required this.accent});
  final Color surface, onSurface, accent;

  static AppColors of(BuildContext context) {
    final ext = Theme.of(context).extension<AppColors>();
    assert(ext != null, 'AppColors missing. Build ThemeData via buildAppTheme().');
    return ext!; // assert, never `?? fallback` — a fallback ships an unverified theme.
  }
  // copyWith + lerp omitted here — see examples/app_theme.dart for the full class.
}
```

Full worked file (primitives, a shapes extension with a `cardShape` factory, the hand-authored `ColorScheme`, honest `lerp`, and one-shot injection): `examples/app_theme.dart`.

## Hand-author `ColorScheme`, keep the M3 role names

```dart
// WRONG — surfaceContainerHigh, surfaceDim, surfaceBright etc. stay seed-derived;
// your `surface` override does not propagate to them.
ColorScheme.fromSeed(seedColor: Primitives.accent45, surface: c.surface);

// RIGHT — state every role you read. Unstated roles get ColorScheme's defaults,
// not a seed's opinion, and the M3 names mean Material widgets theme themselves.
ColorScheme(
  brightness: brightness,
  primary: c.accent, onPrimary: c.surface,
  surface: c.surface, onSurface: c.onSurface,
  surfaceContainerHighest: c.surface, onSurfaceVariant: c.onSurfaceMuted,
  outline: c.hairline, error: c.danger, onError: c.surface,
);
```

A Material `TextField` reads `surfaceContainerHighest`, `onSurfaceVariant`, `outline`, and `error` on its own — name the roles right and it themes with zero per-widget `InputDecoration` patching that would drift out of sync on the next theme change.

## Reduced motion: read the flag, collapse to zero

```dart
// The one place a widget asks "should I animate?" — collapses under the OS flag.
Duration resolveMotion(BuildContext context, Duration full) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : full;

AnimatedContainer(
  duration: resolveMotion(context, AppMotion.of(context).medium), // token, not 300ms
  curve: AppMotion.of(context).enter,                              // token, not Curves.easeOut
  color: AppColors.of(context).surface,
  child: child,
);
```

`NoSplash.splashFactory` alone is **not** enough — the pressed highlight fade is a separate `InkHighlight`, and `MaterialApp` interpolates `ThemeData` over `kThemeAnimationDuration` unless you pass `themeAnimationStyle: AnimationStyle.noAnimation`. See `references/motion-and-reduced-motion.md` for all three switches.

## Restore the theme before first paint

```dart
// bootstrap: settings are loaded BEFORE runApp, so the first frame is correct.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = await Settings.load();               // synchronous by the time runApp runs
  final mode = ThemeVariant.tryParse(settings.themeName) // unknown/corrupt -> explicit default
      ?? ThemeVariant.system;
  runApp(App(initialVariant: mode));
}
```

Persisting the choice but reading it back asynchronously (a bare `shared_preferences` read) lands a frame late and flashes the wrong theme. `state-management-riverpod` covers threading the resolved variant through a `themeModeProvider`; `app-startup-and-bootstrap` covers the `main()` ordering.

## Redundant encoding: derive color last

The ≥3-non-color-signals floor is owned by `accessibility-as-code`; the design-system contribution shown here is narrower — the supporting color is *derived last* from a canonical value object through a semantic slot, never read as the source of state:

```dart
enum OrderStatus { pending, active, blocked }

extension OrderStatusView on OrderStatus {
  IconData get icon => switch (this) {          // signal 1: shape differs per status
        OrderStatus.pending => Icons.schedule,
        OrderStatus.active  => Icons.play_arrow,
        OrderStatus.blocked => Icons.error_outline,
      };
  String label(AppLocalizations l) => switch (this) { … }; // signal 2: the word
  double get emphasis => this == OrderStatus.blocked ? 2 : 1; // signal 3: monotonic weight
  Color color(AppColors c) => switch (this) {   // color is DECORATION, derived LAST
        OrderStatus.pending => c.onSurfaceMuted,
        OrderStatus.active  => c.accent,
        OrderStatus.blocked => c.danger,
      };
}
```

Full chip widget rendering all three signals: `examples/status_encoding.dart`.

## Anti-patterns

- **`Color(0xFF…)`, `Colors.blueGrey`, `Curves.easeOut`, `Duration(milliseconds: 200)`, `BorderRadius.circular(16)`, or `fontSize: 14` in a widget outside `lib/theme/`** — the gate fails; the fix is a slot read or a new slot, never `// ignore`.
- **A static `AppColors`/`Dimens` `const` class, or `AppColors.of` returning `?? AppColors.fallback()`** — slots ride a `ThemeExtension`, and a fallback ships a palette no test ever verified.
- **`ColorScheme.fromSeed(...)` for a product with an identity, or adding `dynamic_color`** — the overrides don't propagate and wallpaper-derived palettes are untestable at build time.
- **A palette-only dark theme, or extensions attached to the light `ThemeData` only** — dark silently renders defaults and theme switches snap.
- **A `lerp` that returns `this` unlabeled, or that forgets a newly added field** — the theme snaps or a slot goes un-interpolated forever.
- **Color as the only status channel** — recoloring is fine; removing the glyph/label/weight it accompanies is a bug that vanishes in grayscale.
- **Choosing a shorter duration or softer curve under reduced motion** — collapse to `Duration.zero`; the user asked for stop.
- **A bare `shared_preferences` read for theme, corrected a frame after `runApp`** — a flash of the wrong theme is a luminance jolt; restore before first paint.
- **`import 'package:google_fonts/…'` or `FontVariation('opsz'|'ital', …)`** — the first ships an HTTP path; the second no-ops silently on a font without the axis.
- **A `CustomPainter` calling `Theme.of(context)` inside `paint()`** — snapshot tokens into painter fields at the widget layer.
- **A token pipeline (DTCG JSON, Style Dictionary, Figma sync codegen) for a small single-package app** — it buys a `node_modules` build-failure mode to solve a designer/engineer handoff that, when it's the same person, does not exist.

## Definition of done

- [ ] `scripts/check_raw_values.sh` and `scripts/check_font_bundling.sh` are clean over `lib/` (raw values confined to `lib/theme/**`; no `google_fonts`).
- [ ] Every aesthetic value a widget renders traces to a named semantic slot on a `ThemeExtension`, read via an asserting `of(context)`.
- [ ] Tokens are two-tier: primitives named by measured value, semantic slots named by role; no widget reads a primitive.
- [ ] `ColorScheme` is hand-authored for both brightnesses (never `fromSeed` for identity); M3 role names kept; every extension attached to **both** `ThemeData`s.
- [ ] Both themes pass AA independently, verified as a `computeLuminance()` unit test over declared fg/bg pairs (`references/contrast-and-redundant-encoding.md`).
- [ ] `copyWith` implemented; `lerp` interpolates colors/doubles and snaps non-interpolables (or is a commented deliberate step).
- [ ] Every stateful meaning carries ≥3 grayscale-legible signals; a greyscale golden still answers "what state is this?".
- [ ] Every animation reads a motion token and collapses to zero under `MediaQuery.disableAnimationsOf`.
- [ ] The persisted theme is restored before first paint; unknown values fall back explicitly, never to `null`.
- [ ] Fonts are bundled and license-registered; per-script `fontFamilyFallback` declared; no runtime font fetch.
- [ ] Painters receive a token snapshot; no `Theme.of(context)` in `paint()`.

## Related skills

- See `accessibility-as-code` for reading a11y state from `MediaQuery`, the never-color-alone rule, target sizes, and never clamping `textScaler`.
- See `custom-canvas-and-gestures` for the painter that consumes the token snapshot.
- See `flutter-performance` for `const` subtrees, `.select` rebuild scoping, and `RepaintBoundary`.
- See `widget-composition` for building views from small `const` widgets that read these slots.
- See `state-management-riverpod` for the `themeModeProvider` and composition-root injection.
- See `app-startup-and-bootstrap` for the `main()` ordering that restores the theme before `runApp`.
- See `i18n-rtl-l10n` for per-script fonts, directional geometry, and RTL goldens.
- See `lint-and-style-config` for promoting the no-raw-values grep into a CI gate.
- See `motion-and-haptics` for what the motion tokens are spent on: the moment catalog, the haptic event map, and the degradation each moment declares.
- See `design-review-workflow` for the once-per-app screenshot sweep that judges the assembled system.

## References

- Flutter API — `ThemeExtension`: https://api.flutter.dev/flutter/material/ThemeExtension-class.html
- Flutter API — `ThemeData` (`extensions`, component themes, `colorScheme`): https://api.flutter.dev/flutter/material/ThemeData-class.html
- Flutter API — `ColorScheme` (roles; `fromSeed` caveats): https://api.flutter.dev/flutter/material/ColorScheme-class.html
- Flutter cookbook — Use themes to share colors and font styles: https://docs.flutter.dev/cookbook/design/themes
- Flutter cookbook — Use a custom font (bundling, `fontFamilyFallback`): https://docs.flutter.dev/cookbook/design/fonts
- Flutter API — `MediaQueryData.disableAnimations` / `textScaler`: https://api.flutter.dev/flutter/widgets/MediaQueryData-class.html
- Flutter API — `Color.computeLuminance` (WCAG relative luminance): https://api.flutter.dev/flutter/dart-ui/Color/computeLuminance.html
- Flutter API — `LicenseRegistry`: https://api.flutter.dev/flutter/foundation/LicenseRegistry-class.html
- Material Design 3 — design tokens: https://m3.material.io/foundations/design-tokens/overview
- W3C WAI — WCAG 2.2 SC 1.4.3 Contrast (Minimum): https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html
- W3C WAI — WCAG 2.2 SC 1.4.1 Use of Color: https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html
