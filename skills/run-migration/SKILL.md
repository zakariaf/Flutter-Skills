---
name: run-migration
description: >-
  Runs the forward-only Drift/SQLite schema-migration ritual — the most dangerous
  deterministic operation in an offline-first app: a bad migration silently destroys
  on-device rows that exist nowhere else. Enforces the exact ordered sequence: take a
  pre-migration file snapshot before the database is opened, bump schemaVersion by
  exactly one, write an append-only stepByStep forward step (never edit a shipped step,
  never write a down migration), commit the drift_dev make-migrations schema snapshot,
  regenerate, then prove it with tests covering every from→to path (incl. multi-version
  jumps), a write-at-v(n)/read-at-v(n+1) content test, PRAGMA integrity_check +
  foreign_key_check, and a forced mid-migration throw that restores the snapshot.
  Manual, side-effecting workflow. Use when adding or altering a Drift table, column,
  index, or CHECK; bumping schemaVersion; editing onUpgrade/stepByStep; or writing
  migration tests.
disable-model-invocation: true
---

# Run migration (forward-only Drift schema migration)

Apply a schema change to a local Drift/SQLite database by following the exact
ordered ritual below. In an offline-first app there is no server and no re-sync
path, so the on-device DB is the single source of truth: a migration that drops
or corrupts a column permanently destroys hand-entered records that exist
nowhere else, and with no telemetry nobody ever reports it — the user just
uninstalls. This is a **manual, low-freedom, human-run** workflow. Execute the
steps in order; do not improvise, reorder, or skip.

## Non-negotiable rules

1. **Take the pre-migration snapshot FIRST — before the database is opened.**
   Do it at the composition boundary that opens `AppDatabase`, never inside
   `onUpgrade`: `PRAGMA wal_checkpoint(TRUNCATE)` any live handle so the `-wal`
   is folded into the main file, then copy the DB file **and its `-wal`/`-shm`
   sidecars** while nothing holds the file open. Opening the database is what
   triggers the migration. Never copy or overwrite bytes under a live
   connection. The snapshot is the only "rollback" SQLite has; restore it on any
   failure.
2. **Forward-only. Never write a down migration.** SQLite has no true down
   migration and you must not pretend to. "Rollback" means restore the snapshot,
   nothing else.
3. **Steps are append-only — NEVER edit a shipped step.** Editing a released
   step corrupts data for every user who skips versions. To fix a bug in a prior
   step, add a **new** step and bump `schemaVersion` — never back-edit history.
4. **Bump `schemaVersion` by exactly one** per shipped schema change, and add the
   matching `fromNToM` branch. A schema changed without a version bump means
   **no migration runs at all** on the user's device — a CI gate must catch it.
5. **Commit the versioned schema snapshot.** Run `drift_dev make-migrations`
   (or `schema dump`), commit the exported snapshot under `drift_schemas/`, and
   commit `schema_versions.dart`. The delta becomes a reviewable diff and the
   test suite diffs live schema against it.
6. **The open is wrapped in try/restore, entirely outside any connection.** If
   opening the database throws, the migration failed and that connection is
   dead: close it, restore the snapshot file(s) taken before the open, and
   rethrow. All file operations happen while nothing has the DB open — never
   overwrite the live file from inside `onUpgrade`.
7. **A green shape check is necessary, never sufficient.** `migrateAndValidate`
   compares `CREATE` statements only — it never reads a row. A migration that
   rebuilds a table perfectly and copies zero rows passes it, green. The content
   test is the deliverable, not the shape test.
8. **No migration merges without the full test suite green** — every `from → to`
   path (including multi-version jumps), a content test per new pair,
   `PRAGMA integrity_check == ok`, `PRAGMA foreign_key_check` empty, and a
   forced mid-migration throw that restores the snapshot.
9. **Store canonical values only** in any new column (integer minor units for
   money keyed to the ISO-4217 exponent, SI integers for quantities, UTC epoch
   millis for instants, a local serial-day integer for a calendar date). Never
   add a float-money, display-string, or localized-numeral column.

## The ordered workflow

Run commands from the package that owns the database (single-package apps: the
app root; see the multi-package note at the end).

1. **Design the change** against your data-layer conventions (see
   `persistence-drift`). Edit the table class.
2. **Bump `schemaVersion` by one** in the database class.
3. **Scaffold the snapshot + step stub** and commit the generated snapshot:
   ```bash
   dart run drift_dev make-migrations
   ```
   On pinned versions where `make-migrations` is not confirmed working, use the
   three explicit commands instead (see "Snapshot commands" below).
4. **Write the append-only forward step** — add one new `fromNToM` branch. Never
   modify an existing branch. Create only the objects this version adds; never
   reference a column added in a later version.
5. **Regenerate codegen** so the generated database picks up the new version
   (invoke the `run-codegen` skill):
   ```bash
   dart run build_runner build --delete-conflicting-outputs
   ```
6. **Run the migration test suite** (see Verification). All paths, the content
   test, both PRAGMAs, and the forced-throw restore must pass.
7. **Analyze, format, and commit** the table change, the bumped `schemaVersion`,
   the new step, the committed snapshot, and the tests together in one change.

## The migration guard

The snapshot/restore lives at the composition boundary, entirely outside any
open connection; `onUpgrade` only runs the steps and checks foreign keys. Keep
this exact shape.

```dart
// ── composition boundary (app_database_opener.dart) ─────────────────────────
// Snapshot BEFORE the open, restore AFTER a failed open — no connection is ever
// live while the bytes are copied. Opening is what triggers onUpgrade.
Future<AppDatabase> openMigratedDatabase(File dbFile) async {
  // 1. Checkpoint any prior handle, then copy dbFile + its -wal/-shm sidecars.
  final snapshot = await _snapshotDbFiles(dbFile);
  final db = AppDatabase(NativeDatabase(dbFile));
  try {
    // 2. Force the migration to run NOW, while the file fallback still stands.
    await db.customStatement('PRAGMA user_version;');
    return db;
  } catch (_) {
    // 3. The failed connection is dead — close it, THEN restore with nothing open.
    await db.close();
    await _restoreDbFiles(snapshot);
    rethrow;
  }
}

// ── app_database.dart ───────────────────────────────────────────────────────
@override
int get schemaVersion => 3; // bump by exactly ONE per shipped schema change

@override
MigrationStrategy get migration => MigrationStrategy(
      onCreate: (m) => m.createAll(),
      onUpgrade: (m, from, to) async {
        // FKs OFF here — BEFORE the migration's own transaction opens, because
        // the pragma is ignored once a transaction is running.
        await customStatement('PRAGMA foreign_keys = OFF;');
        // Forward-only, append-only stepwise migration in one transaction.
        await transaction(() => _steps(m, from, to));
        // Prove the body left no dangling references — in production, not tests.
        final orphans = await customSelect('PRAGMA foreign_key_check').get();
        if (orphans.isNotEmpty) {
          throw StateError('foreign_key_check found ${orphans.length} orphans');
        }
      },
      // Pragmas are per-connection, NOT persisted — re-assert on every open.
      beforeOpen: (details) async {
        await customStatement('PRAGMA foreign_keys = ON;');
      },
    );

final _steps = stepByStep(
  from1To2: (m, schema) async { /* shipped — DO NOT EDIT */ },
  from2To3: (m, schema) async {
    // Create EXACTLY the objects this version adds.
    await m.addColumn(schema.notes, schema.notes.archivedAtUtc);
  },
);
```

## Snapshot commands (explicit form)

When not using `make-migrations`, re-run all three on **every** `schemaVersion`
bump and commit the results:

```bash
# 1. Export the schema for the CURRENT schemaVersion.
dart run drift_dev schema dump lib/data/app_database.dart drift_schemas/

# 2. Era-correct classes. --data-classes --companions is LOAD-BEARING: it emits
#    DatabaseAtV1 / DatabaseAtV2 with era-correct data classes and companions,
#    the only mechanism that lets a test write rows in the v1 world and read
#    them back in the v2 world. Without it only shape tests are possible.
dart run drift_dev schema generate --data-classes --companions \
  drift_schemas/ test/drift/generated/

# 3. Step-by-step helpers — each callback gets a schema frozen at its version.
dart run drift_dev schema steps drift_schemas/ lib/data/schema_versions.dart
```

## Verification (blocking — must pass before commit)

The suite must prove all of the following.

**Every from→to path, including the skips.** A user who ignored updates upgrades
`v1 → v3` directly — a code path nobody ran. A nested loop covers every pair
forever, so a new bump cannot forget a skip path:

```dart
group('schema shape', () {
  for (var from = 1; from < kLatestSchemaVersion; from++) {
    for (var to = from + 1; to <= kLatestSchemaVersion; to++) {
      test('v$from -> v$to', () async {
        final connection = await verifier.startAt(from);
        final db = AppDatabase(connection);
        await verifier.migrateAndValidate(db, to); // shape only — necessary, not sufficient
        await db.close();
      });
    }
  }
});
```

**The content test — the one that matters.** Write rows at v(n) with era-correct
classes, run the real migration, read back at v(n+1), assert the rows are still
there, still correct, and still in place. Use a **hostile** fixture — apostrophes,
non-ASCII, em dashes, emoji, quotes, backslashes, whitespace-only — exactly where
a `columnTransformer` or hand-rolled `INSERT ... SELECT` mangles a value. `'test1'`
survives everything and proves nothing. Put a `reason:` on every `expect` — the
failure message is the whole debugging session when no crash report is coming.

```dart
test('v2 -> v3 preserves every note, byte for byte', () async {
  final schema = await verifier.schemaAt(2);

  // Write real data with v2-era classes. newConnection() over the SAME bytes is
  // what lets different-era database objects see one database.
  final old = v2.DatabaseAtV2(schema.newConnection());
  await old.into(old.notes).insert(
        v2.NotesCompanion.insert(title: 'Blank-ish', body: const Value(' ')),
      );
  await old.close();

  // Run the REAL migration, then prove integrity — FKs are off during migration
  // and SQLite reports a dangling reference to nobody.
  final db = AppDatabase(schema.newConnection());
  await verifier.migrateAndValidate(db, 3);
  expect(await db.customSelect('PRAGMA integrity_check').get(),
      [predicate((QueryRow r) => r.data.values.first == 'ok')]);
  expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty,
      reason: 'migration left dangling references — a lost record');
  await db.close();

  // Read back with v3-era classes and assert CONTENT, not just shape.
  final now = v3.DatabaseAtV3(schema.newConnection());
  final rows = await now.select(now.notes).get();
  expect(rows, hasLength(1), reason: 'a row disappeared during migration');
  expect(rows.single.body, ' ', reason: 'whitespace-only body must survive intact');
  await now.close();
});
```

**The forced mid-migration throw restores the snapshot.** Inject a step that
throws partway, open the database through the boundary opener so the migration
runs, assert the open rethrows and that the pre-open snapshot was restored —
prior schema and rows left byte-identical. The restore path is the last line of
defense and the one that is never exercised in production until it is.

**Never mark a migration done on a green analyzer alone.** It is safe only once
the content test, both PRAGMAs, the all-paths loop, and the snapshot-restore test
are green.

### Migration mechanics that fail silently

- `PRAGMA foreign_keys` **is ignored once a transaction is open** — toggle FKs
  OFF at the top of `onUpgrade`, *before* the `transaction()` that wraps the
  steps, and re-enable them **unconditionally in `beforeOpen`** (the pragma is
  per-connection, not persisted in the file).
- Run `PRAGMA foreign_key_check` after the migration body, not only in tests.
- `flutter test` runs in a plain Dart VM where `sqlite3_flutter_libs` does
  nothing; macOS falls back to the system `libsqlite3` (real version-skew risk)
  and Linux needs `libsqlite3-dev` installed before the run.

## Anti-patterns

- **Editing a shipped step** — rewrites history for existing installs; a
  version-skipping user runs the *edited* step against old data and loses it.
- **Writing a down migration** — SQLite has none; the only rollback is the
  snapshot restore.
- **Changing the schema without bumping `schemaVersion`** — no migration runs on
  the user's device; the schema and code silently diverge.
- **Marking done on `migrateAndValidate` alone** — it is a shape comparison that
  reads zero rows; a migration that copies nothing passes it green.
- **`INSERT ... SELECT` / `columnTransformer` verified only with `'test1'`
  fixtures** — the mangling lives in apostrophes, emoji, and backslashes.
- **`select`/`update` of a not-yet-added column in an older step** — write
  queries only against the schema frozen at that step's version.
- **Assuming a pragma persists in the file** — `foreign_keys`, `synchronous`,
  and any cipher key are per-connection; re-assert on every open.
- **Leaving `eraseDatabaseOnSchemaChange` reachable in a release build** — it is
  a DEBUG-only convenience; shipped, it wipes real user data on every bump.
- **Running the migration test as one big test instead of the every-pair loop**
  — the skip paths are the ones that get forgotten on the next bump.

## Definition of done

- [ ] `schemaVersion` bumped by exactly one; a matching append-only `fromNToM`
      step added; **no** edit to any already-shipped step; no down migration.
- [ ] `make-migrations` (or the three explicit `schema` commands) re-run; the
      committed snapshot and `schema_versions.dart` are in the same change.
- [ ] The pre-migration snapshot is taken before the database is opened; the
      open is wrapped in try/restore-and-rethrow, with every file operation
      outside any live connection.
- [ ] Codegen regenerated with `--delete-conflicting-outputs`.
- [ ] The shape loop covers every pair up to `kLatestSchemaVersion`.
- [ ] A new content test for the new pair uses a hostile fixture, `reason:` on
      every `expect`, and per-key (not per-list-index) assertions.
- [ ] `PRAGMA integrity_check == ok` and `PRAGMA foreign_key_check` empty after
      the migration; FKs disabled before the migration transaction, re-enabled
      in `beforeOpen`.
- [ ] A forced mid-migration throw restores the snapshot, leaving prior schema
      and rows intact.
- [ ] `eraseDatabaseOnSchemaChange` is DEBUG-only and unreachable in release.
- [ ] Analyzer and formatter clean; table change, version bump, step, snapshot,
      and tests committed together.

## When multi-package (workspace)

If Drift is confined to a data package inside a Dart pub workspace, run every
command from that package (or the workspace root for `make-migrations`), keep
`drift_schemas/` and `schema_versions.dart` inside that package, and run the
migration suite there. In a single-package app all of this lives at the app root
— nothing about the ritual requires a workspace.

## Related skills

- See `persistence-drift` for the data-layer conventions the schema change must
  obey (STRICT tables, schema-level CHECK/FK, WAL/pragmas, DAO transactions).
- See `run-codegen` for the deterministic `build_runner` pass invoked in step 5.
- See `error-handling-typed-results` for the never-lose-data guarantees
  (transactions, autosave drafts, soft-delete/Undo) this workflow complements.
- See `testing-strategy` for the real-in-memory-DB test discipline the content
  and shape tests follow.
- See `ci-pipeline-and-gates` for the schema-freshness gate that fails a build
  when the schema changed without a committed snapshot bump.

## References

- Drift — Migrations: https://drift.simonbinder.eu/Migrations/
- Drift — Migration test API (`SchemaVerifier`, `make-migrations`):
  https://drift.simonbinder.eu/Migrations/tests/
- Drift — `stepByStep`: https://drift.simonbinder.eu/Migrations/step_by_step/
- SQLite — `PRAGMA integrity_check` / `foreign_key_check`:
  https://sqlite.org/pragma.html
- SQLite — Write-Ahead Logging: https://sqlite.org/wal.html
