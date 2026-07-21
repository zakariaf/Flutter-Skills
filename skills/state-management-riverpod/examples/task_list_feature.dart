// Demonstrates a complete Riverpod 3.x feature slice: a StreamNotifier ViewModel whose
// build() returns the LIVE repository stream (so a committed write re-emits with no manual
// republish — D6), a StreamProvider derived read model, an in-session filter as its own
// manual NotifierProvider, and a dumb ConsumerWidget that watches/reads/selects.
//
// Conceptual example (repository/DB bodies elided). Generic Task domain.
// Hand-written providers throughout (D7); @riverpod codegen is optional, not shown here.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// --- Domain value types (would be freezed in a real app) ---------------------

class TaskId {
  const TaskId(this.value);
  final String value;
  @override
  bool operator ==(Object other) => other is TaskId && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

class Task {
  const Task({required this.id, required this.title, required this.done});
  final TaskId id;
  final String title;
  final bool done;

  Task copyWith({bool? done}) =>
      Task(id: id, title: title, done: done ?? this.done);
}

enum TaskFilter { all, open, done }

// Immutable UI-state value with value equality. Derived values are getters.
class TaskListState {
  const TaskListState({required this.tasks, required this.filter});

  final List<Task> tasks;
  final TaskFilter filter;

  factory TaskListState.initial(List<Task> tasks) =>
      TaskListState(tasks: tasks, filter: TaskFilter.all);

  int get openCount => tasks.where((t) => !t.done).length; // derive, don't store

  List<Task> get visible => switch (filter) {
        TaskFilter.all => tasks,
        TaskFilter.open => [for (final t in tasks) if (!t.done) t],
        TaskFilter.done => [for (final t in tasks) if (t.done) t],
      };

  TaskListState copyWith({List<Task>? tasks, TaskFilter? filter}) =>
      TaskListState(tasks: tasks ?? this.tasks, filter: filter ?? this.filter);

  @override
  bool operator ==(Object other) =>
      other is TaskListState &&
      other.filter == filter &&
      _listEquals(other.tasks, tasks);
  @override
  int get hashCode => Object.hash(filter, Object.hashAll(tasks));
}

bool _listEquals(List<Task> a, List<Task> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].id != b[i].id || a[i].done != b[i].done) return false;
  }
  return true;
}

// --- Repository abstraction (the single write path) --------------------------

abstract interface class TaskRepository {
  Stream<List<Task>> watchAll(); // the live source of truth build() tracks
  Future<void> markComplete(TaskId id); // persists transactionally, returns after commit
}

// --- DI seams: throw until overridden at the composition root -----------------

final taskRepositoryProvider = Provider<TaskRepository>(
  (ref) => throw UnimplementedError('override taskRepositoryProvider in main()'),
);

// Derived read model: a projection over the source stream, never a stored cache.
final openTaskCountProvider = StreamProvider.autoDispose<int>((ref) {
  return ref
      .watch(taskRepositoryProvider)
      .watchAll()
      .map((tasks) => tasks.where((t) => !t.done).length);
});

// In-session filter: its own tiny Notifier via a manual NotifierProvider (D7).
class TaskFilterNotifier extends Notifier<TaskFilter> {
  @override
  TaskFilter build() => TaskFilter.all;
  void set(TaskFilter filter) => state = filter; // build() below watches this
}

final taskFilterProvider =
    NotifierProvider<TaskFilterNotifier, TaskFilter>(TaskFilterNotifier.new);

// --- The ViewModel: one StreamNotifier over the live query --------------------

class TaskListNotifier extends StreamNotifier<TaskListState> {
  @override
  Stream<TaskListState> build() {
    final filter = ref.watch(taskFilterProvider); // re-projects when the filter changes
    return ref
        .watch(taskRepositoryProvider)
        .watchAll() // the live source of truth — tracks EVERY emission
        .map((tasks) => TaskListState(tasks: tasks, filter: filter));
  }

  // Durable act: routes through the single write path. void action method — the Future
  // is owned inside, never dropped into a VoidCallback at the call site. No manual
  // republish: the committed write makes watchAll() re-emit and build() reruns (D6).
  void complete(TaskId id) {
    unawaited(_complete(id).catchError(_report));
  }

  Future<void> _complete(TaskId id) async {
    await ref.read(taskRepositoryProvider).markComplete(id); // returns after commit
  }

  void _report(Object error, StackTrace stack) {
    // surface via a logger / error sink — never a silent swallow
  }
}

final taskListNotifierProvider =
    StreamNotifierProvider.autoDispose<TaskListNotifier, TaskListState>(
        TaskListNotifier.new);

// --- The View: dumb ConsumerWidget. watch to show, read to act ---------------

class TaskListScreen extends ConsumerWidget {
  const TaskListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(taskListNotifierProvider);
    return Scaffold(
      appBar: AppBar(title: const _OpenCount()), // leaf rebuilds on one field
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: TextButton(
            onPressed: () => ref.invalidate(taskListNotifierProvider),
            child: const Text('Retry'),
          ),
        ),
        data: (s) => ListView(
          children: [
            for (final task in s.visible)
              CheckboxListTile(
                key: ValueKey(task.id.value),
                title: Text(task.title),
                value: task.done,
                // Pass the stable id, never the captured task value.
                onChanged: (_) =>
                    ref.read(taskListNotifierProvider.notifier).complete(task.id),
              ),
          ],
        ),
      ),
    );
  }
}

// Leaf that rebuilds only when openCount changes, via .select.
class _OpenCount extends ConsumerWidget {
  const _OpenCount();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = ref.watch(
      taskListNotifierProvider.select((s) => s.value?.openCount ?? 0),
    );
    return Text('$n open');
  }
}
