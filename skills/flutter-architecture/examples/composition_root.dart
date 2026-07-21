// Demonstrates the composition root: main() is thin, bootstrap() builds async infra
// with plain top-level factories, and placeholder providers are overridden ONCE in
// the root ProviderScope. The SAME openAppDatabase() factory is reusable from a
// background isolate (no BuildContext, no shared container) — that symmetry is what
// makes off-tree work rebuild everything from the local source of truth.
//
// Domain-neutral: a generic AppDatabase + repositories. Symbols elided for illustration.

import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// Placeholder providers — throw until overridden. A forgotten wiring is a LOUD
// startup crash, not silent null data. This is also the test seam.
// ---------------------------------------------------------------------------
final appDatabaseProvider =
    Provider<AppDatabase>((ref) => throw UnimplementedError('override in bootstrap()'));
final appDirsProvider =
    Provider<AppDirs>((ref) => throw UnimplementedError('override in bootstrap()'));

// keepAlive infra reads placeholders; repositories are the single source of truth.
final taskRepositoryProvider =
    Provider<TaskRepository>((ref) => TaskRepository(ref.watch(appDatabaseProvider)));

// ---------------------------------------------------------------------------
// Plain top-level factory — no Riverpod, no Flutter widgets. Callable from the
// main isolate (bootstrap) AND a background isolate (its own throwaway container).
// ---------------------------------------------------------------------------
Future<AppDatabase> openAppDatabase(String dbPath) async =>
    AppDatabase(File(dbPath));

// ---------------------------------------------------------------------------
// The composition root — the ONE place async infra is constructed and the graph
// is composed. main() is a one-liner that calls this.
// ---------------------------------------------------------------------------
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dirs = await resolveAppDirs();
  final db = await openAppDatabase(dirs.dbPath); // built here, on the main isolate

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db), // placeholder -> real
        appDirsProvider.overrideWithValue(dirs),
      ],
      child: const App(),
    ),
  );
}

// main_dev.dart / main_prod.dart (or a single main.dart) are one-liners: bootstrap().

// ---------------------------------------------------------------------------
// A background isolate builds its own container from the SAME factory. It never
// references the UI container and never shares a ProviderContainer across isolates.
// ---------------------------------------------------------------------------
@pragma('vm:entry-point')
Future<void> backgroundReconcile() async {
  final dirs = await resolveAppDirs();
  final db = await openAppDatabase(dirs.dbPath);
  final container = ProviderContainer(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
  );
  try {
    await container.read(taskRepositoryProvider).reconcile();
  } finally {
    container.dispose();
    await db.close();
  }
}

// ---------------------------------------------------------------------------
// Symbols elided for illustration.
// ---------------------------------------------------------------------------
class App extends StatelessWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class AppDatabase {
  AppDatabase(this.file);
  final File file;
  Future<void> close() async {}
}

class AppDirs {
  const AppDirs(this.dbPath);
  final String dbPath;
}

class TaskRepository {
  TaskRepository(this.db);
  final AppDatabase db;
  Future<void> reconcile() async {}
}

Future<AppDirs> resolveAppDirs() async => const AppDirs('/data/app.db');
