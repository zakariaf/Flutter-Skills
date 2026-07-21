# Never-lose-data: transactions, autosave drafts, soft-delete / Trash / Undo

Three mechanisms that protect hand-entered records against half-applied writes, process death, and mistaken deletes. In an app with no server and no re-sync path, a dropped record exists nowhere else. This is a first-class subsystem, not plumbing. See `persistence-drift` for the DAO/connection machinery these build on.

## 1. One transaction per multi-table mutation

A single logical action often touches several tables at once (insert a row + append a ledger entry + invalidate a derived rollup). Either **all** of it lands or **none** does; a half-applied write silently corrupts derived data with no way to notice offline.

### The rule

Wrap the whole unit in one `transaction(...)`. Any throw rolls the entire unit back. Map the throw to a typed `Err` at the boundary (log first).

```dart
Future<Result<void, DbFailure>> placeOrder(OrderDraft raw) async {
  // 1) PREP OUTSIDE the transaction: resolve the clock, run pure validation +
  //    canonical-value conversion. Never do this inside the txn body.
  final at = _clock.now().toUtc();
  final d = raw.canonicalize(at: at);

  try {
    await _db.transaction(() async {                // journal_mode=WAL, foreign_keys=ON
      final id = await _orderDao.insert(d);
      await _lineDao.insertAll(d.lines, orderId: id);
      await _rollupDao.bumpRevision(d.accountId);   // invalidate a derived key
    });
    return const Ok(null);
  } on Object catch (e, st) {
    _log.error('db.place_order', e, st);
    return const Err(TransactionRolledBack());       // whole unit rolled back
  }
}
```

### Synchronous DB calls ONLY inside the body

Inside the transaction, issue **only** statements that run on the transaction's executor. Never `await` an unrelated future and never re-enter the same DB — both deadlock or break atomicity, because the DB serializes access through the transaction's zone.

| Inside the transaction body | Verdict | Why |
| --- | --- | --- |
| A DAO write on the txn executor | OK | runs on the transaction's connection |
| A nested `transaction(...)` | AVOID | maps to a SAVEPOINT — only for a genuine partial-rollback sub-unit |
| `await secureStorage.read(...)` | FORBIDDEN | unrelated platform channel — read it BEFORE and pass the value in |
| `await http/file/Future.delayed` | FORBIDDEN | blocks the txn zone / interleaves |
| Reading `DateTime.now()` | AVOID | inject `Clock`; compute the instant before the txn |

**Do the prep before the transaction:** resolve `Clock.now()`, read any secure-storage value, run pure validation and canonical-value conversion — all *outside* — then open the transaction and issue only the synchronous writes.

### Rollback test (blocking)

Drive a multi-table write whose **2nd** statement throws (force an FK/constraint violation), then assert both the typed `Err` **and** that the DB is byte-unchanged — proving atomic rollback, not just an error return.

```dart
test('placeOrder rolls back atomically when a line insert violates FK', () async {
  final before = await db.dumpAllRows();
  final result = await repo.placeOrder(orderWithBadLineRef);
  expect(result, isA<Err<void, DbFailure>>());
  expect((result as Err).failure, isA<TransactionRolledBack>());
  expect(await db.dumpAllRows(), equals(before)); // no partial write survived
});
```

Use an in-memory DB (`NativeDatabase.memory()`); no device needed. See `testing-strategy`.

## 2. Debounced autosave drafts

In-progress form state persists to a `drafts` table so a background-kill mid-entry loses nothing. On reopen, offer to restore.

- Persist on a **short debounce** (roughly half a second to a second) after the last keystroke — **never write the main DB per keystroke** (I/O thrash + battery). Pick the interval by profiling, not by copying a magic number.
- Drive the debounce off an injected `Clock` + a cancelable `Timer` so `fake_async` can prove: no write before the window, exactly one write after it.
- Key a draft by `(entityType, entityId?)` so editing an existing record and creating a new one each have at most one live draft.
- On form open, if a matching draft is newer than the committed row, show a **non-destructive** "Restore unsaved changes?" prompt. Restore loads the draft; discard deletes it.
- On successful commit, **delete the draft in the same logical step** so a stale draft never shadows a saved record.

```dart
class DraftAutosaver {
  DraftAutosaver(this._store, {Clock clock = const Clock(), required Duration debounce})
      : _clock = clock, _debounce = debounce;

  final DraftStore _store;
  final Clock _clock;
  final Duration _debounce;
  Timer? _timer;

  void onChanged(DraftKey key, Map<String, Object?> snapshot) {
    _timer?.cancel();
    _timer = Timer(_debounce, () {
      unawaited(_store.upsert(key, snapshot, at: _clock.now())); // failure logs, never blocks typing
    });
  }

  Future<void> commitClears(DraftKey key) async {
    _timer?.cancel();
    await _store.delete(key); // saved record supersedes the draft
  }
}
```

```dart
// Test: fake_async proves the debounce window.
fakeAsync((async) {
  saver.onChanged(key, snap);
  async.elapse(const Duration(milliseconds: 300));
  expect(store.writes, 0);                 // nothing before the window
  async.elapse(const Duration(milliseconds: 500));
  expect(store.writes, 1);                 // exactly one after
});
```

## 3. Optimistic soft-delete + Trash + Undo

Deletes are optimistic and reversible. A row is never hard-deleted on the user's tap.

### The columns and the ONE filter

- Every user-owned table has `is_deleted INTEGER NOT NULL DEFAULT 0` and `deleted_at INTEGER` (UTC epoch millis, nullable).
- **A single shared query layer or DB view filters `is_deleted = 0` out of EVERY read.** This is the load-bearing invariant: lists, search, analytics, derived rollups, AND any chart datasets read through the **same** filter. A hand-written query that hits the base table directly silently counts deleted rows and corrupts every report.

```sql
-- The ONE view every active read goes through.
CREATE VIEW orders_active AS SELECT * FROM orders WHERE is_deleted = 0;
```

```dart
// Or a shared builder every DAO composes — none rolls its own WHERE.
extension ActiveOnly on $OrdersTable {
  Expression<bool> get active => isDeleted.equals(false);
}
```

### Optimistic delete with SnackBar Undo (Riverpod)

```dart
class OrdersNotifier extends Notifier<void> {
  @override
  void build() {}

  Future<void> delete(BuildContext context, String id) async {
    final l10n = AppLocalizations.of(context);
    final dao = ref.read(orderDaoProvider);

    await dao.softDelete(id, at: clock.now().toUtc()); // set is_deleted=1, deleted_at=now
    ref.invalidate(activeOrdersProvider);              // list drops the row immediately (optimistic)

    if (!context.mounted) return; // guard BuildContext after the await (see async-safety)
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(l10n.recordDeleted),
      action: SnackBarAction(
        label: l10n.undo,
        onPressed: () async {
          await dao.restore(id); // clears is_deleted/deleted_at — exact, cheap restore
          ref.invalidate(activeOrdersProvider);
        },
      ),
    ));
  }
}
```

### Trash screen + auto-purge

- A Trash screen lists rows where `is_deleted = 1`, ordered by `deleted_at`, offering **Restore** (clear flags) or **Delete permanently** (hard delete + attachment cleanup).
- **Auto-purge after N days**: a maintenance pass hard-deletes rows whose `deleted_at` is older than N days. Drive the cutoff off the injected `Clock` so `fake_async` verifies purge timing deterministically.
- Purge is a real destructive delete — run it inside a transaction and clean up content-addressed attachment files whose last referencing row is gone.

### Parity guarantee (the thing that breaks silently)

| Read surface | Through the shared filter? |
| --- | --- |
| Lists / history / search | YES |
| Analytics & derived stats | YES |
| Rollups / projections | YES |
| Chart datasets | YES |
| Trash screen | NO — the ONLY surface that reads `is_deleted = 1` |
| Export / backup | Policy: exclude soft-deleted from portable export; the archive may retain them for full-fidelity restore — decide per manifest |

`scripts/check-softdelete-parity.sh` greps analytics/chart builders for base-table reads that bypass the shared filter and lists offenders.

### Test recipe

- Soft-delete a row → assert it disappears from the list **and** from analytics/rollup/chart query results (not just the list).
- Undo → assert it reappears everywhere.
- `fake_async`: advance past N days → the maintenance pass hard-deletes it; advance to N-1 days → it survives.
