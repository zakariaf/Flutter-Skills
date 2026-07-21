# ARB workflow, l10n.yaml & ICU

The `l10n/` directory holds the gen-l10n inputs. `app_en.arb` is the **template**; all keys and
placeholder metadata are declared there first, then mirrored into every other locale file.

## l10n.yaml — the settings that matter

```yaml
# l10n.yaml (project or l10n-package root)
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
nullable-getter: false      # AppLocalizations.of(context) is NON-null; missing key = compile error
# untranslated-messages-file: untranslated.json  # optional CI artifact listing gaps
```

Also set `generate: true` under `flutter:` in `pubspec.yaml` so gen-l10n runs on build. `nullable-getter:
false` is the single most valuable setting: it turns a missing or mistyped key from a silent empty
widget into an analyzer error.

## The locale set (illustrative)

| File | Locale | Direction | Notes |
| --- | --- | --- | --- |
| `app_en.arb` | English | LTR | **Template** — source of truth for keys + `@` metadata |
| `app_de.arb` | German | LTR | Compound words expand; leave room, never fixed widths |
| `app_fr.arb` | French | LTR | |
| `app_fa.arb` | Persian | RTL | Persian digits typical (Extended Arabic-Indic) |
| `app_ar.arb` | Arabic | RTL | Six plural forms: zero/one/two/few/many/other |
| `app_ckb.arb` | Sorani Kurdish | RTL | Not in built-in `GlobalMaterialLocalizations` — see below |

Swap in whatever locales the app ships. The workflow is identical; only RTL locales trigger the
directional discipline.

## Step-by-step

1. **Add to the template first.** The key, plus a `@key` object declaring every placeholder and its
   `type`. Only the template needs the `@` metadata block; other locales carry only the message string.
2. **Mirror the key into every other file** with a real translation, keeping the **exact placeholder
   names** and the **same ICU structure** (same plural/select branches; branch bodies differ per language).
3. **Run parity check:** `scripts/check_arb_parity.sh` — reports keys present in the template but
   missing in a locale, extra keys, and placeholder-name mismatches.
4. **Regenerate + analyze:** `flutter gen-l10n` then `flutter analyze`. A missing key is a compile
   error thanks to codegen — the safety net.
5. **Missing-key test:** before release, instantiate every `supportedLocale` and assert all keys
   resolve (no `MissingResource`).

## ICU — always, never concatenation

Plurals and word order differ across languages; Arabic has all six CLDR plural categories. Build them
with ICU placeholders, never by gluing strings.

```json
{
  "reminderDueDays": "{count, plural, =0{Due today} =1{Due in 1 day} other{Due in {count} days}}",
  "@reminderDueDays": { "placeholders": { "count": { "type": "num" } } },

  "attachmentCount": "{n, plural, =0{No photos} =1{1 photo} other{{n} photos}}",
  "@attachmentCount": { "placeholders": { "n": { "type": "int" } } },

  "statusLabel": "{status, select, active{Active} paused{Paused} other{Unknown}}",
  "@statusLabel": { "placeholders": { "status": { "type": "String" } } }
}
```

- `select`/gender keys are **case-sensitive** — pass canonical lowercase keys.
- For Arabic, provide `zero`/`one`/`two`/`few`/`many`/`other` branches where the noun's grammar needs
  them, not just `=0/=1/other`. Treat a missing category as a release blocker, not a cosmetic gap.
- `=0`/`=1` are *exact-value* matches and win over the category branches; use them for special copy
  ("No items" vs "0 items").

## Placeholder typing

| ICU intent | `type` | Notes |
| --- | --- | --- |
| Plural / cardinal count | `num` or `int` | `int` for whole counts, `num` for measured counts |
| Interpolated free text | `String` | User content preserved verbatim; isolate it at the view (see `references/rtl-and-bidi.md`) |
| Formatted date | `DateTime` + `format` | Prefer projecting via your calendar formatter so calendar preference is honored, not a raw ARB date format |
| Formatted number/currency | `num` + `format` | Compose with `numberFormatFor`; render amount and unit/symbol as **separate isolated runs**, never hand-concatenated |

## Values and units in strings

Quantities are stored canonically (integer minor units keyed to the ISO-4217 exponent, SI ints — see
`value-objects-money-and-units`), never a float. Render the amount and the symbol/unit as separate
isolated runs (or via `NumberFormat`'s currency pattern), never hand-glued into one placeholder.

## Widget vendors a delegate for a non-built-in locale

`flutter_localizations` ships `GlobalMaterialLocalizations` for many locales but not all (Sorani
Kurdish `ckb`, for example). For such a locale, vendor a custom `LocalizationsDelegate` that borrows a
close relative's Material/Cupertino/Widgets strings, and register it alongside the `Global*` delegates:

```dart
MaterialApp(
  localizationsDelegates: const [
    ...AppLocalizations.localizationsDelegates, // includes the vendored delegate
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,        // sets ambient RTL from the resolved locale
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  locale: ref.watch(localeProvider), // null => follow the device
);
```

## Pitfalls

- Adding a key to the template only — every other locale silently falls back and ships the template
  language. `check_arb_parity.sh` catches this.
- Renaming a placeholder in one locale — breaks that translation at runtime. Keep names identical.
- Hand-building "1 day" / "2 days" — use ICU `plural`.
- Forgetting iOS `CFBundleLocalizations` for every locale — the locale is not offered on iOS even
  though Android works.

## When multi-package (workspace)

Put the ARB pipeline in one shared `l10n` package with its own `l10n.yaml` so every app and feature
package reads one catalog through a single generated `AppLocalizations`. A single-package app keeps
the ARB files in `lib/l10n/` and needs none of this — the workflow above is unchanged.
