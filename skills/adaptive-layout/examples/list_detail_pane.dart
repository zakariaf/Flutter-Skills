// Shows: a list-detail (master-detail) screen that collapses to a single
// navigating pane on compact width and splits side-by-side on expanded width,
// with the selection held in a Riverpod Notifier so it survives a resize.
// Domain: a generic Task list + task detail.

import 'package:collection/collection.dart'; // firstOrNull (transitive Flutter dep)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// --- shared size-class helper (normally imported from a core file) -----------

enum WindowSizeClass { compact, medium, expanded, large, extraLarge }

WindowSizeClass windowSizeClassFor(double width) => switch (width) {
      < 600 => WindowSizeClass.compact,
      < 840 => WindowSizeClass.medium,
      < 1200 => WindowSizeClass.expanded,
      < 1600 => WindowSizeClass.large,
      _ => WindowSizeClass.extraLarge,
    };

extension WindowSizeClassX on WindowSizeClass {
  bool get canShowTwoPanes => index >= WindowSizeClass.expanded.index;
}

// --- domain + shared selection state ----------------------------------------

typedef TaskId = String;

@immutable
class Task {
  const Task({required this.id, required this.title, required this.details});
  final TaskId id;
  final String title;
  final String details;
}

/// Manual provider (Riverpod 3.x default). In a real app this watches a repo.
final tasksProvider = Provider<List<Task>>((ref) => const [
      Task(id: 't1', title: 'Draft proposal', details: 'Outline the scope.'),
      Task(id: 't2', title: 'Review PR', details: 'Check the migration path.'),
      Task(id: 't3', title: 'Plan sprint', details: 'Groom the backlog.'),
    ]);

/// Selection lives ABOVE both panes so crossing a breakpoint (or rotating)
/// preserves which task is open.
final selectedTaskProvider =
    NotifierProvider<SelectedTaskNotifier, TaskId?>(SelectedTaskNotifier.new);

class SelectedTaskNotifier extends Notifier<TaskId?> {
  @override
  TaskId? build() => null;
  void select(TaskId id) => state = id;
  void clear() => state = null;
}

// --- the adaptive screen -----------------------------------------------------

class TasksScreen extends ConsumerWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final twoPane =
        windowSizeClassFor(MediaQuery.sizeOf(context).width).canShowTwoPanes;

    if (!twoPane) {
      // Compact: list only. Tapping navigates to a detail route.
      return Scaffold(
        appBar: AppBar(title: const Text('Tasks')),
        body: SafeArea(
          child: _TaskListPane(
            onTap: (id) {
              ref.read(selectedTaskProvider.notifier).select(id);
              Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => _TaskDetailRoute(id: id),
              ));
            },
          ),
        ),
      );
    }

    // Expanded+: list and detail side by side; tapping updates the right pane.
    final selected = ref.watch(selectedTaskProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Tasks')),
      body: SafeArea(
        child: Row(
          children: [
            // A bounded control column paired with an Expanded content pane is
            // the one idiomatic place for a fixed width.
            SizedBox(
              width: 360,
              child: _TaskListPane(
                selectedId: selected,
                onTap: (id) =>
                    ref.read(selectedTaskProvider.notifier).select(id),
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: selected == null
                  ? const _DetailPlaceholder()
                  : _TaskDetailPane(id: selected),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskListPane extends ConsumerWidget {
  const _TaskListPane({required this.onTap, this.selectedId});
  final ValueChanged<TaskId> onTap;
  final TaskId? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(tasksProvider);
    return ListView.builder(
      itemCount: tasks.length,
      itemBuilder: (context, i) {
        final task = tasks[i];
        return ListTile(
          selected: task.id == selectedId,
          title: Text(task.title),
          subtitle: Text(task.details, maxLines: 1),
          onTap: () => onTap(task.id),
        );
      },
    );
  }
}

/// Wraps the detail pane in a Scaffold for the compact navigation flow.
class _TaskDetailRoute extends StatelessWidget {
  const _TaskDetailRoute({required this.id});
  final TaskId id;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Task')),
      body: SafeArea(child: _TaskDetailPane(id: id)),
    );
  }
}

class _TaskDetailPane extends ConsumerWidget {
  const _TaskDetailPane({required this.id});
  final TaskId id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task =
        ref.watch(tasksProvider).where((t) => t.id == id).firstOrNull;
    if (task == null) return const _DetailPlaceholder();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640), // readable measure
        child: ListView(
          // Placeholder spacing — real spacing tokens come from
          // `design-system-structure`; only the width caps here are structural.
          padding: const EdgeInsets.all(24),
          children: [
            Text(task.title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12), // placeholder spacing
            Text(task.details, style: Theme.of(context).textTheme.bodyLarge),
          ],
        ),
      ),
    );
  }
}

class _DetailPlaceholder extends StatelessWidget {
  const _DetailPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text('Select a task',
          style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
