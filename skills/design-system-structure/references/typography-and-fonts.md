# Typography and font engineering

Type is a token like color: sizes, weights, tracking, and height live in `TextStyle`s built inside `lib/theme/`, never inline. The subtle failures are in *fonts* — bundling, licensing, and the variable-axis mechanics that fail silently.

## Bundle fonts; never `google_fonts` at runtime

`google_fonts` fetches over HTTP **by default**. It can be configured offline, but it still ships an HTTP client and a network code path into the binary. Declare fonts in `pubspec.yaml` and ship the file:

```yaml
flutter:
  fonts:
    - family: AppSans
      fonts:
        - asset: assets/fonts/AppSans-VariableFont.ttf
```

Ship the license text (`OFL.txt` for a SIL OFL font) and register it so the app's licenses page is honest:

```dart
LicenseRegistry.addLicense(() async* {
  final text = await rootBundle.loadString('assets/fonts/OFL.txt');
  yield LicenseEntryWithLineBreaks(['AppSans'], text);
});
```

If a dependency pulls `google_fonts` transitively into an offline-promising app, treat it as a blocker, not a wart. `scripts/check_font_bundling.sh` greps for the import.

Verify embedding rights per file, from the license, not from memory: SIL OFL is a safe harbor; commercial faces need explicit *application-embedding* terms, and platform system fonts (e.g. Apple's SF family) are licensed for that platform only — prototype-only, never bundled cross-platform.

## `FontWeight` drives the `wght` axis — don't double-drive it

As of recent Flutter, `FontWeight` drives a variable font's `wght` axis automatically. Setting both a `fontWeight` and a `FontVariation('wght', …)` is redundant at best, conflicting at worst.

```dart
// RIGHT
const TextStyle(fontFamily: 'AppSans', fontSize: 20, fontWeight: FontWeight.w600);

// WRONG — double-driving one axis
const TextStyle(fontWeight: FontWeight.w600, fontVariations: [FontVariation('wght', 600)]);
```

`FontWeight(560)` is legal for an off-step weight — the axis is continuous; the named instances are just labelled stops.

## `FontVariation('opsz'|'ital', …)` no-ops silently

A variable font only responds to axes it actually ships. `FontVariation('opsz', …)` on a font without an optical-size axis, or `FontVariation('ital', 1)` on a font shipped upright-only, **silently does nothing** — so a "working" optical size or italic is impossible to catch in review by looking at the code. Probe the actual TTF's axes (with a tool like `fc-query`/`ftxdumperfuser`/`fontTools`) and rely only on axes it reports. If you need italic and the file is upright-only, italic is a *separate file* — bundle it or emphasize with weight/size instead.

## Subset without instancing

Flutter tree-shakes *icon* fonts only, never text fonts — subsetting a text font is manual. When you subset (e.g. `pyftsubset`) to shrink payload:

- Pass `--layout-features='*'` to keep shaping (`GSUB`/`GPOS`) — dropping these breaks cursive/contextual scripts.
- Do **not** let the subsetter *instance* the font. An instanced variable font is frozen to one static weight; `FontWeight` and the platform bold-text accessibility flag then stop working, and it fails only for the accessibility user who turns bold text on.
- After subsetting, verify the `wght` axis (and any other you rely on) still reports its min/default/max range.

## Per-script fallback cascade, always declared

Type that can render more than one script must declare a `fontFamilyFallback` cascade that **ends in a known-good face covering every script the app localizes into**. A glyph falling through to an arbitrary OS font is a defect (tofu, or a mismatched face), not a graceful fallback — and it is invisible on the developer's device, which happens to have the right system font.

```dart
const TextStyle(
  fontFamily: 'AppDisplay',                    // Latin display face
  fontFamilyFallback: ['AppTextBroadCoverage'], // covers the other scripts — never the OS default
);
```

Three legal shapes: one face covers everything; a Latin display face + a broad-coverage fallback for other scripts; or a locale-switched family where metrics matter. Whichever you pick, the cascade is written down in the theme source — the one place a font-family string may appear — not held in someone's head. Bundle real weights; synthesized ("faux") bold mangles the joining strokes of cursive scripts. `i18n-rtl-l10n` owns numerals, calendars, and bidi isolation — don't re-implement them here.

## Numeral and metric details that bite

- **Tabular figures** wherever numbers change or align in a column: `fontFeatures: [FontFeature.tabularFigures()]`, so digits don't jitter during a count or shift a total. Verify the face actually ships `tnum` for the digit block in use; many do not — measure-and-reserve if it doesn't.
- **Line height** carried by scripts with tall ascenders/descenders needs a generous `height`; a value tuned for Latin can shear glyphs of other scripts. Pin cross-locale line boxes with `StrutStyle(forceStrutHeight: true)` where parity matters.
- **Never clamp `MediaQuery.textScaler`.** Let text scale; size rows to content rather than fixing heights that clip scaled glyphs. See `accessibility-as-code`.
- **Casing and punctuation belong in the string table, not the render.** Author "SETTINGS" (if you want caps) or curly quotes in the localized string itself — never `toUpperCase()`/`toLowerCase()` at render, which will eventually mangle a proper noun or a user-entered value. Never apply casing transforms to user content at all.

## Type scale is part of the design system

Resist adding "one more" type role. A wide size spread between the largest and smallest role is doing real work; every extra role in the middle erodes the contrast that carries the hierarchy. Keep the role set small and let scale, weight, and space differentiate — the roles are semantic slots on the theme, read by name, never a bespoke `fontSize:` at a call site.
