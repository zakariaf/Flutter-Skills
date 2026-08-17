// A complete four-state screen: ONE resolution point over AsyncValue, a delayed
// skeleton that suppresses the flash on a fast load, filtered-empty resolved
// before empty, an error view built from a typed Failure code with a retry that
// preserves the user's place, and a per-item failure rendered inline in its row
// instead of replacing the whole list.
//
// Domain is neutral (Note). l10n calls stand in for generated AppLocalizations.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// --- The screen: one switch, four states -------------------------------------

class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final notes = ref.watch(notesProvider);
    // The ViewModel knows whether a filter is active, so the View never has to
    // guess WHY the list is short.
    final isFiltered = ref.watch(notesFilterProvider).isActive;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.notesTitle)),
      body: notes.when(
        // skipLoadingOnRefresh defaults to true: a refresh keeps the list on
        // screen and never falls into this branch.
        loading: () => const DelayedSkeleton(child: NotesSkeleton()),
        error: (error, _) => ErrorStateView(
          message: l10n.failureMessage(error is Failure ? error.code : 'error.unknown'),
          // Retry re-runs the provider; scroll position, filters and entered
          // text all survive because none of them live in this provider.
          onRetry: () => ref.invalidate(notesProvider),
        ),
        data: (items) => switch ((items.isEmpty, isFiltered)) {
          // Filtered-empty is resolved BEFORE empty — different question,
          // different answer, different action.
          (true, true) => EmptyStateView(
              title: l10n.notesNoMatches,
              actionLabel: l10n.clearFilter,
              onAction: () => ref.read(notesFilterProvider.notifier).clear(),
            ),
          (true, false) => EmptyStateView(
              title: l10n.notesEmptyTitle,
              actionLabel: l10n.notesEmptyCreate,
              onAction: () => ref.read(notesProvider.notifier).createDraft(),
            ),
          (false, _) => NotesListView(items: items),
        },
      ),
    );
  }
}

// --- Loading: delayed, and shaped like the result ----------------------------

/// Renders nothing for [delay], then [child].
///
/// A spinner shown instantly flashes on every fast load — the flash IS the
/// perceived defect. Suppressing the first ~200 ms removes it without ever
/// leaving a slow load unexplained.
class DelayedSkeleton extends StatefulWidget {
  const DelayedSkeleton({
    required this.child,
    this.delay = const Duration(milliseconds: 200),
    super.key,
  });

  final Widget child;
  final Duration delay;

  @override
  State<DelayedSkeleton> createState() => _DelayedSkeletonState();
}

class _DelayedSkeletonState extends State<DelayedSkeleton> {
  Timer? _timer;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel(); // every timer cancelled — see `async-safety`
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _visible ? widget.child : const SizedBox.shrink();
}

/// The skeleton mirrors the real row's geometry, so nothing jumps when data
/// arrives. `ExcludeSemantics` keeps placeholder shapes out of the a11y tree.
class NotesSkeleton extends StatelessWidget {
  const NotesSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ListView.builder(
        itemCount: 6,
        itemBuilder: (_, __) => const _SkeletonRow(),
      ),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surfaceContainerHighest;
    // Same height and insets as NoteRow — matching geometry is the whole point.
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 12),
      child: SizedBox(
        height: 40,
        child: DecoratedBox(decoration: BoxDecoration(color: surface)),
      ),
    );
  }
}

// --- Empty and error ---------------------------------------------------------

class EmptyStateView extends StatelessWidget {
  const EmptyStateView({
    required this.title,
    required this.actionLabel,
    required this.onAction,
    super.key,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    // liveRegion: the state change is announced to a screen reader that did not
    // "see" the list disappear.
    return Semantics(
      liveRegion: true,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            // An empty state without its primary action is a dead end.
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class ErrorStateView extends StatelessWidget {
  const ErrorStateView({required this.message, required this.onRetry, super.key});

  /// Already localized, resolved from a typed Failure's stable code.
  /// NEVER an exception's toString().
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      liveRegion: true,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: Text(l10n.retry)),
          ],
        ),
      ),
    );
  }
}

// --- Partial failure: a row state, not a screen state ------------------------

class NoteRow extends StatelessWidget {
  const NoteRow({required this.note, required this.onRetrySync, super.key});

  final Note note;
  final VoidCallback onRetrySync;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListTile(
      title: Text(note.title),
      // One row that failed must not replace the other forty-nine. The failure
      // is inline, in the row it belongs to, with its own action.
      subtitle: note.syncFailed
          ? Row(
              children: [
                // Never colour-alone: the icon and the text both carry the state.
                Icon(Icons.error_outline,
                    size: 16, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 4),
                Expanded(child: Text(l10n.rowSyncFailed)),
                TextButton(onPressed: onRetrySync, child: Text(l10n.retry)),
              ],
            )
          : Text(note.preview),
    );
  }
}
