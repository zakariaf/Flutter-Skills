// Demonstrates one complete, correctly-layered feature slice: an immutable domain
// value object, a CONCRETE repository as the single source of truth + single write
// path, a StreamNotifier ViewModel whose build() returns the live repo stream (a
// write commits and the stream re-emits — no manual republish), and a dumb
// ConsumerWidget View. No interface over the repository — it runs in a test.
//
// Domain: a simple Task list. Single-package shape (no barrels/workspace here).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ---------------------------------------------------------------------------
// domain model — immutable value object with value equality (data/ layer)
// ---------------------------------------------------------------------------
@immutable
final class Task {
  const Task({required this.id, required this.title, required this.done});

  // id is passed in from an injected source (see idGeneratorProvider) — a domain
  // value object never reaches for a UI-framework type like UniqueKey.
  factory Task.create({required String id, required String title}) =>
      Task(id: id, title: title, done: false);

  final String id;
  final String title;
  final bool done;

  Task copyWith({String? title, bool? done}) =>
      Task(id: id, title: title ?? this.title, done: done ?? this.done);

  @override
  bool operator ==(Object other) =>
      other is Task && other.id == id && other.title == title && other.done == done;

  @override
  int get hashCode => Object.hash(id, title, done);
}

// ---------------------------------------------------------------------------
// repository — single source of truth AND single write path (data/ layer).
// CONCRETE on purpose: it runs headless in flutter test, so it earns no interface.
// A real app backs this with a database; here an in-memory stream stands in.
// ---------------------------------------------------------------------------
final class TaskRepository {
  final _store = <String, Task>{};
  final _controller = StreamController<List<Task>>.broadcast();

  Stream<List<Task>> watchTasks() async* {
    yield _snapshot();                       // seed the current value
    yield* _controller.stream;               // then live updates
  }

  Future<void> add(Task task) async {
    _store[task.id] = task;                  // persist FIRST
    _controller.add(_snapshot());            // THEN publish — never the reverse
  }

  Future<void> toggle(String id) async {
    final task = _store[id];
    if (task == null) return;
    _store[id] = task.copyWith(done: !task.done);
    _controller.add(_snapshot());
  }

  List<Task> _snapshot() => _store.values.toList(growable: false);

  void dispose() => _controller.close();
}

// ---------------------------------------------------------------------------
// DI — providers are the dependency injection. Infra is a keepAlive placeholder
// overridden at the composition root (and in every test).
// ---------------------------------------------------------------------------
final taskRepositoryProvider = Provider<TaskRepository>((ref) {
  throw UnimplementedError('override in bootstrap() / test setup');
});

// An injected id source keeps the Task value object free of any UI-framework type
// (no UniqueKey) — the same discipline the architecture uses for an injected Clock.
typedef IdGenerator = String Function();

final idGeneratorProvider = Provider<IdGenerator>((ref) {
  throw UnimplementedError('override in bootstrap() / test setup');
});

// ---------------------------------------------------------------------------
// ViewModel — one per feature. build() returns the live repository stream; an
// intent method commits through the single write path and the watched stream
// RE-EMITS. No manual `state = ...` republish, no notifyListeners, no mutable field.
// ---------------------------------------------------------------------------
final class TaskListNotifier extends StreamNotifier<List<Task>> {
  @override
  Stream<List<Task>> build() =>
      ref.watch(taskRepositoryProvider).watchTasks();   // track every emission

  Future<void> add(String title) async {
    final id = ref.read(idGeneratorProvider)();
    await ref.read(taskRepositoryProvider).add(Task.create(id: id, title: title));
    // No republish: the committed write makes watchTasks() re-emit.
  }

  Future<void> toggle(String id) async {
    await ref.read(taskRepositoryProvider).toggle(id);
    // Same single write path; the stream re-emits the toggled list.
  }
}

final taskListNotifierProvider =
    StreamNotifierProvider<TaskListNotifier, List<Task>>(TaskListNotifier.new);

// ---------------------------------------------------------------------------
// View — dumb ConsumerWidget. Layout + switch on state + calling intent methods.
// No data access, no business logic, no formatting, no try/catch.
// ---------------------------------------------------------------------------
final class TaskListScreen extends ConsumerWidget {
  const TaskListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(taskListNotifierProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      floatingActionButton: FloatingActionButton(
        onPressed: () =>
            ref.read(taskListNotifierProvider.notifier).add('New task'),
        child: const Icon(Icons.add),
      ),
      body: tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(taskListNotifierProvider),
            child: const Text('Retry'),
          ),
        ),
        // Render widget CLASSES, not _buildTile() helpers.
        data: (list) => ListView(
          children: [for (final t in list) _TaskTile(task: t)],
        ),
      ),
    );
  }
}

final class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task});
  final Task task;

  @override
  Widget build(BuildContext context, WidgetRef ref) => CheckboxListTile(
        value: task.done,
        title: Text(task.title),
        onChanged: (_) => ref.read(taskListNotifierProvider.notifier).toggle(task.id),
      );
}
