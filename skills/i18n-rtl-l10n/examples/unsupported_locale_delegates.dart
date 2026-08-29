// Demonstrates shipping a locale `flutter_localizations` has no data for:
// the three vendored delegates, runtime neighbour resolution, and the delegate
// ordering that makes them actually take effect.
//
// The locale here is `ckb` (Sorani Kurdish) because it is a real, current gap —
// measured on Flutter 3.44.6, `kMaterialSupportedLanguages` holds 82 language
// codes and contains neither `ckb` nor `ku`. Substitute your own tag; nothing
// below is Kurdish-specific except the neighbour list.
//
// See references/unsupported-locales.md for the probe, the failure modes and
// the test matrix.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// The tag this file vendors delegates for.
const String kVendoredLanguageCode = 'ckb';

/// Locales `flutter_localizations` *does* ship that are nearest to the vendored
/// one — same script, same numerals, closest vocabulary — best first.
///
/// Borrowed chrome is a deliberate compromise: the app's own strings are
/// translated, Flutter's handful arrive in a related language. That beats
/// English chrome inside an RTL app, and it beats asserting.
const List<Locale> _scriptNeighbours = <Locale>[Locale('fa'), Locale('ar')];

/// Picks the first neighbour [delegate] actually supports.
///
/// Resolved at runtime rather than hardcoded, so dropping a neighbour from the
/// SDK degrades instead of breaking.
Locale _resolveNeighbour(LocalizationsDelegate<dynamic> delegate) {
  for (final neighbour in _scriptNeighbours) {
    if (delegate.isSupported(neighbour)) return neighbour;
  }
  // Unreachable while flutter_localizations ships fa and ar, and asserted in a
  // test. If it ever is reached, English chrome in an RTL app is a visible bug
  // rather than a crash — the right failure of the two.
  return const Locale('en');
}

/// Serves `MaterialLocalizations`.
///
/// Without it `Localizations._loadAll` filters every Material delegate out and
/// the first `Tooltip`, `SnackBar` or `AppBar` back button asserts — a crash in
/// one locale that an English test run never sees.
class VendoredMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  /// Creates the delegate.
  const VendoredMaterialLocalizationsDelegate();

  // Claim ONLY this locale. An over-claiming delegate would hijack the
  // neighbour from the built-in that has real strings for it.
  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == kVendoredLanguageCode;

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(
        _resolveNeighbour(GlobalMaterialLocalizations.delegate),
      );

  @override
  bool shouldReload(VendoredMaterialLocalizationsDelegate old) => false;
}

/// Serves `CupertinoLocalizations`, the same way.
class VendoredCupertinoLocalizationsDelegate
    extends LocalizationsDelegate<CupertinoLocalizations> {
  /// Creates the delegate.
  const VendoredCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == kVendoredLanguageCode;

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(
        _resolveNeighbour(GlobalCupertinoLocalizations.delegate),
      );

  @override
  bool shouldReload(VendoredCupertinoLocalizationsDelegate old) => false;
}

/// Supplies `WidgetsLocalizations` — and therefore the ambient `TextDirection`.
///
/// **It cannot be omitted.** `_WidgetsLocalizationsDelegate.isSupported`
/// returns `true` for *every* locale (measured, including the nonsense code
/// `zz`) and `DefaultWidgetsLocalizations.textDirection` is hardcoded
/// `TextDirection.ltr`. A build that vendors only the Material half runs fine
/// and **reads backwards** — the silent half of the same bug, and the one no
/// crash report would ever surface.
///
/// It delegates rather than hand-rolling a direction because
/// `GlobalWidgetsLocalizations` derives direction from the locale and the
/// neighbour is already RTL. Writing `TextDirection.rtl` here would be a second
/// place the answer lives.
class VendoredWidgetsLocalizationsDelegate
    extends LocalizationsDelegate<WidgetsLocalizations> {
  /// Creates the delegate.
  const VendoredWidgetsLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      locale.languageCode == kVendoredLanguageCode;

  @override
  Future<WidgetsLocalizations> load(Locale locale) =>
      GlobalWidgetsLocalizations.delegate.load(
        _resolveNeighbour(GlobalWidgetsLocalizations.delegate),
      );

  @override
  bool shouldReload(VendoredWidgetsLocalizationsDelegate old) => false;
}

/// Builds the list `MaterialApp.localizationsDelegates` is handed.
///
/// **Order is the mechanism.** `Localizations._loadAll` takes the *first*
/// delegate of a type that reports the locale supported, so the vendored ones
/// must come before the `Global*` ones.
///
/// [appDelegates] is `AppLocalizations.localizationsDelegates`, which **already
/// contains the three `Global*` delegates** — gen-l10n emits them. They are
/// stripped and re-added at the end rather than spread as-is, because spreading
/// would put them ahead of the vendored ones. That happens to work today only
/// because they decline the locale, and "it works because the wrong delegate
/// said no" is not an ordering guarantee.
List<LocalizationsDelegate<dynamic>> localizationsDelegatesFor(
  Iterable<LocalizationsDelegate<dynamic>> appDelegates,
) {
  const globals = <LocalizationsDelegate<dynamic>>[
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ];

  return <LocalizationsDelegate<dynamic>>[
    ...appDelegates.where(
      (delegate) => !globals.any((global) => identical(global, delegate)),
    ),
    const VendoredWidgetsLocalizationsDelegate(),
    const VendoredMaterialLocalizationsDelegate(),
    const VendoredCupertinoLocalizationsDelegate(),
    ...globals,
  ];
}

// Usage:
//
//   MaterialApp(
//     localizationsDelegates:
//         localizationsDelegatesFor(AppLocalizations.localizationsDelegates),
//     supportedLocales: AppLocalizations.supportedLocales,
//     locale: ref.watch(localeProvider), // null => follow the device
//   );
//
// The tests that matter (references/unsupported-locales.md has the full list):
//
//   - GlobalMaterialLocalizations.delegate.isSupported(Locale(tag)) is FALSE —
//     so this whole file becomes a deliberate deletion when the SDK catches up.
//   - Directionality.of() is asserted for EVERY supported locale, which is what
//     catches the silent-LTR half.
//   - The vendored delegates precede the Global* ones in the built list.
