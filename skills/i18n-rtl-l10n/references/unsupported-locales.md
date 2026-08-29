# Locales `flutter_localizations` does not ship

gen-l10n localizes **your** strings. It does nothing for **Flutter's** — the tooltip on a
`Tooltip`, the "dismiss" on a `SnackBar`, the `AppBar` back button's semantic label, the
`showDatePicker` chrome, and the ambient `TextDirection`. Those come from
`flutter_localizations`, which ships a fixed set of languages, and yours may not be in it.

`ckb` (Sorani Kurdish) is the worked example below. The same hole swallows Amharic variants,
Tigrinya, Dhivehi, Sindhi and plenty more — the procedure is identical for any of them.

## First, probe. Don't assume.

Six independent tables decide whether a locale works. Check each; they disagree.

| Table | Where | `ckb`, measured on Flutter 3.44.6 / `intl` 0.20.2 |
| --- | --- | --- |
| `kMaterialSupportedLanguages` | `flutter_localizations/lib/src/l10n/generated_material_localizations.dart` | **Absent.** 82 codes; `en` `de` `fa` `ar` present, `ckb` and `ku` are not |
| `kWidgetsSupportedLanguages` | `generated_widgets_localizations.dart` | **Absent.** Same 82 |
| `kCupertinoSupportedLanguages` | `generated_cupertino_localizations.dart` | **Absent** |
| `NumberSymbols` | `intl/lib/number_symbols_data.dart` | **Absent** — no `"ckb"` entry, so digits silently fall back to Latin |
| `DateSymbols` | `intl/lib/date_symbol_data_local.dart` | **Absent** |
| `Bidi.isRtlLanguage` | `intl/lib/src/intl/bidi.dart` | **Present** — the regex lists `ckb` |

Read that last row against the others. `intl` agrees the locale is right-to-left while shipping
no symbol data for it. Nothing raises; you get an RTL language rendered with `0123456789`.
Probe the tables in a test rather than trusting a changelog:

```dart
test('the SDK still lacks the locale this app vendors delegates for', () {
  expect(GlobalMaterialLocalizations.delegate.isSupported(const Locale('ckb')), isFalse);
  expect(GlobalCupertinoLocalizations.delegate.isSupported(const Locale('ckb')), isFalse);
});
```

That test is not paranoia. It is what turns the vendored code below into a **deliberate deletion**
the day the SDK covers the locale, instead of dead code nobody dares remove.

## Two failure modes, and only one of them is loud

**Loud.** With no `MaterialLocalizations` for the locale, `Localizations._loadAll` filters every
Material delegate out and the first `Tooltip`, `SnackBar` or `AppBar` back button asserts. A crash
in one locale, which an English-only test run and an English-only manual pass both miss.

**Silent, and worse.** Direction does *not* fail the same way. Measured in
`packages/flutter/lib/src/widgets/localizations.dart`:

```dart
class _WidgetsLocalizationsDelegate extends LocalizationsDelegate<WidgetsLocalizations> {
  // Flutter's own comment: "This is convenient simplification."
  @override
  bool isSupported(Locale locale) => true;   // <- every locale. Including 'zz'.
}

class DefaultWidgetsLocalizations implements WidgetsLocalizations {
  @override
  TextDirection get textDirection => TextDirection.ltr;   // <- hardcoded
}
```

So the fallback always claims your locale and always answers LTR. A build that vendors only the
Material half stops crashing, looks fixed, and renders the entire app backwards. Nothing is
logged, no report is filed, and the developer's device never shows it.

**Both halves or neither.** Fixing Material without Widgets converts a crash into a wrong-direction
UI, which is the worse of the two outcomes.

## Vendor three delegates

`MaterialLocalizations`, `CupertinoLocalizations` and `WidgetsLocalizations`. Each borrows a
**script neighbour** — a locale `flutter_localizations` does ship that uses the same script, the
same numerals and the nearest vocabulary. For `ckb` that is `fa`, then `ar` as a second choice.

Borrowed chrome is a compromise worth naming out loud: your own strings are translated, Flutter's
handful are in a related language. That beats English chrome inside an RTL app, and it beats a
crash. See `examples/unsupported_locale_delegates.dart` for the full trio.

```dart
class VendoredWidgetsLocalizationsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  const VendoredWidgetsLocalizationsDelegate();

  // Claim ONLY your locale. A delegate that returns true for anything else
  // hijacks a locale the built-in actually has real strings for.
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ckb';

  // Delegate rather than hand-rolling a TextDirection: GlobalWidgetsLocalizations
  // derives direction from the locale, and the neighbour is already RTL. Writing
  // `TextDirection.rtl` here would be a second place the answer lives.
  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      GlobalWidgetsLocalizations.delegate.load(const Locale('fa'));

  @override
  bool shouldReload(VendoredWidgetsLocalizationsDelegate old) => false;
}
```

## Ordering is the mechanism

`Localizations._loadAll` takes the **first** delegate of a given type that reports the locale
supported. So the vendored delegates must come **before** the `Global*` ones.

The trap: `AppLocalizations.localizationsDelegates` **already contains all three `Global*`
delegates** — gen-l10n emits them into the generated file. Spreading that list and appending
yours puts the built-ins first.

```dart
// WRONG — the Global* delegates are already inside that spread, so they win.
localizationsDelegates: [
  ...AppLocalizations.localizationsDelegates,
  const VendoredWidgetsLocalizationsDelegate(),   // never reached
],
```

This "works" today only because the built-ins happen to decline the locale. *It works because the
wrong delegate said no* is not an ordering guarantee — it is one SDK release from breaking, in the
one locale nobody tests. Strip them out and re-append them last:

```dart
List<LocalizationsDelegate<dynamic>> localizationsDelegatesFor(
  Iterable<LocalizationsDelegate<dynamic>> appDelegates,
) {
  const globals = <LocalizationsDelegate<dynamic>>[
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];
  return <LocalizationsDelegate<dynamic>>[
    // the app's own gen-l10n delegate, with the built-ins removed
    ...appDelegates.where((d) => !globals.any((g) => identical(g, d))),
    const VendoredWidgetsLocalizationsDelegate(),
    const VendoredMaterialLocalizationsDelegate(),
    const VendoredCupertinoLocalizationsDelegate(),
    ...globals,
  ];
}
```

`MaterialApp` appends its own English/LTR defaults after whatever you hand it, so anything that
reaches them is a locale nobody wired.

## Numerals: pin the locale, assert the block

`NumberFormat.decimalPattern('ckb')` returns Latin digits, quietly. Pin the formatter to the
neighbour that shares the numbering system and assert the emitted codepoint range in a test —
`numberFormatFor` in `references/numerals-and-calendars.md` owns the pattern. A silent Latin
fallback must fail a test, not ship.

## A font that draws the script may not draw the language

Script coverage is not language coverage. Sorani is written in Arabic script **plus** seven letters
Persian does not use — ڕ ڵ ۆ ێ ھ ە ڤ. Faces marketed as "Arabic" routinely lack them and render
tofu. A specimen image will not show you this, because the specimen is set in Arabic.

Assert coverage from the font's **own `cmap` table**, over the bundled asset bytes:

```dart
// Parse the format-4 cmap subtable, then:
test('the bundled face draws every letter of the language, not just the script', () async {
  final coverage = await mappedCodepointsOf('AppTextBroadCoverage');
  const soraniOnly = <String, int>{
    'ڕ': 0x0695, 'ڵ': 0x06B5, 'ۆ': 0x06C6, 'ێ': 0x06CE,
    'ھ': 0x06BE, 'ە': 0x06D5, 'ڤ': 0x06A4,
  };
  final missing = soraniOnly.entries.where((e) => !coverage.contains(e.value));
  expect(missing, isEmpty, reason: 'a face that draws Persian is not thereby a face '
      'that draws Sorani — every miss is tofu on a device nobody checked');
});
```

Run the same probe over the digit block the locale renders (U+06F0–U+06F9 for `fa`/`ckb`) and its
separators (U+066B, U+066C). See `design-system-structure` → `references/typography-and-fonts.md`
for where the cascade is declared.

## Platform manifests, and the consequence nobody plans for

Add the tag to iOS `CFBundleLocalizations` or the locale is not offered at all, however complete
the Dart side is.

Then face the real consequence: **if no OS language setting can select the locale, the in-app
language override is the only way to reach it.** For a locale the platform does not know, that
picker is not polish — it is the entire delivery mechanism, and it must be reachable, persisted,
and applied before the first frame (`app-startup-and-bootstrap`). A device-locale-only app ships
a translation no user can ever see.

Label each entry with its **endonym** — `کوردیی ناوەندی`, not "Kurdish" — because the person who
needs that row is not currently reading the language the app is in.

## Definition of done

- [ ] A test asserts the SDK still lacks the locale, so the vendored code is deletable on purpose.
- [ ] All three delegates vendored — Material, Cupertino **and** Widgets.
- [ ] Each `isSupported` claims that language code only.
- [ ] The `Global*` delegates are stripped from the gen-l10n list and re-appended last; a test
      asserts the ordering, not just the membership.
- [ ] `Directionality.of` is asserted per locale across the whole supported set — the assertion
      that catches the silent-LTR half.
- [ ] `NumberFormat` is pinned to a neighbour with symbol data; a test asserts the digit block.
- [ ] Bundled font coverage asserted from the `cmap` for the language's own letters, its digits
      and its separators.
- [ ] The locale tag is in `CFBundleLocalizations`, and an in-app override can reach it.
