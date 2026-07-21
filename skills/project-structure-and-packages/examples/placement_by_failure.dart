// Demonstrates "place a class in the layer whose failure it owns" and the
// confine-the-boundary rule: the repository owns persistence failure, so it is
// the ONLY thing that touches raw rows and the ONLY thing that catches DB errors,
// handing the UI a value type (or a typed outcome) instead.
//
// Self-contained: the "database" and "row" are stand-ins so the file compiles
// without an ORM; in a real app these come from the data/database/ layer.

import 'package:meta/meta.dart';

/// Value type the UI is allowed to see. Lives in lib/core/.
@immutable
final class Account {
  const Account({required this.id, required this.balanceMinorUnits});
  final String id;
  final int balanceMinorUnits;
}

/// A raw persistence row. Never escapes the data layer.
@immutable
class _AccountRow {
  const _AccountRow(this.id, this.balance);
  final String id;
  final int balance;
}

/// Stand-in for the generated database / DAO. In a real app this is Drift.
class AppDatabase {
  Future<List<_AccountRow>> selectAccounts() async =>
      const [_AccountRow('a1', 4200)];
}

/// OWNS persistence failure, so it lives in lib/data/. It is the single door to
/// account data: rows are unpacked here and nowhere else, and DB exceptions are
/// caught at this boundary and converted to a typed outcome the UI understands.
class AccountRepository {
  AccountRepository(this._db);
  final AppDatabase _db;

  Future<LoadOutcome> loadAll() async {
    try {
      final rows = await _db.selectAccounts();
      // Map rows -> value objects here; the UI never sees a _AccountRow.
      final accounts = rows
          .map((r) => Account(id: r.id, balanceMinorUnits: r.balance))
          .toList();
      return LoadSucceeded(accounts);
    } catch (_) {
      // Convert-at-boundary: the raw error stays inside data/; the UI is owed a
      // stable code, not an exception type it would have to switch on. (A real
      // repository would log the caught error here before returning the code.)
      return const LoadFailed('accounts_unavailable');
    }
  }
}

/// Typed outcome, exhaustively switchable in the notifier. Lives in lib/core/.
sealed class LoadOutcome {
  const LoadOutcome();
}

final class LoadSucceeded extends LoadOutcome {
  const LoadSucceeded(this.accounts);
  final List<Account> accounts;
}

final class LoadFailed extends LoadOutcome {
  const LoadFailed(this.code);
  final String code;
}
