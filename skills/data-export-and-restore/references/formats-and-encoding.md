# Formats, encoding, and the share seam

## CSV — two independent escapes

**1. RFC 4180 quoting (correctness).** Quote a field when it contains the delimiter, a
double quote, CR, or LF; escape an embedded quote by doubling it. Records are separated
by CRLF. Everything else in the field is written verbatim — including leading and
trailing spaces, which a trimming writer silently destroys.

**2. Formula-injection neutralization (safety).** A spreadsheet evaluates a cell
starting with `=`, `+`, `-`, `@`, tab, or CR. A field of user text such as
`=HYPERLINK("http://…","click")` becomes a live formula in the recipient's spreadsheet.
Neutralize it *before* quoting — the usual fix is a leading apostrophe or a zero-width
prefix; either way the raw text must not reach the parser as a formula.

The two escapes are independent: quoting alone still yields an executable cell, and
neutralization alone still corrupts a field containing a comma. Do both, in that order,
and prove both with tests. Never hand-roll a reader for these files — round-trip
through a real parser in tests.

## Encoding

- **UTF-8 always.** No UTF-16, no platform default.
- **A BOM is a target-specific choice, not a default.** Some spreadsheet apps read a
  BOM-less UTF-8 file as legacy 8-bit and mangle non-ASCII; a BOM fixes that and breaks
  strict parsers that treat it as data in the first field. Pick per export target,
  document which one you chose, and test the artifact in the tool it is meant for.
- **RTL and bidi.** Text carrying an RLM/LRM or an embedded isolate must round-trip
  **byte-for-byte** — never "clean up" bidi control characters on write, and never add
  presentation-only marks to a machine format. Rendering concerns live at the UI edge
  (`i18n-rtl-l10n`), not in the file.
- **Newlines inside a field** are legal when quoted; a writer that strips them is
  silently editing user data.

## JSON payloads

- Write with a streaming encoder into the `IOSink` rather than `jsonEncode` on one giant
  object — the second one materializes the whole export in memory twice.
- Emit values in a stable order (sorted keys, sorted rows by id) so the round-trip test
  can assert **byte identity** instead of a fuzzy structural compare.
- Do not pretty-print a backup: it doubles the size for no reader.
- Numbers are integers (minor units, SI). A JSON double for money reintroduces the exact
  float problem `value-objects-money-and-units` exists to prevent.
- Instants are ISO-8601 **UTC with an explicit `Z`**; a naive local timestamp cannot be
  restored on a device in another zone, and cannot be disambiguated across a DST fold.

## PDF and other human artifacts

`pdf` + `printing` render a *presentation*: fully localized, formatted, with the
locale's numerals and calendar. This is the one export that is allowed to be lossy and
opinionated, because nothing parses it back. Build it from the same value objects, not
from the CSV, so the two exports cannot drift apart.

## The share / save seam

Both live behind an injected Gateway (`service-boundary-and-native`) so tests never open
a real sheet:

```dart
abstract interface class ShareGateway {
  Future<Result<void, ShareFailure>> shareFile(
    File file, {
    required String mimeType,
    Rect? originRect,   // iPad popover anchor — a null anchor CRASHES on iPad
  });
}
```

- **`sharePositionOrigin` is mandatory on iPad.** `share_plus` needs an anchor rect for
  the popover; omitting it throws on iPad and on nowhere else, so it survives every
  phone test and fails in review.
- **Set an honest MIME type** (`text/csv`, `application/json`, `application/pdf`) — the
  receiving app's picker depends on it.
- **Write inside the app's own temp directory** (`path_provider`), never external
  storage, and clean up published temp artifacts on next launch: they are copies of user
  data sitting outside the database's protection.
- **A save dialog (`file_selector`) is not a share.** Saving hands the file to the
  user's chosen location; sharing hands it to another app. They are different consent
  moments and often different UI affordances — do not collapse them into one button.
