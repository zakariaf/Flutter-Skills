// Demonstrates: the numeral seam — format native digits at the display edge, and
// fold native digits AND native separators back to canonical ASCII BEFORE any parse
// or storage. Plus calendar projection from a canonical UTC instant (display only).
// Storage is ALWAYS UTC epoch millis + ASCII digits; calendars/numerals are transforms.

import 'package:hijri/hijri_calendar.dart';
import 'package:intl/intl.dart';
import 'package:shamsi_date/shamsi_date.dart';

enum CalendarKind { gregorian, jalali, hijri }

/// Display: shape a number to the locale's numeral system (presentation only).
/// intl emits native digits from each locale's OWN symbol data — it drops a `-u-nu-`
/// extension during fallback — so format with a locale intl actually ships symbols for.
/// A locale intl lacks (e.g. ckb) would silently fall back to Latin, so pin it to fa.
NumberFormat numberFormatFor(String locale) => switch (locale) {
      'fa' => NumberFormat.decimalPattern('fa'), // ۰۱۲۳۴۵۶۷۸۹ (arabext)
      'ckb' => NumberFormat.decimalPattern('fa'), // no ckb symbols — same arabext block
      'ar' => NumberFormat.decimalPattern('ar'), // ٠١٢٣٤٥٦٧٨٩ (arab)
      _ => NumberFormat.decimalPattern('en'), // Western (en, de, fr)
    };

/// Project the ASCII digits calendar libraries emit into the locale's numeral block,
/// reusing the ONE formatter so a projected date's digits match the rest of the chrome.
String localizeDigits(String s, String locale) {
  final fmt = numberFormatFor(locale);
  final native = {for (var d = 0; d <= 9; d++) '$d': fmt.format(d)};
  return s.replaceAllMapped(RegExp(r'[0-9]'), (m) => native[m[0]]!);
}

/// Input: fold native digits AND native separators to canonical ASCII BEFORE parse.
/// Handles Persian (U+06F0..) and Eastern-Arabic (U+0660..) ranges SEPARATELY,
/// plus the ٫ decimal (U+066B) and ٬ grouping (U+066C) separators.
String normalizeToAscii(String input) {
  final sb = StringBuffer();
  for (final r in input.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      sb.writeCharCode(0x30 + (r - 0x0660)); // Eastern-Arabic ٠-٩
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      sb.writeCharCode(0x30 + (r - 0x06F0)); // Persian ۰-۹
    } else if (r == 0x066B) {
      sb.write('.'); // ٫ decimal -> ASCII dot
    } else if (r == 0x066C) {
      continue; // ٬ grouping -> drop
    } else {
      sb.writeCharCode(r);
    }
  }
  return sb.toString();
}

/// Parse a user-entered numeric value safely (price, quantity, measurement).
/// NEVER int.parse(raw): a Persian/Arabic soft keyboard yields ۱۲۳ / ١٢٣ and '1٫5'.
double parseNumeric(String raw) => double.parse(normalizeToAscii(raw));

/// Project a stored UTC instant into the user's chosen calendar for DISPLAY only.
/// Never schedule reminders off this — schedule off the epoch/DateTime.
String formatDate(
  DateTime utc,
  CalendarKind kind,
  String locale, {
  int hijriDayOffset = 0, // user-settable, persisted, included in backups
}) {
  final local = utc.toLocal();
  switch (kind) {
    case CalendarKind.gregorian:
      return DateFormat.yMMMMd(locale).format(local);
    case CalendarKind.jalali:
      final j = Jalali.fromDateTime(local); // shamsi_date (astronomical Nowruz)
      // shamsi_date emits ASCII digits — project them into the locale's numeral block.
      return localizeDigits(
        '${j.formatter.yyyy}/${j.formatter.mm}/${j.formatter.dd}',
        locale,
      );
    case CalendarKind.hijri:
      HijriCalendar.setLocal(locale); // localized month names (e.g. 'ar'); else English
      final h = HijriCalendar.fromDate(
        local.add(Duration(days: hijriDayOffset)), // Um Al-Qura + user offset
      );
      // toFormat still emits ASCII digits — project them at the edge too.
      return localizeDigits(h.toFormat('dd MMMM yyyy'), locale);
  }
}
