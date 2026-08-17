---
name: data-export-and-restore
description: >-
  Enforces user-facing data portability in an offline-first app — backup/restore (exact,
  machine round-trippable) kept strictly separate from export/report (human, lossy,
  never a restore source); a versioned envelope carrying formatVersion, schemaVersion,
  appVersion, exportedAtUtc and a payload checksum so a restore refuses a file from a
  newer app instead of corrupting the database; restore as an all-or-nothing import into
  a staging database swapped in only after validation; canonical values in machine
  formats (integer minor units, SI integers, ISO-8601 UTC, stable ids) and never
  localized numerals; RFC 4180 CSV quoting plus the =/+/-/@ formula-injection escape;
  streaming writes published by atomic rename; the share sheet behind an injected
  Gateway; and an export→import→export round-trip test on a hostile fixture. Use when
  adding or changing export, backup, import, restore, share, or CSV/JSON/PDF output,
  writing an import validator or merge-vs-replace policy, or handling a picked file.
---

# Data export and restore

In an app with no server, the export file is the only copy of a user's data that can
outlive the phone, and restore is the only recovery path they can invoke themselves.
Both are dangerous in opposite directions: a lossy export silently becomes someone's
backup, and a half-applied restore destroys the very database it was meant to protect.
This skill governs the *portable* artifacts; the on-device `VACUUM INTO` snapshot and
WAL rules belong to `persistence-drift`.

Depth lives in `references/formats-and-encoding.md` (CSV/JSON/PDF mechanics) and
`references/restore-and-merge-policy.md` (validation ladder, merge strategies).

## Non-negotiable rules

1. **Backup and export are two different features — never conflate them.** *Backup* is
   exact, machine-read, round-trippable, and the only thing restore accepts. *Export*
   (CSV for a spreadsheet, PDF for a human) is an interop artifact, lossy by design,
   and must be refused as a restore source. WHY: the moment a CSV is restorable, a
   format built for readability becomes the file someone's records depend on.
2. **Every backup carries an envelope, and restore reads it first.** `formatVersion`,
   `schemaVersion`, `appVersion`, `exportedAtUtc`, a checksum over the payload, then the
   payload. Restore verifies the checksum, refuses `schemaVersion` **greater** than the
   app's with a plain message, and migrates an older payload through the *same*
   forward-only path as the database (`run-migration`). WHY: an unversioned file cannot
   be refused, only misread.
3. **Restore is all-or-nothing and never edits the live database in place.** Import
   into a fresh staging database, validate everything, close every handle, then publish
   by atomic rename with the previous file kept as a rollback until the new one opens
   cleanly. WHY: a partial restore is worse than a failed one — it leaves a state the
   user cannot describe and you cannot reproduce.
4. **Machine formats carry canonical values only.** Integer minor units, SI integers,
   ISO-8601 UTC instants, stable ids, untranslated enum *codes*. Never a localized
   numeral, a formatted date, a currency symbol, or a translated label in a file that
   will be parsed. Localize only in human-facing exports, which are never re-imported.
   WHY: `١٢٫٥` and `12.5` and `12,5` are the same quantity and three different parses.
5. **Identity is content-assigned, never a rowid.** Every exportable row carries a
   stable id (UUID/ULID) minted at creation. WHY: re-importing the same file must be
   idempotent — with autoincrement ids it duplicates every record instead.
6. **State the merge policy and show it before it runs.** Replace-all (wipe then
   import) and merge-by-id (last-write-wins on a stored `updatedAtUtc`) are different
   promises; the confirmation names which one is about to happen and what will be lost.
   WHY: "Restore" reads as "add my data back" to a user who is about to lose a week.
7. **Stream to a temp file, publish by rename.** Build the artifact through an `IOSink`
   into the app's own temp directory and rename it into place only when the last byte
   is flushed. WHY: a 100k-row export assembled in a `String` OOMs a cheap phone, and a
   half-written file must never be shareable.
8. **Nothing leaves the sandbox without an explicit user action, through an injected
   Gateway.** No auto-upload, no background sync, no "helpful" cloud copy. The share
   sheet and file-save picker sit behind a `ShareGateway`/`FileExportGateway`
   (`service-boundary-and-native`), faked in tests.
9. **CSV is escaped twice: RFC 4180 *and* against formula injection.** Quote any field
   containing the delimiter, a quote, CR or LF, doubling embedded quotes; and neutralize
   a leading `=`, `+`, `-`, `@`, tab or CR so a spreadsheet renders the text instead of
   executing it. WHY: an unescaped cell is a code-execution vector in the recipient's
   spreadsheet, and a lost row in yours.
10. **Export and restore return typed results, never throw at the UI.**
    `Result<ExportArtifact, ExportFailure>` / `Result<RestoreReport, RestoreFailure>`
    with a distinct failure per refusal reason (checksum, unsupported version,
    malformed payload, no space, permission denied). WHY: "Restore failed" with no
    reason is indistinguishable from data loss to the person reading it.
11. **A failed export leaves no artifact.** Delete the temp file on every failure path
    and never publish a partial one. WHY: a truncated file that looks like a backup is
    the failure mode that surfaces months later.
12. **Say what an export is.** Exports are plaintext and unencrypted unless you built
    encryption on purpose; the UI must say so at the moment of sharing, and the claim
    must match the code (see `release-and-store-shipping` for claim wording).

## The envelope

```dart
/// The only shape restore accepts. Version fields come FIRST so a truncated or
/// foreign file is rejected by the header rather than by a mid-parse exception.
({
  int formatVersion,        // this envelope's own shape — bump independently of the DB
  int schemaVersion,        // the DB schema the payload was written from
  String appVersion,        // provenance for support, never a compatibility check
  DateTime exportedAtUtc,   // UTC, from the injected Clock
  String payloadSha256,     // checksum over the payload bytes, verified before parsing
  Map<String, Object?> payload,
});
```

`formatVersion` and `schemaVersion` are separate on purpose: the envelope can gain a
field without a database migration, and the database can migrate without changing the
file shape. A single "version" number conflates them and forces a false choice on the
next change. Complete, runnable shape: `examples/backup_envelope.dart`.

## Restore: validate, stage, swap

```dart
Future<Result<RestoreReport, RestoreFailure>> restore(File picked) async {
  // 1. Header and integrity BEFORE anything is parsed or opened.
  final envelope = readEnvelope(picked);
  switch (envelope) {
    case Err(:final failure): return Err(failure);           // malformed / bad checksum
    case Ok(:final value) when value.schemaVersion > kSchemaVersion:
      return const Err(RestoreFailure.newerThanApp());       // refuse, never guess
    case Ok():
      break;
  }

  // 2. Import into a STAGING database — the live one is never touched yet.
  final staging = await openStagingDatabase();
  final imported = await staging.transaction(() => _importAll(envelope.value.payload));
  if (imported case Err(:final failure)) {
    await staging.close();
    await deleteStagingFiles();                              // user's data still intact
    return Err(failure);
  }

  // 3. Migrate the staged copy forward through the SAME path as the app database.
  //    4. Close every handle, then publish by rename, keeping the old file until the
  //       new one opens cleanly. See references/restore-and-merge-policy.md.
  return publishStagedDatabase(staging);
}
```

The staging file, the migration path, and the rename ordering are the whole
correctness argument — a restore that writes directly into the open app database has
no failure mode that leaves the user where they started.

## Choosing a format

| Need | Format | Restorable? |
|---|---|---|
| Full-fidelity backup the app reads back | Envelope + JSON payload (or a copied DB file) | **Yes** — the only one |
| Rows for a spreadsheet or another tool | CSV, RFC 4180, canonical values | No |
| Something a human reads, prints, or files | PDF, fully localized and formatted | No |

Human-facing exports localize at the edge like any other rendering
(`value-objects-money-and-units`, `i18n-rtl-l10n`); machine formats never do. Copying
the live database file directly is a valid backup *only* through the WAL-safe primitive
in `persistence-drift` — never `File.copy` on an open database.

## Tests that must exist

- **Round trip on a hostile fixture.** Export → import into an empty database → export
  again → **byte-identical**. The fixture carries apostrophes, quotes, commas, embedded
  newlines, emoji, RTL text with bidi marks, whitespace-only strings, the largest
  supported number, a DST-ambiguous local instant, and a null-vs-empty pair. `'test1'`
  survives everything and proves nothing.
- **Idempotent re-import.** Importing the same file twice produces the same state under
  merge-by-id — not duplicates.
- **Every refusal is a test:** truncated file, flipped checksum byte, `schemaVersion`
  one higher than the app, an older `schemaVersion` that must migrate, empty payload,
  and a file that is not this format at all. Each asserts the *typed failure* and that
  the live database is byte-unchanged.
- **Failure leaves no artifact.** Force a mid-write failure; assert no publishable file
  exists in the export directory.
- **CSV escaping.** A cell containing `=cmd()`, one containing `a,b"c\nd`, and an RTL
  cell each survive a write→read round trip through a real parser.

## Anti-patterns

- **CSV as the backup format** — no envelope, no types, no versioning; it will be
  someone's only copy.
- **An unversioned export file** — the first schema change makes every existing file
  either unreadable or, worse, silently misread.
- **Restoring straight into the live database** — no rollback exists; a mid-import
  failure leaves a state nobody can describe.
- **Autoincrement rowids as export identity** — re-import duplicates everything.
- **Formatting numbers or dates in a machine format** — locale-dependent output that
  round-trips only on the machine that wrote it.
- **Building the export in a `String`/`StringBuffer`** — fine for 100 rows, an OOM
  crash at 100k, on the cheapest device you support.
- **Writing directly to the shareable path** — a crash mid-write publishes a truncated
  file that still looks like a backup.
- **Auto-uploading or auto-backing-up "for safety"** — it converts an offline app into
  a data processor, changing the store privacy declaration and breaking the claim.
- **Trusting a picked file's extension or name** — validate the envelope, not the path.
- **A generic "Import failed" message** — the user cannot tell a wrong file from lost
  data; name the reason from the typed failure.
- **Silently merging when the user expected replace (or vice versa)** — state the
  policy in the confirmation, in the same words as the code.

## Definition of done

- [ ] Backup and export are separate paths; export artifacts are refused by restore.
- [ ] Every backup carries `formatVersion`, `schemaVersion`, `appVersion`,
      `exportedAtUtc`, and a payload checksum, in that header-first order.
- [ ] Restore verifies the checksum, refuses a newer `schemaVersion`, and migrates an
      older payload through the same forward-only path as the database.
- [ ] Restore imports into a staging database and publishes by rename; a failure leaves
      the live database byte-unchanged.
- [ ] Machine formats carry canonical values and stable content ids only.
- [ ] The merge-vs-replace policy is explicit in code and named in the confirmation UI.
- [ ] Writes stream to a temp file and are published by atomic rename; failures delete
      the temp file and publish nothing.
- [ ] Share/save goes through an injected Gateway on an explicit user action; nothing
      uploads automatically.
- [ ] CSV output is RFC 4180 quoted and formula-injection escaped.
- [ ] Export/restore return typed `Result`s with one failure per refusal reason.
- [ ] Round-trip, idempotent-re-import, every-refusal, no-partial-artifact, and CSV
      escaping tests pass on a hostile fixture.

## Related skills

- `persistence-drift` — the WAL-safe on-device snapshot primitive and the DAO layer the
  importer writes through; never `File.copy` a live database.
- `run-migration` — the forward-only path an older payload is migrated through.
- `error-handling-typed-results` — the `Result`/`Failure` spine and the never-lose-data
  guarantees this feature is the user-facing end of.
- `value-objects-money-and-units` — canonical storage (minor units, SI, UTC) that makes
  a machine format round-trip.
- `i18n-rtl-l10n` — localize-at-render, and why localized numerals never enter a file.
- `service-boundary-and-native` — the `ShareGateway`/file-picker seam and its fake.
- `release-and-store-shipping` — the privacy claims an export feature must not break.
- `testing-strategy` — hostile fixtures, property/round-trip tests, injected `Clock`.

## References

- RFC 4180 — Common Format and MIME Type for CSV Files: https://www.rfc-editor.org/rfc/rfc4180
- Dart — `dart:io` `IOSink`, `File.rename`: https://api.dart.dev/stable/dart-io/File-class.html
- `path_provider` — app directories: https://pub.dev/packages/path_provider
- `share_plus` — share sheet (incl. `sharePositionOrigin`): https://pub.dev/packages/share_plus
- `file_selector` — save/open dialogs: https://pub.dev/packages/file_selector
- `crypto` — SHA-256 for the payload checksum: https://pub.dev/packages/crypto
- OWASP — CSV Injection: https://owasp.org/www-community/attacks/CSV_Injection
