// Demonstrates testing the data layer against a REAL in-memory SQLite
// (NativeDatabase.memory()) — never a Map-backed fake, which would accept rows a
// real composite PK / CHECK / FK rejects. Proves the foreign_keys pragma is
// actually ON, that a value -> row -> value round-trip is identity (including the
// canonical-int mapping), and that a soft-delete is filtered by the base query.

import 'package:drift/native.dart';
import 'package:test/test.dart';

// `AppDatabase`, `OrderRepository`, the value objects, and companions come from
// lib/data/. The DB is opened over an in-memory connection with the same
// beforeOpen pragmas the production connection uses.
void main() {
  late AppDatabase db;
  late OrderRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = OrderRepository(db);
  });

  tearDown(() => db.close());

  test('foreign_keys pragma is ON — FK actions are actually enforced', () async {
    final rows = await db.customSelect('PRAGMA foreign_keys;').get();
    expect(rows.single.data['foreign_keys'], 1,
        reason: 'FKs default OFF and silently no-op; beforeOpen must turn them ON');
  });

  test('value -> row -> value is identity, canonical mapping included', () async {
    final order = Order(
      id: 'ord-1',
      accountId: 'acc-1',
      status: OrderStatus.placed,
      total: Money.minor(1299, Currency.usd), // stored as integer minor units
      placedAt: DateTime.utc(2026, 1, 2, 3, 4),
    );
    await repo.place(order, _anyLineItem('ord-1'), nowMs: 1_700_000_000_000);

    final loaded = await repo.watchForAccount('acc-1', _wholeYear).first;

    expect(loaded, hasLength(1));
    expect(loaded.single.total, order.total); // Money value equality
    expect(loaded.single.placedAt, order.placedAt); // UTC round-trips exactly
  });

  test('soft-deleted rows are filtered by the scoped watch', () async {
    await repo.place(_anyOrder('ord-2'), _anyLineItem('ord-2'), nowMs: 1);
    await repo.softDelete('ord-2', nowMs: 2);

    final visible = await repo.watchForAccount('acc-1', _wholeYear).first;
    expect(visible.where((o) => o.id == 'ord-2'), isEmpty);
  });
}
