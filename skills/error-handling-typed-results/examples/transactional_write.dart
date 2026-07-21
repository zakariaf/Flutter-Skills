// A multi-table mutation in ONE transaction: all of it lands or none of it does.
// Everything that is NOT a synchronous DB call is done BEFORE the transaction —
// the clock is resolved and the draft is canonicalized outside the txn body, so
// the body only issues DAO writes on the transaction's executor.
//
// Neutral domain (Order + lines + a derived rollup). On a throw the whole unit
// rolls back and the boundary returns a typed Err(TransactionRolledBack).

import 'package:clock/clock.dart';

// Result / Failure spine imported from the app's Flutter-free core in a real app.
sealed class Result<T, F extends Failure> {
  const Result();
}

final class Ok<T, F extends Failure> extends Result<T, F> {
  const Ok(this.value);
  final T value;
}

final class Err<T, F extends Failure> extends Result<T, F> {
  const Err(this.failure);
  final F failure;
}

sealed class Failure {
  const Failure();
  String get code;
}

sealed class DbFailure extends Failure {
  const DbFailure();
}

final class TransactionRolledBack extends DbFailure {
  const TransactionRolledBack();
  @override
  String get code => 'db.transaction_rolled_back';
}

class OrderRepository {
  OrderRepository(this._db, this._orderDao, this._lineDao, this._rollupDao, this._log,
      {Clock clock = const Clock()})
      : _clock = clock;

  final AppDatabase _db;
  final OrderDao _orderDao;
  final OrderLineDao _lineDao;
  final RollupDao _rollupDao;
  final AppLog _log;
  final Clock _clock;

  Future<Result<void, DbFailure>> placeOrder(OrderDraft raw) async {
    // 1) PREP OUTSIDE the transaction: resolve the clock, run pure validation +
    //    canonical-value conversion. Never do this inside the txn body.
    final at = _clock.now().toUtc();
    final d = raw.canonicalize(at: at); // money -> minor units, timestamps -> UTC

    try {
      // 2) The transaction body: synchronous DAO writes on the txn executor ONLY.
      //    No awaiting unrelated futures, no re-entering the DB, no channel reads.
      await _db.transaction(() async {
        final id = await _orderDao.insert(d); // journal_mode=WAL, foreign_keys=ON
        await _lineDao.insertAll(d.lines, orderId: id);
        await _rollupDao.bumpRevision(d.accountId); // invalidate a derived key
      });
      return const Ok(null);
    } on Object catch (e, st) {
      _log.error('db.place_order', e, st);
      // A FK/constraint throw here rolled the WHOLE unit back — nothing partial landed.
      return const Err(TransactionRolledBack());
    }
  }
}

// --- Stubs so the example reads as a complete unit ---------------------------

class OrderDraft {
  const OrderDraft();
  OrderDraft canonicalize({required DateTime at}) => this;
  List<Object> get lines => const [];
  String get accountId => 'a';
}

abstract interface class AppDatabase {
  Future<void> transaction(Future<void> Function() body);
}

abstract interface class OrderDao {
  Future<int> insert(OrderDraft d);
}

abstract interface class OrderLineDao {
  Future<void> insertAll(List<Object> lines, {required int orderId});
}

abstract interface class RollupDao {
  Future<void> bumpRevision(String accountId);
}

abstract interface class AppLog {
  void error(String code, Object error, StackTrace stack);
}
