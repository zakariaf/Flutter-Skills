# Schema, DAOs & the index plan

Detail for defining and evolving the source of truth: tables, the audit-column
mixin, canonical column types, the DAO↔repository split, blob metadata, and the
index/query-plan strategy.

## The audit-column mixin — every table

Every table mixes in `AuditColumns`. Never redefine these per table; never add a
table without it.

```dart
mixin AuditColumns on Table {
  TextColumn get id => text()();                       // UUID — collision-free, merge-safe, export-stable
  IntColumn  get createdAt => integer()();             // UTC epoch millis, set once
  IntColumn  get updatedAt => integer()();             // bumped on every write (last-write-wins tiebreaker)
  IntColumn  get rowRevision => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  IntColumn  get deletedAt => integer().nullable()();  // Trash / Undo timestamp
  @override
  Set<Column> get primaryKey => {id};
}
```

- **Text UUID PK, never `autoIncrement()`.** Collision-free multi-device
  creation, stable identity across export/re-import, no reflow. Prefer a
  time-ordered UUID (v7) so inserts stay locality-friendly.
- `created_at` preserves true entry order independent of any user-typed date
  field; `updated_at` is the merge tiebreaker.
- A single shared write wrapper stamps `updated_at` and increments `row_revision`
  on **every** mutation — do not stamp ad-hoc in each DAO method.
- **Every read filters `is_deleted = 0`** — analytics included — via one shared
  base-query helper. Deletes are soft (set `is_deleted` + `deleted_at`), moving
  the row to a user-facing Trash until it expires. See
  `error-handling-typed-results` for the soft-delete/Undo layer.

`autoIncrement()` implies `PRIMARY KEY` and will not compile alongside a
`primaryKey` override — that compile error is the schema defending itself; do not
work around it by dropping the override.

## Position/identity as the primary key

When rows model fixed positions (a slot in a grid, a seat, a rank), make the
position the composite primary key with a **nullable** foreign key to the
content, rather than a surrogate `id` plus an `order`/`index` column. An empty
position is a row with a `NULL` FK — not an absent row — so "delete" writes
`NULL` into the position (via `onDelete: setNull`) and nothing reflows. An
ordering column you have to recompute is one forgotten `WHERE` clause away from a
silent shift; a positional PK makes reflow *unrepresentable*.

## Column type discipline (canonical storage)

| Concept | Column | Canonical unit | Never store |
|---|---|---|---|
| Quantity / length | `IntColumn` | smallest SI unit (metres, grams, ml) | floats, mixed units |
| Money amount | `IntColumn` + separate ISO-4217 code column | integer minor units | `REAL`/`double`, formatted strings |
| Exact rate/ratio | `TextColumn` | canonical decimal string | a float |
| True instant | `IntColumn` | UTC epoch millis | local time, ISO strings, wall-clock |
| Local calendar day | `IntColumn` | serial-day integer | a `DateTime` instant |
| Closed value set | `TextColumn` + `CHECK (col IN (...))` | enum name | a free string |

Money is `int minorUnits` + a separate ISO code column; minor-units-per-major
comes from the currency's real ISO-4217 exponent (`0` for JPY/VND, `2` for most,
`3` for KWD/BHD/OMR) — never a hardcoded `* 100`. The local-day column and the
instant column are **distinct**: a day that drives a boundary must never be an
instant. See `value-objects-money-and-units`.

## Invariants live in the schema

Encode every rule the storage layer can enforce, so a corrupt row cannot be
written:

- `STRICT` on every table — a column never silently coerces a type.
- `CHECK (col IN ('a','b','c'))` for enumerable columns (mirror the Dart enum
  exactly), `CHECK (qty BETWEEN 0 AND n)` / `CHECK (amount_minor >= 0)` for
  ranges.
- Foreign keys with an explicit `onDelete` (`cascade` when a parent owns the row,
  `setNull` for an optional link). FK enforcement requires
  `PRAGMA foreign_keys = ON` on every connection (see the connection section in
  SKILL.md) — it is OFF by default and SQLite silently no-ops FK actions when off.
- Uniqueness as a (partial) `UNIQUE INDEX` — e.g.
  `CREATE UNIQUE INDEX ux_daily ON tasks(day, slot) WHERE kind = 'scheduled';`.

Do **not** bake a fixed layout into a `CHECK` (e.g. `CHECK (col_index < 3)`) when
the dimension is configurable — that turns a valid larger layout into a
database-level insert failure and a needless migration. Bounds that reference
another table's value are enforced in the repository (SQLite `CHECK` cannot
reference another table).

## Per-entity extension without a bespoke shared table

When one feature needs a field the shared schema does not have, prefer a small,
schema-shaped, decode-validated JSON column over a new table — but never smuggle
a value that must stay a typed, `CHECK`ed column (a status, a money amount, an
entitlement flag) into a JSON blob a call site can corrupt.

## Blobs are files on disk, paths relative

Bytes never live in SQLite — they bloat the DB and slow every checkpoint and
backup. Store only a metadata row:

```dart
class Attachments extends Table with AuditColumns {
  TextColumn get sha256 => text()();          // hash of the bytes — content-addressed dedupe key
  TextColumn get relativePath => text()();     // relative to a known base dir, NEVER absolute
  TextColumn get mimeType => text()();
  TextColumn get ownerType => text()();        // polymorphic parent
  TextColumn get ownerId => text()();
  IntColumn  get refCount => integer().withDefault(const Constant(1))();
}
```

- **Path relative to a base directory, resolved to absolute only at read time.**
  An absolute path dies on iOS reinstall/restore when the app-container UUID
  changes: the row survives, the file survives, the tile renders blank forever
  with no error. Resolve media through one helper that owns the base dir; never
  hand-build a media path elsewhere. Note that the DB file (support dir) and
  media (documents dir) may use *different* base dirs — never join against the
  wrong one.
- Downscale images at import, not at render.
- A `ref_count` lets a shared file survive until the last owner is deleted; a GC
  sweep deletes the file only when `ref_count` reaches 0.

## DAOs vs repositories

- One `@DriftDatabase`, per-feature `@DriftAccessor` DAOs holding **single-table**
  queries. Repositories hold **cross-table transactions** and row→value-object
  mapping, expose scoped `.watch()`, and return `Result<T, Failure>` for fallible
  work.
- DAOs return value objects, not Drift row classes. The mapper converts canonical
  `int` columns into value types (`Money(row.amountMinor, ...)`,
  `Quantity.grams(row.qty)`); formatting never happens here — that is the
  presentation edge.
- Fast logic tests use `NativeDatabase.memory()` — a real in-memory SQLite, never
  a `Map`-backed fake (a fake accepts rows a real composite PK or `CHECK`
  rejects, and never runs a migration step).

## The index & query-plan strategy

Index the real access patterns, then **prove it with `EXPLAIN QUERY PLAN` in a
test**:

```sql
-- Nearly every read is "this owner, ordered by time" — compose the key to serve
-- both the WHERE filter and the ORDER BY.
CREATE INDEX idx_orders_account_time ON orders (account_id, placed_at_utc_ms);
-- Content-addressed blob GC + relink.
CREATE INDEX idx_attach_sha   ON attachments (sha256);
CREATE INDEX idx_attach_owner ON attachments (owner_type, owner_id);
```

- Leading column is the equality filter, trailing column the sort — one index
  serves filter and order.
- History screens use **keyset (seek) pagination**:
  `WHERE ts < :cursor ORDER BY ts DESC LIMIT n`, never `OFFSET`.
- When you add a join-heavy query, add its index in the same change and add the
  `EXPLAIN QUERY PLAN` assertion.

## Aggregate/rollup tables (only when a scan is too slow)

If a derived read genuinely cannot afford to scan its source rows on every
render, materialise a rollup table keyed by `(scope, period)` and stamped with a
revision counter — and update it **in the same transaction** as the write that
invalidates it, recomputing off-isolate (`Isolate.run`) over only the affected
slice. This is an optimisation, not a default: derived state is recomputed on
read (rule 6) until measurement proves the scan is the bottleneck.
