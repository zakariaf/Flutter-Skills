---
name: persistence-drift
description: >-
  Governs the on-device Drift/SQLite data layer: package:drift and package:sqlite3 confined to lib/data/ behind
  DAOs that map rows to immutable value objects (no Drift symbol leaks past the repository), invariants pushed into
  the schema (STRICT tables, CHECK/FK/partial-UNIQUE indexes), foreign_keys/WAL pragmas re-asserted idempotently in
  beforeOpen, one db.transaction per mutation, persist-before-publish, every query awaited, canonical integer storage,
  derived state recomputed-on-read never stored, scoped .watch streams, keyset (seek) pagination not OFFSET, and
  WAL-safe backups (checkpoint + VACUUM INTO, verify-by-reopen, never File.copy a live WAL DB). Use when defining or
  altering a Drift Table, Companion, DAO, index, or CHECK; writing a repository transaction or scoped watch provider;
  wiring the connection/beforeOpen pragmas; adding SQLCipher; building or verifying a backup; or reviewing a
  data-layer diff. Migrations and their tests live in run-migration.
---

# Persistence — Drift / SQLite

The on-device store is the single source of truth: with no server, everything must rebuild from this DB alone after
process death, reboot, or restore. Push invariants into the schema, confine Drift to one layer, make every mutation
one durable transaction, and store canonical values only. Applies to any `lib/data/` Drift table, DAO, repository,
connection setup, or backup.

Read the reference for the task at hand:
- `references/schema-and-daos.md` — audit-column mixin, STRICT/CHECK/FK invariants, canonical column types, the index + `EXPLAIN QUERY PLAN` gate, DAO↔repository split, files-on-disk-with-relative-paths for blobs.
- `references/backup-and-wal.md` — the checkpoint→vacuum→verify-by-reopen primitive, WAL rules, the backup-before-anything lesson, optional SQLCipher (key-first, assert-cipher, header-check).
- `references/persistence-without-drift.md` — the same discipline for a small app on plain JSON files (injected base dir, debounce + lifecycle flush, atomic writes, lenient decode).

Run `scripts/check-drift-confinement.sh` and `scripts/check-persistence-bans.sh` before a PR. Migrations and their tests: see `run-migration`.

## Non-negotiable rules

1. **Drift lives only in `lib/data/`; everything else sees value types.** `package:drift` and `package:sqlite3` are imported nowhere else — a banned-import lint/grep enforces it. DAOs map rows to immutable value objects; no `Table`, `Companion`, `TableInfo`, or generated row class crosses the boundary. A feature reaching for a raw query is a layering break that also blocks pure testing of everything above it.
2. **Put invariants in the schema, not at call sites.** Tables are `STRICT` (no silent coercion); enumerable columns get `CHECK (col IN (...))`, ranges get `CHECK (qty BETWEEN 0 AND n)` / `CHECK (amount_minor >= 0)`, relations are foreign keys with an explicit `onDelete`, uniqueness is a (partial) `UNIQUE INDEX`. A corrupt row must be unrepresentable at the storage layer, not merely policed in Dart.
3. **`foreign_keys` and `synchronous` are set in `beforeOpen`/`setup` on EVERY open; `journal_mode = WAL` is set idempotently there too.** `foreign_keys` and `synchronous` are **per-connection** and are **not** persisted in the file, so they must be re-asserted on every open. `journal_mode = WAL`, by contrast, *is* persisted in the database file header and survives across connections — but it is still set idempotently in setup so a freshly created or restored DB adopts it. `PRAGMA foreign_keys = ON` unconditionally (SQLite defaults it OFF and silently no-ops FK actions when off); `journal_mode = WAL` for concurrent durable reads; `synchronous = FULL` on any store holding non-regenerable user data (WAL+NORMAL "might rollback following a power failure"). Seeding, and only seeding, goes inside `if (details.wasCreated)`.
4. **One `db.transaction` per mutation; every query inside awaited; persist before publish.** A mutation that writes several rows (parent + dependents, or a debit + a credit) is all-or-nothing. A missing `await` inside `transaction(() async {` lets a query run after the transaction closes — Drift calls this data loss; it is a release blocker. The DAO `Future` resolves only after the durable commit; the committed write then makes the watched `.watch()` stream **re-emit** the new state on its own — never an optimistic pre-commit update, never a manual `state = …` republish, never "save later". (The write→UI-update rule is owned by `state-management-riverpod`.)
5. **Store canonical values only; convert at the presentation edge.** Money as integer minor units keyed to the real ISO-4217 exponent (never a `REAL`/`double`), other quantities as SI integers, true instants as UTC epoch millis. The **local calendar day** (anything that drives a day boundary) is a serial-day integer, **never a `DateTime` instant** — an instant reintroduces the DST/timezone off-by-one. No display strings, localized numerals, or formatted values in any column; switching locale/unit must leave stored rows byte-identical.
6. **Derived state is recomputed on read, never stored as a second authority.** Counts, streaks, running totals, histograms are pure folds over their source rows, computed by one `watch…`/query fold next to the data. A stored copy is a second source of truth that drifts and that any future sync must reconcile twice.
7. **The repository is the single write path and the single source of truth.** DAOs hold single-table queries; repositories own cross-table transactions and row→value-object mapping, and return a typed `Result<T, Failure>` for fallible work. Feature code depends on the repository abstraction, never on a DAO or Drift row.
8. **Reads are scoped `.watch()` streams; pagination is keyset, not `OFFSET`.** Never subscribe to an unscoped app-wide stream (it recomputes on every write); scope by owner/entity + time window. History uses `WHERE ts < :cursor ORDER BY ts DESC LIMIT n`; `OFFSET` degrades badly on large tables.
9. **Blob bytes never live in SQLite.** Store files on disk (app-private) with only a metadata row; persist the path **relative** to a base directory and resolve to absolute at read time — an absolute path dies on iOS reinstall/restore when the container UUID changes, and the row survives while the file renders blank with no error. BLOBs bloat the DB and slow every checkpoint and backup.
10. **Back up via `wal_checkpoint(TRUNCATE)` + `VACUUM INTO`, then verify by reopen — never `File.copy` a live WAL DB.** A raw copy of a WAL-mode DB captures a torn state across the `-wal`/`-shm` sidecars and is corrupt and unrestorable. A backup that was not re-opened and integrity-checked did not succeed. Detail in `references/backup-and-wal.md`.
11. **Schema evolution is forward-only, append-only, and snapshot-guarded — and it is a separate ritual.** Bump `schemaVersion`, add a new `stepByStep` step (never edit a shipped one), commit the schema snapshot, and ship no migration without a content-level test. That whole workflow lives in `run-migration`; this skill defines the tables it migrates.

## Confining Drift to one layer

One `@DriftDatabase`, per-feature `@DriftAccessor` DAOs, repositories on top. Use the `NativeDatabase` FFI backend, never `sqflite`.

```text
lib/data/
  db/        app_database.dart   (@DriftDatabase, schemaVersion, MigrationStrategy)
             connection.dart     (open + beforeOpen pragmas; optional SQLCipher key)
             tables/             one Table subclass per entity + audit mixin
  daos/      one @DriftAccessor per feature (single-table queries)
  repositories/  cross-table transactions; map rows -> value objects; expose .watch
```

> **When multi-package (workspace):** the same boundary becomes a package (e.g. `packages/data`) that is the only pubspec depending on `drift`/`sqlite3`, enforced by a banned-import gate. For a single-package app the boundary is the `lib/data/` directory and the grep in `scripts/check-drift-confinement.sh`. Do not reach for a workspace to get this boundary — a directory + lint is enough.

## Schema: invariants in the table

```dart
// lib/data/db/tables/orders.dart — the ONLY layer importing package:drift.
import 'package:drift/drift.dart';

@DataClassName('OrderRow') // generated row type stays inside lib/data/
class Orders extends Table with AuditColumns {
  TextColumn get status =>
      text().check(status.isIn(const ['draft', 'placed', 'shipped', 'cancelled']))();
  IntColumn get amountMinor => integer()();          // integer minor units, never REAL
  TextColumn get currencyCode => text().withLength(min: 3, max: 3)();
  IntColumn get placedOnDay => integer().nullable()(); // LOCAL calendar day as serial int
  IntColumn get placedAtUtcMs => integer().nullable()(); // true instant, UTC epoch millis

  @override
  List<String> get customConstraints => const [
        'CHECK (amount_minor >= 0)',
        // a placed order must carry the day that drives its boundary
        "CHECK (status = 'draft' OR placed_on_day IS NOT NULL)",
      ];

  @override
  bool get isStrict => true; // no silent type coercion
}
```

`AuditColumns` (a `mixin on Table`) gives every table a stable text PK (a UUID — collision-free, merge-safe, stable across export), `createdAt`/`updatedAt` UTC-ms, `rowRevision`, and `isDeleted`/`deletedAt` for soft-delete. Stamp `updatedAt`/`rowRevision` through one shared write wrapper; filter `is_deleted = 0` in one shared base-query helper — analytics included. See `references/schema-and-daos.md`.

## The connection: pragmas per open

```dart
// lib/data/db/connection.dart
LazyDatabase openConnection() => LazyDatabase(() async {
      final dir = await getApplicationSupportDirectory(); // internal DB, not Documents
      final file = File(p.join(dir.path, 'app.sqlite'));
      return NativeDatabase.createInBackground(
        file,
        setup: (raw) {
          // foreign_keys & synchronous are PER-CONNECTION (not persisted) — set on every open.
          // WAL persists in the file header, but set it idempotently so a fresh/restored DB adopts it.
          raw.execute('PRAGMA journal_mode = WAL;');
          raw.execute('PRAGMA synchronous = FULL;');
          raw.execute('PRAGMA foreign_keys = ON;');
          raw.execute('PRAGMA busy_timeout = 5000;');
        },
      );
    });
```

In `MigrationStrategy.beforeOpen`, re-assert `foreign_keys = ON` and seed only under `if (details.wasCreated)`. During a migration, toggle `foreign_keys` **outside** any transaction (it is a no-op inside one) and run `PRAGMA foreign_key_check` afterwards.

## DAO + repository: one transaction, mapped to value objects

A DAO holds **single-table** queries for one table (`window` is a plain-Dart
`TimeWindow` VO of UTC-ms bounds — never a Flutter `DateTimeRange` in the data layer):

```dart
// lib/data/daos/orders_dao.dart — the only door to SQL for the Orders table.
@DriftAccessor(tables: [Orders])
class OrdersDao extends DatabaseAccessor<AppDatabase> with _$OrdersDaoMixin {
  OrdersDao(super.db);

  /// Reactive, SCOPED, SINGLE-TABLE read. Rows map to value objects — callers see no Drift symbol.
  Stream<List<Order>> watchForAccount(String accountId, TimeWindow window) =>
      (select(orders)
            ..where((o) =>
                o.accountId.equals(accountId) &
                o.isDeleted.equals(false) & // always filter soft-deletes
                o.placedAtUtcMs.isBetweenValues(window.startMs, window.endMs))
            ..orderBy([(o) => OrderingTerm.desc(o.placedAtUtcMs)]))
          .watch()
          .map((rows) => rows.map(_toModel).toList());
}
```

The **repository** owns the cross-table transaction (a DAO scoped to `[Orders]`
cannot reference `lineItems` — that is rule 7) and maps rows to value objects:

```dart
// lib/data/repositories/order_repository.dart — the single write path across tables.
class OrderRepository {
  OrderRepository(this._db);
  final AppDatabase _db;

  /// ONE transaction, every query awaited, persist-before-publish.
  Future<void> place(Order order, LineItem item) {
    return _db.transaction(() async {
      await _db.into(_db.orders).insertOnConflictUpdate(order.toRow()); // await — required
      await _db.into(_db.lineItems).insert(item.toCompanion());          // await — required
    }); // Future resolves only after the durable commit; the watched stream re-emits — no manual republish.
  }
}
```

The repository maps `OrderRow` → the immutable `Order` value object (integer minor units → a `Money` value object, `placedOnDay` serial → a calendar-day type) so no feature ever sees a canonical `int` or a Drift class. Keyset pagination: `..where((o) => o.placedAtUtcMs.isSmallerThanValue(cursor))..limit(n)`.

## Riverpod wiring (state + DI)

The database and each repository are provided; scoped `.watch()` streams map onto stream providers; derived views are computed providers. Keep the core persistence-agnostic — a repository interface with a single write path and derive-don't-store — and let Riverpod be the injection and consumption mechanism.

```dart
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase(openConnection());
  ref.onDispose(db.close); // close the connection with the provider
  return db;
});

final orderRepositoryProvider = Provider<OrderRepository>(
  (ref) => OrderRepository(ref.watch(appDatabaseProvider)),
);

// Scoped stream — family carries the scope; autoDispose tears the watch down.
final ordersProvider = StreamProvider.autoDispose
    .family<List<Order>, OrderScope>((ref, scope) =>
        ref.watch(orderRepositoryProvider).watchForAccount(scope.accountId, scope.window));
```

Never open the DB in a widget; never expose a DAO through a provider. See `state-management-riverpod` for Notifier/AsyncNotifier discipline over these repositories.

## Anti-patterns

- **A `package:drift` symbol leaking past `lib/data/`, or a widget/Notifier issuing a raw query** — the row shape is a data-layer secret; map to value objects at the boundary.
- **A non-`STRICT` table, or validating enums/ranges at every call site** instead of `CHECK` in the schema — a corrupt row must be impossible to write.
- **Assuming a pragma persists** — `foreign_keys`/`synchronous`/a cipher key are per-connection; set them in `setup`/`beforeOpen` on every open. `PRAGMA foreign_keys` inside a transaction is a silent no-op.
- **`synchronous = NORMAL` on a store of non-regenerable data** — SQLite says WAL+NORMAL transactions may roll back after power loss.
- **A `DateTime` instant stored as the local day** — reintroduces the DST/timezone rollover bug. Local day = serial int; instants = UTC ms.
- **A stored `count`/`total`/`streak` treated as authority** — recompute from source rows; a stored copy drifts.
- **Splitting a mutation across transactions, dropping an `await` inside `transaction(() async {`, or an optimistic pre-commit update** — each is a data-loss footgun; commit first and let the watched stream re-emit.
- **`OFFSET` pagination, or an unscoped `.watch()`** — both degrade and over-recompute; keyset + scoped streams.
- **BLOB bytes in SQLite, or an absolute media path** — files on disk with a path relative to a base dir; absolute paths die on reinstall/restore.
- **`File.copy` of a live WAL DB for a backup** — torn, unrestorable; checkpoint + `VACUUM INTO` + verify-by-reopen.
- **`sqflite` backend, or `eraseDatabaseOnSchemaChange` reachable in release** — use `NativeDatabase` FFI; that flag wipes real data.

## Definition of done

- [ ] `package:drift`/`package:sqlite3` appear only under `lib/data/` (grep green); DAOs return value objects; no Drift type crosses the boundary. Backend is `NativeDatabase` (FFI), not `sqflite`.
- [ ] Every table is `STRICT`; enums are `CHECK (... IN (...))`; ranges are `CHECK`ed; relations are foreign keys with an explicit `onDelete`; uniqueness is a (partial) `UNIQUE INDEX`; hot queries have a matching index proven by `EXPLAIN QUERY PLAN` in a test.
- [ ] `journal_mode = WAL`, `synchronous = FULL`, `foreign_keys = ON`, `busy_timeout` are set in `setup`/`beforeOpen` on every open; seeding is only under `if (details.wasCreated)`.
- [ ] Each mutation is exactly one `db.transaction`; every query inside is awaited; the write `Future` resolves before any UI update, and the watched stream re-emits (persist-before-publish, never optimistic, no manual republish).
- [ ] Canonical storage only: integer minor units + ISO-4217 code, SI ints, UTC epoch ms; the local day is a serial int, never a `DateTime`; no formatted/localized values in any column.
- [ ] Derived state is recomputed on read (one fold next to the data), never stored as authority.
- [ ] Reads are owner/window-scoped `.watch()` streams mapped to value objects; pagination is keyset, never `OFFSET`.
- [ ] Blob bytes are files on disk with a path relative to a base dir; no BLOB columns.
- [ ] Backups use `wal_checkpoint(TRUNCATE)` + `VACUUM INTO` + verify-by-reopen; no `File.copy` of a live DB.
- [ ] Schema changes are paired with the `run-migration` ritual (bumped `schemaVersion`, append-only step, committed snapshot, content test).

## Related skills

- `run-migration` — the forward-only `stepByStep` migration ritual, committed snapshots, and content tests for the tables this skill defines.
- `error-handling-typed-results` — the `Result`/`Failure` spine repositories return, and the never-lose-data layer (transactions, drafts, soft-delete/Undo).
- `value-objects-money-and-units` — the `Money`/quantity/`Clock` value types a repository maps canonical columns into.
- `state-management-riverpod` — Notifier/AsyncNotifier ViewModels and providers-as-DI over these repositories.
- `flutter-architecture` — the downward-only DAG and single-write-path layering this data layer sits at the bottom of.
- `codegen-and-toolchain` / `run-codegen` — running `build_runner` for Drift's generated code.
- `service-boundary-and-native` — wiring the database/repository as injectable providers overridden at the composition root.
- `data-export-and-restore` — the portable, user-facing end of this store: the versioned backup envelope, staging-then-swap restore, and CSV/PDF export.

## References

- Drift docs: https://drift.simonbinder.eu/
- Drift transactions: https://drift.simonbinder.eu/dart_api/transactions/
- Drift migrations: https://drift.simonbinder.eu/Migrations/
- SQLite STRICT tables: https://sqlite.org/stricttables.html
- SQLite WAL: https://sqlite.org/wal.html
- SQLite `VACUUM INTO`: https://sqlite.org/lang_vacuum.html#vacuuminto
- SQLite foreign keys (per-connection pragma): https://sqlite.org/foreignkeys.html
- `path_provider`: https://pub.dev/packages/path_provider
