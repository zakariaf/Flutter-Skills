// Demonstrates: testing a Drift data layer against a REAL in-memory SQLite engine
// (NativeDatabase.memory) — schema CHECK/FK constraints, a scoped .watch() stream, and
// atomic transaction rollback. Never substitute a mocked DAO: it proves nothing about
// the SQL, constraints, indexes, or migrations. Requires `flutter test`, drift, and
// sqlite3 in dev_dependencies.

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app/data/app_database.dart'; // your generated AppDatabase + DAOs

void main() {
  late AppDatabase db;

  setUp(() {
    // A fresh, isolated database per test; no file, no shared state.
    db = AppDatabase(NativeDatabase.memory());
  });

  // Reactive .watch() streams keep a timer alive; closing the DB in teardown prevents
  // a "Timer still pending" leak that would flake the next test.
  tearDown(() => db.close());

  test('CHECK constraint rejects a non-positive quantity', () async {
    await expectLater(
      db.orderDao.insertItem(name: 'Widget', quantity: 0),
      throwsA(isA<SqliteException>()), // the REAL constraint fires, not a stub
    );
  });

  test('foreign key rejects an item pointing at a missing order', () async {
    await expectLater(
      db.orderDao.insertItem(name: 'Widget', quantity: 1, orderId: 999),
      throwsA(isA<SqliteException>()),
    );
  });

  test('watchItems emits the current rows, then the update', () async {
    final orderId = await db.orderDao.createOrder();
    final emissions = <int>[];
    final sub = db.orderDao.watchItemCount(orderId).listen(emissions.add);
    addTearDown(sub.cancel);

    await db.orderDao.insertItem(name: 'A', quantity: 1, orderId: orderId);
    await db.orderDao.insertItem(name: 'B', quantity: 2, orderId: orderId);
    await pumpEventQueue();

    expect(emissions, containsAllInOrder([0, 1, 2]));
  });

  test('a failed mutation inside a transaction rolls back atomically', () async {
    final orderId = await db.orderDao.createOrder();
    await db.orderDao.insertItem(name: 'valid', quantity: 1, orderId: orderId);

    await expectLater(
      db.transaction(() async {
        await db.orderDao.insertItem(name: 'also valid', quantity: 1, orderId: orderId);
        await db.orderDao.insertItem(name: 'bad', quantity: -1, orderId: orderId);
      }),
      throwsA(isA<SqliteException>()),
    );

    // The first insert inside the transaction must NOT have persisted.
    expect(await db.orderDao.itemCount(orderId), 1);
  });
}
