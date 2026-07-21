# Token tiers, ThemeExtension, and hand-authored ColorScheme

The structural core: how values are named, exposed, and folded into Material — without prescribing a single color.

## Two tiers, and why the naming matters

**Tier 1 — primitives.** Raw values, in one file (`lib/theme/primitives.dart`). Name each by its **measured value**, so the name stays true forever and inverts correctly by construction.

| Naming style | Example | Why it rots |
|---|---|---|
| Measured (use this) | `neutral12`, `accent45` | The number is a fact (e.g. OKLCH lightness ×100); it cannot lie in either theme. |
| Rank | `grey700` | Rank scales have no room to insert a value between 600 and 700, and "500 is the main one" is false in dark mode. |
| Appearance | `darkGrey` | Inverts catastrophically — `darkGrey` is the *lightest* neutral in dark mode. |
| Brand | `brandPrimary` | Dies with the brand; a re-brand makes every reference a lie. |

**Tier 2 — semantic slots.** A `ThemeExtension` names roles: `surface`, `onSurface`, `onSurfaceMuted`, `accent`, `hairline`, `danger`, `hairlineWidth`. Widgets read **only** the semantic tier. A widget that reaches `Primitives.neutral12` has hardcoded one theme; grep for primitive references outside `lib/theme/` in review.

The two tiers are different *kinds* of names on purpose: a primitive answers "what value is this?", a slot answers "what is this for?". Light and dark are two different Tier-2 instances built from the same primitive pool.

## Why `ThemeExtension`, and the asserting `of()`

`ColorScheme` cannot hold every neutral, hairline width, or bespoke role a product needs — so carry them on a `ThemeExtension<T>`, attached to `ThemeData(extensions: [...])`, retrieved with `Theme.of(context).extension<T>()`. `MaterialApp` then drives light/dark switching and rebuild invalidation for free.

Expose it through a static `of(context)` that **asserts**:

```dart
static AppColors of(BuildContext context) {
  final ext = Theme.of(context).extension<AppColors>();
  assert(ext != null, 'AppColors missing. Build ThemeData via buildAppTheme().');
  return ext!;
}
```

A `?? AppColors.fallback()` would silently ship a theme no test has ever verified — the exact failure the extension exists to prevent. Loud in debug beats wrong in the field.

## `copyWith` and honest `lerp`

Both are abstract members; omitting them will not compile. `copyWith` is mechanical. `lerp` is where rot hides:

- Interpolate every `Color` (`Color.lerp`) and every `double` (`lerpDouble`).
- **Snap** non-interpolables — font families, `ShapeBorder` factories, enums — at `t < 0.5`.
- If your app bans theme animation entirely and you make `lerp` a pure step (`t < 0.5 ? this : other`), leave a one-line comment saying so. A bare step reads as an unfinished implementation, and the next reader will "helpfully" restore a per-field interpolation and reintroduce the forgotten-field bug.

Make it `t < 0.5 ? this : (other ?? this)`, never `return this`: if a theme change ever *does* animate, `return this` never arrives at the new theme, whereas the `t < 0.5` form lands on the correct endpoint at both ends.

The recurring bug: someone adds a slot, updates the constructor and `copyWith`, and forgets `lerp`. The new slot then never transitions. A `lerp` that lists every field (or a deliberately commented step) is the only defense a compiler can't give you.

## Hand-author `ColorScheme`; never `fromSeed` for identity

`ColorScheme.fromSeed` derives ~40 roles from one seed via a tonal algorithm. Two mechanical failures, not aesthetic ones:

1. **Per-role overrides do not propagate.** Overriding `surface` does *not* regenerate `surfaceContainerHigh` / `surfaceDim` / `surfaceBright` — they stay seed-derived. "Seed plus a few overrides" means owning the roles you chose *and* every seam of the ones you didn't.
2. **A seed encodes an opinion you may not want.** Flat neutral chroma across the ramp is what makes seed-generated darks read a particular way; a hand-tuned neutral ramp cannot be expressed by a single seed.

So state every role you consume, and **keep the M3 role names** so Material components theme themselves:

```dart
ColorScheme(
  brightness: brightness,
  primary: c.accent, onPrimary: c.surface,
  secondary: c.accent, onSecondary: c.surface,
  surface: c.surface, onSurface: c.onSurface,
  surfaceContainerHighest: c.surface, onSurfaceVariant: c.onSurfaceMuted,
  outline: c.hairline, outlineVariant: c.hairline,
  error: c.danger, onError: c.surface,
);
```

A `TextField` reads `surfaceContainerHighest`, `onSurfaceVariant`, `outline`, and `error` unaided — name them correctly and you never patch `InputDecoration` per widget. Unstated roles fall to `ColorScheme`'s own defaults (not a seed's), and nothing in the app should read a role you didn't state.

`dynamic_color` / Material You is a stronger version of the same problem: a wallpaper-derived palette is computed on-device from an image no test has seen, so every build-time contrast guarantee evaporates. Decline it for any product that needs a stable, verified identity.

## Inject once, at the composition root

Build both `ThemeData`s and hand them to `MaterialApp` — the theme is never flavor-dependent:

```dart
MaterialApp(
  theme: buildAppTheme(Brightness.light),
  darkTheme: buildAppTheme(Brightness.dark),
  themeMode: mode, // from the restored setting; see app-startup-and-bootstrap
);
```

`buildAppTheme` attaches **all** extensions to **both** brightnesses. A palette-only dark theme (inverting light, or shipping light's contrast ratios) fails AA in the dark; each theme is authored and verified independently, and a dark accent usually needs raised luminance to survive.

## No token pipeline for a small app

Do not add DTCG JSON, Style Dictionary, a codegen step, or a Figma sync to a single-package app. Those solve a designer→engineer handoff; when that's the same person, a JSON→codegen build step and a `node_modules` for a few dozen values buys a new build-failure mode to solve a problem that does not exist. Revisit only when a second person owns the tokens.

### When multi-package (workspace)

In a Dart pub workspace where a `design_system` package is consumed by several app packages, the extension **classes** (slot names, `copyWith`/`lerp`) live in the shared package; the **instances** (the actual values) live in each app. A shared file never imports an app's palette. Adding or renaming a slot is then a shared-package change with an honest `lerp` and a neutral default that leaves existing goldens byte-identical. This layering is unnecessary for a single-package app — keep tokens in `lib/theme/`.
