// Demonstrates a DUMB feature View: it watches one scoped stream and one controller, renders
// with .when, fires one-shot effects via ref.listen, navigates BY ID from the View (never from
// the controller), and uses Directional geometry + gen-l10n strings only. No business logic,
// no unit math, no formatting decisions live here — those belong to the ViewModel and the l10n edge.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'contracts.dart'; // AppLocalizations, localizeFailure, Task, routes, providers

class TasksScreen extends ConsumerWidget {
  const TasksScreen({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);

    // One-shot side effects (SnackBar / navigate) belong in ref.listen, not in build's body.
    ref.listen(tasksNotifierProvider, (prev, next) {
      if (next case AsyncError(:final error)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(localizeFailure(l10n, error))), // typed Failure -> localized text
        );
      }
    });

    final async = ref.watch(taskListProvider(projectId)); // watch in build

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tasksTitle)),
      floatingActionButton: FloatingActionButton(
        onPressed: () => AddTaskRoute(projectId: projectId).go(context), // navigate by ID, from View
        child: const Icon(Icons.add),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(localizeFailure(l10n, e))),
        data: (tasks) => tasks.isEmpty
            ? _EmptyState(title: l10n.tasksEmptyTitle, body: l10n.tasksEmptyBody)
            : ListView.builder(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                itemCount: tasks.length,
                itemBuilder: (context, i) => _TaskTile(
                  task: tasks[i],
                  onTap: () => TaskDetailRoute(
                    projectId: projectId,
                    taskId: tasks[i].id,
                  ).go(context),
                  onToggle: () => ref
                      .read(tasksNotifierProvider.notifier) // read in callbacks
                      .complete(tasks[i].id),
                ),
              ),
      ),
    );
  }
}

/// A leaf widget: a small const class, not a _buildX() method. Takes primitives + callbacks;
/// reads no providers. Directional insets only.
class _TaskTile extends StatelessWidget {
  const _TaskTile({
    required this.task,
    required this.onTap,
    required this.onToggle,
  });

  final Task task;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsetsDirectional.only(start: 16, end: 8),
      leading: Checkbox(
        value: task.status == TaskStatus.done,
        onChanged: (_) => onToggle(),
      ),
      title: Text(task.title),
      onTap: onTap,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsetsDirectional.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
