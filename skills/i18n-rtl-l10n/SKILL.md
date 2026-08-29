---
name: i18n-rtl-l10n
description: >-
  Enforces the gen-l10n/ARB localization contract: every string through AppLocalizations from a
  template app_en.arb, key + placeholder parity, nullable-getter:false so a missing key is a
  compile error, ICU plural/select over concatenation, Directional-only geometry
  (EdgeInsetsDirectional, AlignmentDirectional, TextAlign.start, Icons.adaptive), FSI/PDI
  isolation for mixed-script runs, per-locale NumberFormat with a pinned numbering system,
  canonical UTC-epoch + ASCII storage projected only at render, normalize-to-ASCII before any
  parse, and three vendored LocalizationsDelegates ahead of the Global* ones for a locale
  flutter_localizations lacks. Use when adding or translating an ARB key, building an RTL screen,
  formatting or parsing dates/numbers/numerals, wiring l10n.yaml, AppLocalizations, or MaterialApp
  localizationsDelegates, supporting a locale Flutter lacks (ckb), fixing a locale that crashes on
  Tooltip or renders LTR, checking bundled-font glyph coverage, isolating technical IDs, or
  touching app_*.arb.
---

# i18n, RTL & Localization

One contract: **store canonical, localize at render.** Every conversion and formatting lives in
one `l10n` layer; feature widgets receive value objects and already-localized strings, never raw
formatting logic. RTL is a layout discipline, not a translation task — author with logical
geometry so it mirrors by construction. Applies to any app that ships more than one locale or any
RTL locale (Arabic, Persian, Hebrew, Sorani Kurdish, Urdu).

Read the reference for the task at hand:

- `references/arb-and-icu.md` — the ARB add/translate workflow, `l10n.yaml`, ICU plural/select, placeholder typing.
- `references/rtl-and-bidi.md` — the directional-geometry allow/ban table, icon mirroring, bidi isolation, CustomPainter pinned LTR, RTL charts.
- `references/numerals-and-calendars.md` — digit systems, separator traps, format/parse, calendar projection.
- `references/unsupported-locales.md` — shipping a locale `flutter_localizations` has no data for: the probe, the vendored delegate trio, delegate ordering, font coverage.

Run `scripts/check_arb_parity.sh` and `scripts/check_i18n_bans.sh` before a PR.

## Non-negotiable rules

1. **Every user-facing string goes through gen-l10n.** Add the key to the template `app_en.arb`
   first, then read it via `AppLocalizations.of(context)`. Set `nullable-getter: false` in
   `l10n.yaml` so the getter is non-null and a missing/typo key is a **compile error**, not a
   silent empty widget. Never hardcode a literal in `Text`, `tooltip:`, `label:`, `hint:`, or
   `semanticsLabel:`. Never call `AppLocalizations.of` above the `Localizations` scope (e.g. in
   `main()` before `runApp`).
2. **Key + placeholder parity across all locales.** A key present in the template but missing in
   a locale silently ships the template language; a renamed placeholder breaks that translation at
   runtime. Keep every key and every `{placeholder}` name identical — `check_arb_parity.sh` gates it.
3. **Build sentences and plurals with ICU, never concatenation.** Use `{count, plural, ...}` and
   `{x, select, ...}` in the ARB. Word order and plural categories differ per language (Arabic has
   six CLDR forms: zero/one/two/few/many/other). Concatenation produces grammatically wrong output
   and can't survive RTL reordering.
4. **Direction is a locale consequence, never hardcoded.** Wire `localizationsDelegates` +
   `supportedLocales` on `MaterialApp` and drive the active locale from state. A root
   `Directionality(TextDirection.rtl)` hides physical-side bugs and breaks LTR islands. RTL follows
   the resolved locale via `GlobalWidgetsLocalizations` with zero per-widget code — **but only for
   locales `flutter_localizations` actually ships** (rule 10). For any other, direction silently
   falls back to LTR. Assert `Directionality.of` per locale rather than assuming.
5. **Directional-only geometry from the first commit.** Use `EdgeInsetsDirectional`,
   `AlignmentDirectional`, `PositionedDirectional`, `TextAlign.start/end`,
   `MainAxisAlignment.start/end`, `BorderRadiusDirectional`, `Icons.adaptive.*`. Never
   `EdgeInsets.only(left/right)`, `Alignment.centerLeft/Right`, `Positioned(left/right:)`,
   `TextAlign.left/right`, or `Icons.arrow_back`. A grep gate rejects the PR.
6. **Store canonical: UTC epoch + ASCII digits.** Persist `dateTime.toUtc().millisecondsSinceEpoch`
   and Western/Latin digits. Calendars and numeral systems are pure display projections. **Schedule
   off the epoch/`DateTime`, never off Jalali/Hijri arithmetic** — leap/month-length quirks stay
   calendar-independent.
7. **Normalize every numeric input to ASCII before parse or storage** — digits AND separators. Use
   `double.parse(normalizeToAscii(text))`; never `int.parse(text)` on raw input (a Persian/Arabic
   soft keyboard yields `۱۲۳` / `١٢٣` and `1٫5`).
8. **Isolate strong-LTR technical runs** (account/order/reference numbers, phone, email, URL,
   product codes) with one FSI/PDI helper at the view layer **only**. Never let isolate characters
   (`U+2066`–`U+2069`) reach storage, search, or export — strip at the boundary.
9. **Bundle fonts that cover your scripts, with fallback; no runtime font fetch.** Set a theme
   `fontFamily` plus `fontFamilyFallback` so Arabic/Persian glyphs never tofu. Avoid `google_fonts`
   in an offline/no-telemetry app — it fetches at runtime. **Prove coverage from the font's own
   `cmap`, not a specimen:** script coverage is not language coverage — a face that draws Persian
   can be missing the seven letters Sorani adds, and a specimen set in Arabic never shows it.
10. **A locale `flutter_localizations` does not ship needs three vendored delegates, ordered
    first.** gen-l10n localizes *your* strings; Flutter's own chrome and the ambient `TextDirection`
    come from a different catalog. Vendor `MaterialLocalizations`, `CupertinoLocalizations` **and**
    `WidgetsLocalizations` borrowing a script neighbour, each claiming only that language code, and
    place them ahead of the `Global*` delegates — which `AppLocalizations.localizationsDelegates`
    already contains. WHY: the missing Material delegate asserts on the first `Tooltip`, and the
    Widgets fallback claims *every* locale while hardcoding `TextDirection.ltr`, so fixing only the
    Material half yields an RTL app that reads backwards and never crashes.
    See `references/unsupported-locales.md`.

## The ARB workflow (add or translate a key)

1. Add the key + its `@key` metadata (typed `placeholders`, a `description` for translators) to the
   **template** `app_en.arb`.
2. Mirror the SAME key into every other locale file with a real translation, keeping placeholder
   names and ICU structure identical (branch bodies differ; branch shapes must not).
3. Run `scripts/check_arb_parity.sh` — fails on any missing/extra key or placeholder mismatch.
4. Regenerate (`flutter gen-l10n`) and `flutter analyze` — a missing key is now a compile error.

```json
// app_en.arb (template) — declare the key + @metadata here first.
{
  "@@locale": "en",
  "itemsRemaining": "{count, plural, =0{No items left} =1{1 item left} other{{count} items left}}",
  "@itemsRemaining": {
    "description": "Count shown on the order summary card.",
    "placeholders": { "count": { "type": "int" } }
  }
}
```

```json
// app_ar.arb — same key; Arabic's SIX CLDR categories are a translation contract.
{
  "@@locale": "ar",
  "itemsRemaining": "{count, plural, zero{لا عناصر متبقية} one{عنصر واحد متبقٍ} two{عنصران متبقيان} few{{count} عناصر متبقية} many{{count} عنصرًا متبقيًا} other{{count} عنصر متبقٍ}}"
}
```

## Directional geometry — mirror by construction

```dart
// Reads correctly under LTR and RTL with zero conditionals.
Padding(
  padding: const EdgeInsetsDirectional.only(start: 16, end: 8), // never left/right
  child: Row(
    children: [
      Expanded(child: Text(task.title, textAlign: TextAlign.start)), // never .left
      IconButton(
        icon: Icon(Icons.adaptive.arrow_forward), // auto-mirrors in RTL
        onPressed: onNext,
      ),
    ],
  ),
)
```

Mirror direction-implying glyphs (back/next, chevrons, progress carets) via `Icons.adaptive.*`.
Never mirror fixed-meaning glyphs (clock, checkmark, media play/pause, logos). See
`references/rtl-and-bidi.md` for the full allow/ban table and manual-flip recipe.

## Numerals — format at the edge, one formatter everywhere

Use each locale's own `NumberFormat`: `intl` emits native digits from the locale's symbol data, not
from a `-u-nu-` extension (it drops the unicode `-u` extension during fallback). Locales `intl` has
no number symbols for (e.g. `ckb`) silently fall back to Latin, so pin those to a covered base locale
that shares the numbering system (`ckb`→`fa`) and assert the emitted digit block in a test. The same
formatter feeds chrome AND any canvas painter.

```dart
// One formatter per locale. Persian and Arabic digits are DISTINCT Unicode blocks
// (۴۵۶ U+06Fx vs ٤٥٦ U+066x) — not interchangeable. Format with a locale intl ships
// symbols for; a `-u-nu-` extension is dropped, not honored.
NumberFormat numberFormatFor(Locale locale) => switch (locale.languageCode) {
      'fa' => NumberFormat.decimalPattern('fa'),  // ۰۱۲۳۴۵۶۷۸۹ (arabext)
      // ckb has no intl number symbols — borrow fa (same arabext block + separators).
      'ckb' => NumberFormat.decimalPattern('fa'),
      'ar' => NumberFormat.decimalPattern('ar'),  // ٠١٢٣٤٥٦٧٨٩ (arab)
      _ => NumberFormat.decimalPattern('en'),      // Western (en, de, fr)
    };
```

Normalize before any parse — fold both digit ranges AND the Persian/Arabic separators:

```dart
String normalizeToAscii(String input) {
  final sb = StringBuffer();
  for (final r in input.runes) {
    if (r >= 0x0660 && r <= 0x0669) {        // Eastern-Arabic ٠-٩
      sb.writeCharCode(0x30 + (r - 0x0660));
    } else if (r >= 0x06F0 && r <= 0x06F9) { // Persian ۰-۹
      sb.writeCharCode(0x30 + (r - 0x06F0));
    } else if (r == 0x066B) {                // ٫ decimal separator -> '.'
      sb.write('.');
    } else if (r == 0x066C) {                // ٬ grouping separator -> drop
      continue;
    } else {
      sb.writeCharCode(r);
    }
  }
  return sb.toString();
}
// double.parse(normalizeToAscii(text)) — never int.parse on raw input.
```

`1٫5` means 1.5, not 15: normalizing digits but not separators silently corrupts entered amounts.
Full digit/separator/calendar tables: `references/numerals-and-calendars.md`.

## Bidi isolation — mixed-script runs

```dart
const _lri = '⁦'; // LEFT-TO-RIGHT ISOLATE
const _rli = '⁧'; // RIGHT-TO-LEFT ISOLATE
const _fsi = '⁨'; // FIRST STRONG ISOLATE (unknown direction)
const _pdi = '⁩'; // POP DIRECTIONAL ISOLATE

String isolate(String run) => '$_fsi$run$_pdi';    // unknown direction
String isolateLtr(String run) => '$_lri$run$_pdi'; // known LTR (codes, numbers)
String isolateRtl(String run) => '$_rli$run$_pdi'; // known RTL

// Prefer known-direction over FSI: first-strong mis-guesses on leading punctuation.
// The isolated value is an ARB placeholder, never a hard-spliced substring:
Text(l10n.orderRef(isolateLtr(order.reference))); // "{ref} — order" reads correctly in RTL
```

Isolate at the view layer only. For a standalone field, set direction on the widget instead:
`Text(code, textDirection: TextDirection.ltr, textAlign: TextAlign.end)`. Never use legacy
`LRE/RLE/LRO/RLO` embeddings — use the isolate controls (UAX #9).

## Calendars & dates

Project a stored UTC instant into the user's chosen calendar for display only. Never persist a
calendar-specific field; never hand-roll Jalali/Gregorian conversion (use `intl`, `shamsi_date`,
`hijri`). First-day-of-week and weekend are locale-aware — compute buckets on canonical dates,
label per locale. See `examples/numeral_normalizer.dart` and `references/numerals-and-calendars.md`.

## CustomPainter with a locale-invariant coordinate space

If a painter owns a fixed coordinate grid, pin **only that subtree** to
`Directionality(textDirection: TextDirection.ltr, …)` so ambient RTL cannot flip the geometry;
chrome around it still mirrors via logical insets. Map pointers through the painter's own transform
on `localPosition` — never invert `dx` for RTL. Feed the painter the same `numberFormatFor(locale)`
so on-canvas numerals match the chrome. Chart chrome (axes, legend, time axis) mirrors, but the
plotted data itself never flips. Details in `custom-canvas-and-gestures`.

## Anti-patterns

- `Text('Order details')` — a hardcoded literal with no gen-l10n route. Read `l10n.orderDetails`.
  (A precise hardcoded-UI-string grep is false-positive-prone, so this one is caught in review, not by
  `check_i18n_bans.sh` — that gate covers geometry, icons, number splices, legacy bidi, and font fetch.)
- Authoring a translation file first, or letting a missing key degrade to null — the template is
  `en` and `nullable-getter: false` makes a missing key a compile error.
- `count == 1 ? 'item' : 'items'` — a two-way ternary can't hold Arabic `few`/`many`; use ICU `plural`.
- `Text('$count items')` or `'Total ' + n.toString()` — concatenated fragments + raw ASCII digits;
  wrong word order in RTL and wrong digit block. One ICU message + `numberFormatFor`.
- Persian showing `٤٥٦` (Arabic-Indic) or Arabic showing `۴۵۶` (Extended Arabic-Indic) — distinct
  Unicode blocks; format via the `fa` formatter for fa/ckb and the `ar` formatter for ar.
- `EdgeInsets.only(left: 16)` / `Alignment.centerLeft` / `Positioned(left:)` — physical sides bypass
  mirroring (fails the grep).
- Wrapping the app root in `Directionality(TextDirection.rtl)` to "turn on RTL" — RTL comes from the
  locale; a hardcoded root hides physical-side bugs and breaks LTR islands.
- `[...AppLocalizations.localizationsDelegates, GlobalMaterialLocalizations.delegate, …]` — that
  spread **already contains** the three `Global*` delegates, so re-appending them duplicates them
  and puts them ahead of any delegate you vendor. `Localizations._loadAll` takes the first delegate
  of a type that claims the locale; yours is never reached.
- Vendoring only a `MaterialLocalizations` delegate for an unsupported locale — the crash goes away
  and the app renders backwards instead. Vendor the `WidgetsLocalizations` one too, or neither.
- Trusting "supports Arabic" on a foundry page for a Sorani, Urdu or Pashto build — assert the
  language's own letters against the bundled face's `cmap`.
- Letting isolate characters (`U+2066`–`U+2069`) reach storage/search/export — strip at the boundary.
- Rendering RTL/numeral goldens with `Ahem` — Persian digits and Arabic-script shaping are never
  exercised. Load real bundled fonts (see `widget-golden-and-a11y-testing`).
- `int.parse(userText)` on a raw numeric field — normalize to ASCII first.

## Definition of done

- [ ] Key authored in the template `app_en.arb` with `@description` + typed placeholders; every other
      locale has the same key; `check_arb_parity.sh` passes.
- [ ] `nullable-getter: false`; string read only through `AppLocalizations`; no literal in
      `Text`/`tooltip`/`label`/`hint`/`semanticsLabel`.
- [ ] Count-bearing strings are ICU `plural` (all six Arabic categories where Arabic ships); no
      ternary, no `$count` splice.
- [ ] Numerals/dates come from `numberFormatFor(locale)` / `intl` `DateFormat`, injected as
      placeholders — never hand-formatted ASCII, never the wrong digit block; a painter shares the
      same formatter.
- [ ] Every numeric input passes `normalizeToAscii` before parse/store; round-trip tested.
- [ ] All geometry is directional (`start`/`end`, `Icons.adaptive`); no physical-side API survives
      the grep; direction comes from the locale, not a hardcoded root `Directionality`.
- [ ] Every mixed-script run goes through the one FSI/PDI helper (known-direction over FSI); no raw
      concatenation, no legacy `LRE/RLE`; isolates never reach storage.
- [ ] Dates/numbers stored canonical (UTC epoch + ASCII); calendars/numerals project only at render;
      reminders schedule off the epoch.
- [ ] Fonts cover all shipped scripts with fallback; no runtime font fetch; RTL + numeral goldens run
      on real fonts. Coverage asserted from each bundled face's `cmap` — the language's own letters,
      not just its script.
- [ ] Every shipped locale is either in `flutter_localizations` or has all three delegates vendored
      ahead of the `Global*` ones; `Directionality.of` and a `MaterialLocalizations` string are
      asserted for each; platform manifests (`CFBundleLocalizations`) list every tag.

## Related skills

- See `accessibility-as-code` for `Semantics` roles/labels and reading a11y state from `MediaQuery`.
- See `widget-golden-and-a11y-testing` for the RTL/numeral golden lanes (real fonts, not Ahem) and
  the textScaler overflow matrix.
- See `custom-canvas-and-gestures` for the LTR-pinned painter, shared transform, and pointer mapping.
- See `value-objects-money-and-units` for canonical integer-minor-unit storage rendered here.
- See `local-notifications-scheduler` for scheduling off canonical instants, not calendar arithmetic.
- See `widget-composition` for the directional layout primitives these strings sit inside.
- See `scaffold-feature-module` for wiring a new feature's strings through this ARB workflow.
- See `design-system-structure` (`references/typography-and-fonts.md`) for where the per-script
  fallback cascade is declared and how bundled glyph coverage is proved.
- See `app-startup-and-bootstrap` for restoring the persisted locale before the first frame — the
  only way a locale the OS cannot select is ever reachable.

## References

- Flutter internationalization: https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization
- gen-l10n / `l10n.yaml` options: https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization#configuring-the-l10nyaml-file
- ARB format: https://github.com/google/app-resource-bundle/wiki/ApplicationResourceBundleSpecification
- ICU `MessageFormat` (plural/select): https://unicode-org.github.io/icu/userguide/format_parse/messages/
- CLDR plural rules: https://cldr.unicode.org/index/cldr-spec/plural-rules
- `intl` package (NumberFormat, DateFormat, Bidi): https://pub.dev/packages/intl
- Unicode Bidi Algorithm (UAX #9), isolate controls: https://www.unicode.org/reports/tr9/
- `Directionality`, `EdgeInsetsDirectional`: https://api.flutter.dev/flutter/widgets/Directionality-class.html
- `LocalizationsDelegate` (vendoring one): https://api.flutter.dev/flutter/widgets/LocalizationsDelegate-class.html
- Supported locale list + adding an unsupported one: https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization#advanced-locale-definition
- OpenType `cmap` table (glyph coverage): https://learn.microsoft.com/en-us/typography/opentype/spec/cmap
