// A complete typed-error boundary: the zero-dependency sealed Result spine, one
// per-boundary sealed Failure family (stable code + typed params, no strings), a
// convert-at-the-boundary repository method (log FIRST, then return a typed Err),
// and an exhaustive call-site switch with NO default:.
//
// Domain is neutral (Order). In a real app the spine lives in a Flutter-free
// layer (lib/core/ single-package; packages/core in a workspace).

import 'dart:async';

import 'package:meta/meta.dart'; // @useResult

// --- The Result spine (Flutter-free) -----------------------------------------

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

// --- The Failure spine: one sealed family per boundary -----------------------

sealed class Failure {
  const Failure();

  /// Stable, localization-key-like identifier. NEVER a user-facing string —
  /// the presentation layer maps this code to a localized message.
  String get code;
}

sealed class OrderFailure extends Failure {
  const OrderFailure();
}

final class OrderNotFound extends OrderFailure {
  const OrderNotFound(this.id);
  final String id;
  @override
  String get code => 'order.not_found';
}

final class OrderConstraintViolated extends OrderFailure {
  const OrderConstraintViolated(this.field);
  final String field;
  @override
  String get code => 'order.constraint_violated';
}

final class OrderStoreUnavailable extends OrderFailure {
  const OrderStoreUnavailable();
  @override
  String get code => 'order.store_unavailable';
}

// --- The boundary: the ONLY place low-level exceptions are caught -------------

class OrderRepository {
  OrderRepository(this._dao, this._log);

  final OrderDao _dao;
  final AppLog _log;

  /// @useResult makes `await findOrder(id);` (outcome discarded) a lint error
  /// when `unused_result` is promoted to error in analysis_options.yaml.
  @useResult
  Future<Result<Order, OrderFailure>> findOrder(String id) async {
    try {
      final row = await _dao.byId(id).timeout(const Duration(seconds: 5));
      if (row == null) return Err(OrderNotFound(id));
      return Ok(row.toDomain());
    } on TimeoutException catch (e, st) {
      _log.error('order.find.timeout', e, st); // log the original FIRST
      return const Err(OrderStoreUnavailable());
    } on SqliteException catch (e, st) {
      _log.error('order.find.db', e, st);
      return Err(_map(e)); // typed, stable code, no strings
    }
    // No `catch (_)` — a bug in the DAO layer surfaces as a crash, not a fake
    // "store unavailable" that hides it.
  }

  OrderFailure _map(SqliteException e) => switch (e.resultCode) {
        19 /* SQLITE_CONSTRAINT */ => OrderConstraintViolated(e.field ?? 'unknown'),
        _ => const OrderStoreUnavailable(),
      };
}

// --- The call site: exhaustive switch, no default: ---------------------------

/// Returns a localized message key path decision. Adding a fourth OrderFailure
/// subtype makes this switch a COMPILE ERROR until it is handled here.
String describeFailureCode(OrderFailure f) => switch (f) {
      OrderNotFound(:final id) => 'order.not_found:$id',
      OrderConstraintViolated(:final field) => 'order.constraint:$field',
      OrderStoreUnavailable() => 'order.store_unavailable',
    };

Future<void> loadAndShow(OrderRepository repo, String id) async {
  switch (await repo.findOrder(id)) {
    case Ok(:final value):
      _render(value);
    case Err(:final failure):
      _showError(describeFailureCode(failure)); // map code -> l10n at the edge
  }
}

// --- Stubs so the example reads as a complete, compiling unit ----------------

class Order {
  const Order(this.id);
  final String id;
}

class OrderRow {
  Order toDomain() => const Order('x');
}

abstract interface class OrderDao {
  Future<OrderRow?> byId(String id);
}

class SqliteException implements Exception {
  SqliteException(this.resultCode, this.field);
  final int resultCode;
  final String? field;
}

abstract interface class AppLog {
  void error(String code, Object error, StackTrace stack);
}

void _render(Order o) {}
void _showError(String key) {}
