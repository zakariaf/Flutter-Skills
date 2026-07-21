# Numerals & calendars — projection, format AND parse

All timestamps are stored canonically as `dateTime.toUtc().millisecondsSinceEpoch`; all numbers are
stored as ASCII/Latin digits. Calendars and numeral systems are **pure display/input projections**
chosen from the user's persisted preferences. Never persist a calendar-specific field or native
numerals. **Never schedule off Jalali/Hijri arithmetic** — trigger off epoch/`DateTime` so
leap/month-length quirks stay calendar-independent.

## The four digit systems

| System | 0–9 | Unicode range | Locale(s) |
| --- | --- | --- | --- |
| Western Arabic (Latin) | 0123456789 | U+0030–0039 | Canonical storage/export form |
| Eastern Arabic-Indic | ٠١٢٣٤٥٦٧٨٩ | U+0660–0669 | ar |
| Extended Arabic-Indic (Persian) | ۰۱۲۳۴۵۶۷۸۹ | U+06F0–06F9 | fa, ckb |
| Devanagari | ०१२३४५६७८९ | U+0966–096F | hi |

> **Persian and Eastern-Arabic are DISTINCT code points and distinct glyphs for 4, 5, 6** (Persian
> ۴۵۶ vs Eastern-Arabic ٤٥٦). Showing `٤٥٦` to a Persian/Kurdish reader is a defect. `normalizeToAscii`
> must handle both ranges separately — mapping only one silently drops the other.
>
> **Devanagari is listed for completeness; the illustrative `normalizeToAscii` below folds only the
> RTL Arabic/Persian ranges.** When `hi` actually ships, add the same fold for U+0966–096F (and a `hi`
> branch to `numberFormatFor`) — otherwise a Hindi user's Devanagari numerals fail the parse.

## Format — pin the numbering system

`intl` emits each locale's native digits from that locale's **own number-symbol data**, not from a
`-u-nu-` extension — the unicode `-u` extension is dropped during `verifiedLocale` fallback, so
`'fa-u-nu-arabext'` and bare `'fa'` behave identically, and a `-u-nu-` on a locale `intl` has no
symbols for gains nothing. The real risk: a locale `intl` lacks symbols for (e.g. `ckb`) resolves to
the default (`en`) and silently emits **Latin** digits. Pin those to a covered base locale that shares
the numbering system (`ckb`→`fa`). Use the SAME formatter for chrome and any canvas painter.

```dart
NumberFormat numberFormatFor(Locale locale) => switch (locale.languageCode) {
      'fa' => NumberFormat.decimalPattern('fa'),   // ۰۱۲۳۴۵۶۷۸۹ (arabext)
      // ckb has no intl number symbols — borrow fa (same arabext block + separators).
      'ckb' => NumberFormat.decimalPattern('fa'),
      'ar' => NumberFormat.decimalPattern('ar'),   // ٠١٢٣٤٥٦٧٨٩ (arab)
      _ => NumberFormat.decimalPattern('en'),       // Western (en, de, fr)
    };
```

Optionally honor a user "Western digits" toggle by passing `'en'` regardless of locale. Technical IDs
(codes, references) render Western digits regardless of the toggle.

## Separators — the trap

| Style | Decimal | Grouping | Example (1234567.5) |
| --- | --- | --- | --- |
| English (US/UK) | `.` | `,` every 3 | `1,234,567.5` |
| German / French | `,` | `.` / thin space every 3 | `1.234.567,5` |
| Persian / Arabic | `٫` U+066B | `٬` U+066C every 3 | `۱٬۲۳۴٬۵۶۷٫۵` |
| Indian (lakh/crore) | `.` | `2-2-3` grouping | `12,34,567.5` |

> **`1٫5` means 1.5, not 15.** The Persian/Arabic decimal `٫` (U+066B) and grouping `٬` (U+066C) must
> never be confused. Normalizing digits but not separators silently corrupts entered amounts —
> `double.parse` then throws or yields the wrong number.

## Parse — normalize FIRST, always

```dart
String normalizeToAscii(String input) {
  final sb = StringBuffer();
  for (final r in input.runes) {
    if (r >= 0x0660 && r <= 0x0669) {        // Eastern-Arabic ٠-٩
      sb.writeCharCode(0x30 + (r - 0x0660));
    } else if (r >= 0x06F0 && r <= 0x06F9) { // Persian ۰-۹
      sb.writeCharCode(0x30 + (r - 0x06F0));
    } else if (r == 0x066B) {                // ٫ decimal -> '.'
      sb.write('.');
    } else if (r == 0x066C) {                // ٬ grouping -> drop
      continue;
    } else {
      sb.writeCharCode(r);
    }
  }
  return sb.toString();
}
// double.parse(normalizeToAscii(text)) — NEVER int.parse(raw): a Persian/Arabic soft keyboard
// yields ۱۲۳ / ١٢٣ and '1٫5', all of which fail int.parse.
```

**Round-trip test:** `numberFormatFor(Locale('fa')).format(12345)` → `normalizeToAscii` → `.parse` →
`12345`. Table-test both digit ranges and both separators. **Also assert the digit block per shipped
locale** — that `numberFormatFor` for `fa`/`ckb` emits U+06Fx and `ar` emits U+066x — so a silent
Latin fallback (e.g. if `ckb` were left unmapped) fails a test rather than shipping wrong numerals.

## Calendars

| Kind | Library | Projection notes |
| --- | --- | --- |
| Gregorian | `intl` (`DateFormat`) | Canonical storage calendar; baseline, no conversion |
| Jalali / Shamsi | `shamsi_date` | Astronomical Nowruz leap rule; short-month clamp. Persian digits typical |
| Hijri | `hijri` (Um Al-Qura) | ~354-day year, variable months; add the user ±day offset before projecting |

```dart
// Project the ASCII digits libraries emit into the locale's numeral block, reusing
// the ONE formatter so a projected date's digits match the rest of the chrome.
String localizeDigits(String s, String locale) {
  final fmt = numberFormatFor(Locale(locale));
  final native = {for (var d = 0; d <= 9; d++) '$d': fmt.format(d)};
  return s.replaceAllMapped(RegExp(r'[0-9]'), (m) => native[m[0]]!);
}

String formatDate(DateTime utc, CalendarKind kind, String locale, {int hijriDayOffset = 0}) {
  final local = utc.toLocal();
  switch (kind) {
    case CalendarKind.gregorian:
      return DateFormat.yMMMMd(locale).format(local); // intl localizes digits + months
    case CalendarKind.jalali:
      final j = Jalali.fromDateTime(local);
      // shamsi_date emits ASCII digits — project them to the locale's block.
      return localizeDigits('${j.formatter.yyyy}/${j.formatter.mm}/${j.formatter.dd}', locale);
    case CalendarKind.hijri:
      HijriCalendar.setLocal(locale); // localized month names (e.g. 'ar'); else English
      final h = HijriCalendar.fromDate(local.add(Duration(days: hijriDayOffset)));
      return localizeDigits(h.toFormat('dd MMMM yyyy'), locale); // digits still need projecting
  }
}
```

- **Never hand-roll** Jalali/Gregorian conversion (leap-year/epoch bugs) — use the libraries.
- **Hijri offset:** Um Al-Qura vs moon-sighting can differ ±1 day; expose a persisted, user-settable
  ±day offset (include it in backups) or users report "wrong date."
- **First day of week / weekend** are locale-aware (Saturday start for fa/ar) — compute buckets on
  canonical dates, label per locale.
- **Recurrence** ("every 6 months", calendar-anchored due date) resolves in the user's calendar with
  short-month clamping, then re-anchors from actual completion — but the fired trigger is still an
  absolute epoch instant. See `local-notifications-scheduler`.

## Export

CSV/JSON writes an unambiguous ISO-8601/epoch canonical value (optionally plus a localized display
string); the importer round-trips native text, native digits, and localized separators back to
canonical. CSV gets a UTF-8 BOM so a spreadsheet does not mojibake non-Latin scripts.
