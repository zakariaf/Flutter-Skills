# Backup, WAL & optional SQLCipher

The store is the only source of truth with no server behind it, so a verified
local backup is the real disaster-recovery guarantee. This file covers the
one correct backup primitive, WAL rules, and optional at-rest encryption.

## The backup primitive — the ONLY correct order

**Never `File.copy` a live WAL-mode DB.** Copying while writes may be in the
`-wal`/`-shm` sidecars yields a torn, corrupt, unrestorable archive — the single
most dangerous latent bug in this area.

```dart
Future<Result<BackupHandle, BackupFailure>> createBackup(File targetDir) async {
  final tmp = File(p.join(targetDir.path, 'backup.sqlite.tmp'));

  // 1. Quiesce the WAL so the file we serialize is self-contained.
  await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE);');

  // 2. VACUUM INTO — a consistent, defragmented single file. NEVER File.copy a live DB.
  await db.customStatement("VACUUM INTO '${tmp.path}';");

  // 3. Publish atomically: rename only after bytes are fully flushed.
  final finalFile = File(p.join(targetDir.path, 'backup-$stamp.sqlite'));
  await tmp.rename(finalFile.path);

  // 4. VERIFY BY REOPEN before ever reporting success.
  if (!await _verifyByReopen(finalFile)) {
    await finalFile.delete();
    return const Err(BackupFailure.verifyFailed());
  }
  return Ok(BackupHandle(finalFile));
}
```

`_verifyByReopen` opens the produced file as a fresh DB, runs
`PRAGMA integrity_check`, and asserts a manifest's row counts (and any blob
hashes) match. Only then is the backup a proven fact. A backup that was not
re-opened did not succeed — this applies to silent auto-backups too; skipping
verification "because it's automatic" ships silent unrestorable archives.

## WAL rules

| Do | Never |
|---|---|
| `wal_checkpoint(TRUNCATE)` then `VACUUM INTO` for every backup | `File.copy` a live WAL-mode DB |
| Back up when no write transaction is open | Back up mid write-transaction |
| Verify every backup, including automatic ones | Skip verification because it is automatic |
| Temp-file then atomic `rename` after the bytes flush | Write the final path incrementally |

## The plain-file backup that outranks every migration test

The highest safety-per-line item in a store with non-regenerable data is
dead simple: **before running a migration's `onUpgrade`, copy the DB file to
`backup-v{oldVersion}.sqlite`, keep the last two, and expose "Restore previous
data".** (This copy is safe because it happens with no migration transaction
open and the DB quiesced — distinct from a *live* backup, which must use
`VACUUM INTO`.) Migration tests protect against the bugs you enumerated; the
pre-migration backup protects against the one you did not — which, with no
telemetry, is the entire invisible category. They are complements, never
substitutes. See `run-migration` for the migration ritual itself.

## iOS: keep the working store out of iCloud

Set `NSURLIsExcludedFromBackupKey` on the working DB and media directories so the
on-device store is not swept into an iOS device backup unintentionally; the app's
own verified archive is the intended transfer path. Store the DB in
`getApplicationSupportDirectory()` (backed up like Documents but not user-visible
in Files), not `getApplicationDocumentsDirectory()`.

## Export / import portability

If you offer a portable export alongside the archive, make it **locale-neutral**:
UTF-8 (+ BOM if spreadsheets must read it), Western digits, ISO-8601 instants,
SI/canonical units, integer minor-unit money — so it round-trips losslessly
regardless of UI locale. Import **normalizes numerals before parsing** (see
`i18n-rtl-l10n`), runs as one atomic transaction preceded by an auto-backup, is
idempotent via a `dedupe_key`, and neutralizes spreadsheet formula injection
(prefix a leading `= + - @` cell with a quote).

## Optional: at-rest encryption (SQLCipher)

At-rest encryption is **opt-in defense-in-depth**, not the app's correctness floor
(WAL + transactions are) and not an anti-piracy or entitlement mechanism. If you
adopt it, three lessons carry over regardless of the exact library:

1. **Key first.** `PRAGMA key` (or the build-hook equivalent) must be the FIRST
   statement on every raw connection, before any other query. Key after a query,
   or not at all, and you silently get an unusable — or plaintext — DB.
2. **Assert the cipher is real.** Immediately after keying, assert
   `PRAGMA cipher_version` (or `PRAGMA cipher`) is non-empty. Empty means a stock
   `sqlite3` won the native link and the store is silently plaintext — throw and
   refuse to open, never proceed.
3. **Prove the header is never plaintext.** A blocking test reads the first 16
   bytes of the raw DB file and fails if they equal `SQLite format 3\000`.

```dart
setup: (raw) {
  raw.execute("PRAGMA key = \"x'$hexKey'\";"); // 1. KEY FIRST
  final cipher = raw.select('PRAGMA cipher_version;');
  if (cipher.isEmpty) {
    throw StateError('Encryption library missing — refusing to open plaintext DB');
  }
  raw.execute('PRAGMA journal_mode = WAL;'); // side files inherit the cipher
  raw.execute('PRAGMA foreign_keys = ON;');
},
```

- Read the key on the **main isolate** (platform secure-storage channels are
  main-isolate only) and pass the bytes into any background DB isolate.
- Change the key with `PRAGMA rekey`, never a re-encrypt-by-copy.
- The master key should not live *only* in Keychain/Keystore (OS updates,
  biometric re-enrollment, and restore can drop it) — wrap it with a
  user-recoverable secret if the data is irreplaceable.
