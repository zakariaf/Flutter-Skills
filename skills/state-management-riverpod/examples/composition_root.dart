// Demonstrates the composition root: throwing-seam DI providers wired to their one
// live implementation per flavor via ProviderScope overrides in main(), with retry
// disabled for local-only failures. Tests override the same seams with fakes.
//
// Conceptual example. Generic Account domain.

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// --- Collaborators (abstractions) --------------------------------------------

abstract interface class AccountRepository {
  Future<void> credit(String accountId, int minorUnits);
}

class AppDatabase {
  static AppDatabase open() => AppDatabase._();
  AppDatabase._();
  void close() {}
}

class DriftAccountRepository implements AccountRepository {
  DriftAccountRepository(this._db);
  final AppDatabase _db;
  @override
  Future<void> credit(String accountId, int minorUnits) async {
    // one transaction, persist-before-publish (see persistence-drift)
  }
}

// --- Seams --------------------------------------------------------------------

// Throws until overridden: an un-wired dependency fails loudly at first read.
final databaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('override databaseProvider in main()'),
);

// The ONE time seam: package:clock's Clock. It self-defaults to the real clock
// (const Clock() opens no I/O), so it needs no override outside tests, which use
// Clock.fixed(...). Never DateTime.now(); never a bespoke ClockService/SystemClock.
// service-boundary-and-native owns this seam.
final clockProvider = Provider<Clock>((ref) => const Clock());

// Wired provider: injects the seam, never constructs a live DB itself.
final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => DriftAccountRepository(ref.watch(databaseProvider)),
);

// --- Composition root: the ONLY place live collaborators are constructed ------

void main() {
  final db = AppDatabase.open();

  runApp(
    ProviderScope(
      // Local-only failures (corrupt DB, missing file) should be loud, not retried
      // behind a spinner. An app with a network may keep the default for network
      // providers and disable it for local ones.
      retry: (retryCount, error) => null,
      overrides: [
        databaseProvider.overrideWithValue(db),
        // clockProvider self-defaults to const Clock() — no override needed here.
      ],
      child: const App(),
    ),
  );
}

class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(home: Placeholder());
}

// --- A test overrides the same seams with deterministic fakes ----------------

ProviderContainer buildTestContainer(AppDatabase memoryDb) {
  // ProviderContainer.test() self-disposes; no manual addTearDown needed.
  return ProviderContainer.test(
    overrides: [
      databaseProvider.overrideWithValue(memoryDb), // real in-memory DB, not a mock
      clockProvider.overrideWithValue(Clock.fixed(DateTime.utc(2026, 1, 1))),
    ],
  );
}
