// Demonstrates the single write path: a parent row and its dependent row written
// in ONE db.transaction, every query awaited, canonical int columns only, stamped
// audit fields, and a typed Result on failure. The Future resolves only after the
// durable commit — the watched .watch() stream then re-emits on its own, no manual
// republish (persist-before-publish; the write->UI-update rule lives in state-management-riverpod).
//
// Generic domain: placing an Order writes the order plus its line item atomically
// so the two can never desync. Money is stored as integer minor units + an ISO
// code; the instant is UTC epoch millis. Mapping to value objects happens at the
// repository boundary, not here.

import 'package:drift/drift.dart';

// Assume `AppDatabase`, `Orders`, `LineItems`, and the value types below are
// generated / declared elsewhere in lib/data/. `Result`/`Failure` come from the
// error-handling-typed-results spine.
class OrderRepository {
  OrderRepository(this._db);
  final AppDatabase _db;

  /// Place an order and its line item atomically.
  /// [nowMs] is injected (package:clock) so tests are deterministic.
  Future<Result<void, DataFailure>> place(
    Order order,
    LineItem item, {
    required int nowMs,
  }) async {
    try {
      await _db.transaction(() async {
        await _db.into(_db.orders).insert(
              OrdersCompanion.insert(
                id: order.id, // UUID text PK
                accountId: order.accountId,
                status: 'placed', // mirrors CHECK (status IN (...))
                amountMinor: order.total.minorUnits, // integer minor units
                currencyCode: order.total.currency.code, // ISO-4217
                placedAtUtcMs: Value(nowMs), // true instant, UTC epoch millis
                createdAt: nowMs,
                updatedAt: nowMs,
              ),
            ); // await — required; a dropped await runs after the tx closes

        await _db.into(_db.lineItems).insert(
              LineItemsCompanion.insert(
                id: item.id,
                orderId: order.id, // FK — enforced only with PRAGMA foreign_keys = ON
                quantity: item.quantity,
                unitAmountMinor: item.unitPrice.minorUnits,
                currencyCode: item.unitPrice.currency.code,
                createdAt: nowMs,
                updatedAt: nowMs,
              ),
            ); // await — required
      });
      return const Ok(null);
    } on DriftRemoteException catch (e, s) {
      // Convert at the boundary: log the original, return a typed failure.
      _log.error('order.place failed', e, s);
      return const Err(DataFailure.writeFailed());
    }
  }
}
