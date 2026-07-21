// Demonstrates a feature's Riverpod backbone: a SCOPED family StreamProvider wrapping a
// repository .watch(), plus the 1:1 command Notifier (the ViewModel) that routes every write
// through ONE repository method (the single write path) and maps the typed Result to AsyncValue.
//
// Domain: a Task list scoped by projectId. The repository (in the data layer) maps rows to the
// immutable Task value object; nothing here ever sees a Drift row. Manual (hand-written) providers
// are the default — see state-management-riverpod; @riverpod codegen is an optional alternative.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'contracts.dart'; // Task, TaskStatus, TaskFailure, Result/Ok/Err, taskRepositoryProvider, clockProvider, idGeneratorProvider

/// Reactive backbone: wrap the repository's scoped `.watch()` in a family StreamProvider,
/// keyed by [projectId] so a write for one project never re-emits for every screen.
/// `.autoDispose` frees the subscription when the screen unmounts.
final taskListProvider =
    StreamProvider.autoDispose.family<List<Task>, String>((ref, projectId) =>
        ref.watch(taskRepositoryProvider).watchTasks(projectId));

/// A derived read: rebuild only when the open-count changes, not on every list mutation.
final openTaskCountProvider =
    Provider.autoDispose.family<int, String>((ref, projectId) => ref.watch(
          taskListProvider(projectId).select(
            (async) =>
                async.valueOrNull
                    ?.where((t) => t.status == TaskStatus.open)
                    .length ??
                0,
          ),
        ));

/// The ViewModel: command state for the tasks screen. `.autoDispose` (per-screen).
/// Drop `.autoDispose` (or `ref.keepAlive()`) only if the state must outlive the route.
final tasksNotifierProvider =
    AsyncNotifierProvider.autoDispose<TasksNotifier, void>(TasksNotifier.new);

class TasksNotifier extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {
    // No synchronous heavy work here. Offload any expensive computation to Isolate.run.
  }

  /// Create a task. The write goes through ONE repository method (single write path);
  /// the committed write makes the watch stream re-emit — no manual republish.
  Future<void> add(String projectId, String title) async {
    state = const AsyncLoading();
    final draft = Task(
      id: _newId(),
      projectId: projectId,
      title: title,
      status: TaskStatus.open,
      createdAtUtc: ref.read(clockProvider).now().toUtc(), // injected Clock, never DateTime.now()
    );
    state = switch (await ref.read(taskRepositoryProvider).addTask(draft)) {
      Ok() => const AsyncData(null),
      Err(:final failure) => AsyncError(failure, StackTrace.current), // typed, localized in the View
    };
  }

  /// Toggle completion. Reversible in-session? No — completion is durable, so it crosses the
  /// write path immediately. A transient draft being typed would stay in state instead.
  Future<void> complete(String taskId) async {
    final Result<void, TaskFailure> r =
        await ref.read(taskRepositoryProvider).markComplete(taskId);
    if (r case Err(:final failure)) {
      state = AsyncError(failure, StackTrace.current);
    }
  }

  String _newId() => ref.read(idGeneratorProvider).next();
}
