// A streaming RFC 4180 CSV writer with the two independent escapes applied in
// the right order: formula-injection neutralization FIRST (safety), then quoting
// (correctness). Rows stream through an IOSink — nothing is assembled in memory —
// and values are canonical, never localized.
//
// Domain is neutral (Note). This artifact is an EXPORT: it is never a restore
// source (see the backup envelope for that).

import 'dart:io';

/// A row of already-canonical strings: integer minor units, SI integers,
/// ISO-8601 UTC instants, untranslated enum codes, stable ids. Formatting for
/// humans happens only in the PDF/report path, never here.
typedef CsvRow = List<String>;

/// Characters a spreadsheet treats as the start of a formula. A cell of user
/// text beginning with one of these becomes executable in the recipient's
/// spreadsheet — this is a code-execution vector, not a cosmetic issue.
const _formulaLeaders = {'=', '+', '-', '@', '\t', '\r'};

/// Escape 1 — neutralize a formula leader by prefixing an apostrophe, which
/// spreadsheets consume as "this cell is text". Applied BEFORE quoting.
String _neutralize(String field) =>
    field.isNotEmpty && _formulaLeaders.contains(field[0]) ? "'$field" : field;

/// Escape 2 — RFC 4180: quote when the field contains the delimiter, a quote,
/// CR or LF; double any embedded quote. Leading/trailing spaces and embedded
/// newlines are preserved verbatim — trimming them silently edits user data.
String _quote(String field) {
  final needsQuotes = field.contains(',') ||
      field.contains('"') ||
      field.contains('\r') ||
      field.contains('\n');
  if (!needsQuotes) return field;
  return '"${field.replaceAll('"', '""')}"';
}

String encodeCsvField(String field) => _quote(_neutralize(field));

/// Writes rows to [target] as UTF-8 CSV with CRLF record separators.
///
/// [withBom] is a TARGET-SPECIFIC choice, not a default: a BOM makes some
/// spreadsheet apps read UTF-8 correctly and makes strict parsers treat it as
/// data in the first field. Pick per export target and test in that tool.
///
/// Publishing is the caller's job: write to a temp file, then rename (see
/// backup_envelope.dart) so a crash mid-write can never publish a partial file.
Future<void> writeCsv(
  File target,
  CsvRow header,
  Stream<CsvRow> rows, {
  bool withBom = false,
}) async {
  final sink = target.openWrite();
  try {
    if (withBom) sink.write('﻿');
    sink.write('${header.map(encodeCsvField).join(',')}\r\n');
    // Streamed row by row: a 100k-row export built in a StringBuffer OOMs the
    // cheapest device you support.
    await for (final row in rows) {
      sink.write('${row.map(encodeCsvField).join(',')}\r\n');
    }
    await sink.flush();
  } finally {
    await sink.close(); // closed on every path, including a mid-stream throw
  }
}

// --- What the tests must cover (see SKILL.md "Tests that must exist") --------
//
//   encodeCsvField('=HYPERLINK("http://x","c")') starts with an apostrophe
//   encodeCsvField('a,b"c\nd')                   round-trips through a real parser
//   encodeCsvField('  padded  ')                 keeps both spaces
//   encodeCsvField('مرحبا‏')                keeps the bidi mark byte-for-byte
//   encodeCsvField('')                           stays distinguishable from null
