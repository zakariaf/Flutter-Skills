// Demonstrates a repository exposing an owner + time-window-scoped .watch stream
// that maps Drift rows to immutable value objects, always filters soft-deletes,
// and paginates with keyset (seek) — never OFFSET. Feature code and Riverpod
// stream providers subscribe to this; they never touch the DAO or a Drift row.

import 'package:drift/drift.dart';

/// Plain-Dart time window in UTC epoch millis. The data layer stays Flutter-free:
/// a Flutter `DateTimeRange` (a package:flutter type) never crosses into a
/// repository signature — the presentation edge converts to this VO.
class TimeWindow {
  const TimeWindow(this.startMs, this.endMs);
  final int startMs;
  final int endMs;
}

// `Order` (value object), `Money`, `Currency`, `AppDatabase`, and the generated
// `OrderRow` are declared elsewhere in lib/data/ and lib/domain/.
class OrderReadRepository {
  OrderReadRepository(this._db);
  final AppDatabase _db;

  /// Reactive stream of one account's orders within [window], newest first.
  /// Emits VALUE OBJECTS — never generated row classes.
  Stream<List<Order>> watchForAccount(String accountId, TimeWindow window) {
    final q = _db.select(_db.orders)
      ..where((o) =>
          o.accountId.equals(accountId) &
          o.isDeleted.equals(false) & // ALWAYS filter soft-deletes
          o.placedAtUtcMs.isBetweenValues(window.startMs, window.endMs))
      ..orderBy([(o) => OrderingTerm.desc(o.placedAtUtcMs)]);
    return q.watch().map((rows) => rows.map(_toDomain).toList());
  }

  /// Keyset (seek) pagination — pass the previous page's last instant as cursor.
  /// NEVER OFFSET; it degrades on large tables.
  Future<List<Order>> pageBefore(
    String accountId,
    int cursorMs,
    int pageSize,
  ) async {
    final q = _db.select(_db.orders)
      ..where((o) =>
          o.accountId.equals(accountId) &
          o.isDeleted.equals(false) &
          o.placedAtUtcMs.isSmallerThanValue(cursorMs))
      ..orderBy([(o) => OrderingTerm.desc(o.placedAtUtcMs)])
      ..limit(pageSize);
    return (await q.get()).map(_toDomain).toList();
  }

  // Row -> value object mapping happens ONLY here, at the repository boundary.
  // Canonical int columns become value objects; formatting is the presentation edge.
  Order _toDomain(OrderRow r) => Order(
        id: r.id,
        accountId: r.accountId,
        status: OrderStatus.values.byName(r.status),
        total: Money(r.amountMinor, Currency.byCode(r.currencyCode)),
        placedAt: r.placedAtUtcMs == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r.placedAtUtcMs!, isUtc: true),
      );
}
