// Demonstrates a dumb ConsumerWidget View that watches ONE Notifier and renders,
// composed from small const widget CLASSES (never _buildX() methods), with intents
// routed via ref.read(...notifier), a lazy keyed list, and a domain-blind card.
//
// The Notifier/state types are elided; this file shows the widget layer only.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Elided: `taskListNotifierProvider` is an AsyncNotifier exposing TaskListState.
// It precomputes ready-to-render rows (labels localized, values formatted) so the
// View does zero domain math. See state-management-riverpod.

// ─── Immutable view-data the Notifier hands down (no domain entity in the UI) ───
@immutable
class TaskRow {
  const TaskRow({required this.id, required this.title, required this.dueLabel});

  final String id;
  final String title;   // already-localized
  final String dueLabel; // already-formatted
}

// ─── 1. THE VIEW — dumb: watches one Notifier, maps AsyncValue, routes intents ───
class TaskListScreen extends ConsumerWidget {
  const TaskListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(taskListNotifierProvider);
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface, // full-bleed
      appBar: AppBar(title: const Text('Tasks')), // TODO: localize via ARB
      body: SafeArea(
        child: state.when(
          loading: () => const _LoadingView(),
          error: (_, __) => _ErrorView(
            onRetry: () => ref.invalidate(taskListNotifierProvider),
          ),
          data: (rows) => _TaskListBody(
            rows: rows,
            // Intent up: resolve the stable id, never a captured content value.
            onToggle: (id) =>
                ref.read(taskListNotifierProvider.notifier).toggleDone(id),
          ),
        ),
      ),
    );
  }
}

// ─── 2. A feature-local section CLASS (not a _buildBody() method), lazy + keyed ──
class _TaskListBody extends StatelessWidget {
  const _TaskListBody({required this.rows, required this.onToggle});

  final List<TaskRow> rows;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) return const _EmptyView();
    return ListView.builder(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 8), // RTL-safe
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        return TaskCard(
          key: ValueKey(row.id), // stable identity in a variable list
          title: row.title,
          dueLabel: row.dueLabel,
          onToggle: () => onToggle(row.id),
        );
      },
    );
  }
}

// ─── 3. A shared, domain-blind card: primitives + callbacks only, no ref ────────
class TaskCard extends StatelessWidget {
  const TaskCard({
    required this.title,
    required this.dueLabel,
    required this.onToggle,
    super.key,
  });

  final String title;    // already-localized
  final String dueLabel; // already-formatted
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context); // read theme in the leaf that uses it
    return Card(
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsetsDirectional.all(12),
          child: Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              const SizedBox(width: 8), // cheapest widget for a gap
              Text(dueLabel, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Small shared stubs ─────────────────────────────────────────────────────────
class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();
  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('No tasks yet')); // TODO: localize via ARB
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Center(
        child: TextButton(onPressed: onRetry, child: const Text('Retry')),
      );
}
