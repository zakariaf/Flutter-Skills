---
name: ui-states-and-feedback
description: >-
  Enforces the non-happy paths every screen owes the user — loading/empty/error/content
  resolved in ONE switch over an AsyncValue or sealed view state, never an
  isLoading+error+data bool triple; a delayed skeleton shaped like the result instead of
  a spinner that flashes; a refresh that keeps stale content on screen; "nothing yet"
  distinguished from "nothing matches this filter", each with its own action; error text
  from a typed Failure code (never e.toString()) plus a retry that invalidates the
  provider; the surface ladder inline, snackbar, banner, dialog, with a modal earned
  only by a decision that must resolve now; soft-delete + Undo over a confirmation;
  showDialog's null dismissal handled as its own outcome; ScaffoldMessenger captured
  before an await; and announcements for eye-only changes. Use when writing
  loading, empty, error, or offline UI, calling AsyncValue.when, showDialog,
  showModalBottomSheet, showSnackBar or showMaterialBanner, or adding a confirmation,
  Undo, or retry.
---

# UI states and feedback

Most of a screen's code is the happy path; most of its defects are not. This skill
governs everything a screen shows when there is no data yet, no data at all, no data
matching the filter, a failure, or a write that just returned — and which *surface* each
of those is allowed to use. The first-frame/cold-start path belongs to
`app-startup-and-bootstrap`; the error *values* belong to `error-handling-typed-results`.
This skill is only about how they are rendered and announced.

## Non-negotiable rules

1. **One state, resolved in one place.** A screen renders exactly one of
   loading / empty / error / content, chosen by a single `switch` over an `AsyncValue`
   or a sealed view state. Never a triple of `isLoading`, `error`, `items` booleans.
   WHY: separate flags make impossible states representable — loading *and* error, empty
   *and* loading — and every such combination eventually renders.
2. **The ViewModel decides the state; the View renders it.** No `FutureBuilder` or
   `StreamBuilder` wrapped around a repository call in the middle of a widget tree.
   WHY: state scattered across the tree cannot be tested without pumping widgets, and
   rebuilds re-fire the future. See `state-management-riverpod`, `widget-composition`.
3. **Empty, filtered-empty, and error are three different screens.** "You haven't added
   anything yet" (offer the primary action), "Nothing matches *this filter*" (offer to
   clear it), and "We couldn't load this" (offer retry) answer three different user
   questions. WHY: showing "no items" for a failed load teaches the user their data is
   gone.
4. **Never render an exception.** No `e.toString()`, no stack trace, no failure class
   name in the UI. Map the typed `Failure.code` to a localized message via ARB. WHY: a
   raw exception is untranslatable, unactionable, and often leaks paths or ids.
5. **Every error state offers a next action.** Retry (`ref.invalidate(provider)`), go
   back, or change the input — and retry must preserve scroll position, filters, and
   entered text. WHY: a dead-end error screen turns a transient failure into an uninstall.
6. **A refresh never blanks the screen.** While reloading, keep the previous content and
   show a subtle indicator (`AsyncValue.when`'s `skipLoadingOnRefresh` default, or
   `valueOrNull` + `isRefreshing`). WHY: replacing a list with a spinner loses the user's
   place and reads as data loss.
7. **Loading is a delayed skeleton shaped like the result** — not a centered spinner.
   Suppress it for roughly the first 150–300 ms so a fast load does not flash, and match
   the final layout so nothing jumps when content arrives. WHY: a flash and a reflow are
   two separate perceived defects; both are free to avoid. (Every duration in this skill
   is a behavioral threshold, not a value to hardcode — the numbers themselves belong to
   the duration tokens in `design-system-structure`.)
8. **An in-flight action shows progress on its own control, not over the app.** Disable
   the button, show progress in it, keep the rest interactive. A full-screen modal
   barrier is earned only when continuing would corrupt state. WHY: a blocking barrier
   over a 200 ms write is the most common self-inflicted "the app froze".
9. **Pick the surface by the ladder: inline < snackbar < banner < dialog.** Take the
   lowest one that works (table below). A modal is earned only by a decision that must
   resolve before the user can continue. WHY: every step up the ladder takes control
   away from the user, and dialogs are the only one that also blocks.
10. **Information the user must act on never lives only in a snackbar.** It
    auto-dismisses, it can be missed entirely, and a screen reader may never reach it.
    Use a banner or an inline state for anything that still matters in ten seconds.
11. **Prefer soft delete + Undo over a confirmation dialog.** Confirm only what is
    genuinely irreversible, and then name the consequence ("Delete 12 notes permanently")
    rather than asking "Are you sure?", with `barrierDismissible: false`. WHY: Undo is
    faster for the 99% who meant it and safer for the 1% who did not. See
    `error-handling-typed-results` for the soft-delete write path.
12. **`showDialog`/`showModalBottomSheet` return `Future<T?>` — `null` means dismissed,
    and it is its own outcome.** Switch over a sealed result and handle dismissal
    explicitly; never `?? true`. WHY: `?? true` silently converts a tap outside the
    dialog into a confirmed deletion.
13. **Capture `ScaffoldMessenger`/`Navigator` before the `await`, guard `mounted` after.**
    Then show the snackbar. WHY: the `BuildContext` may be gone when the write returns —
    this is the exact `use_build_context_synchronously` hole (`async-safety`).
14. **Announce what only the eye can see.** A result that appears (saved, deleted,
    retried, filtered) is announced with `liveRegion: true` or `SemanticsService.announce`,
    and auto-dismissal is lengthened or removed when
    `MediaQuery.accessibleNavigationOf(context)` is true. WHY: a 4-second snackbar is
    invisible to a screen-reader user mid-sentence. Announcements are best-effort per
    platform — never the *only* channel for something important.

## The four states — one resolution point

```dart
class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final notes = ref.watch(notesProvider);

    // ONE switch. skipLoadingOnRefresh (default true) keeps the list on screen
    // while it reloads — the refresh path never falls into `loading`.
    return notes.when(
      loading: () => const NotesSkeleton(),          // shaped like the list, delayed
      error: (error, _) => ErrorStateView(
        // A typed Failure's stable code → a localized string. Never e.toString().
        message: l10n.failureMessage(error is Failure ? error.code : 'error.unknown'),
        onRetry: () => ref.invalidate(notesProvider),
      ),
      data: (notes) => notes.isEmpty
          ? EmptyStateView(                          // "nothing yet" ≠ "no matches"
              title: l10n.notesEmptyTitle,
              action: l10n.notesEmptyCreate,
              onAction: () => ref.read(notesProvider.notifier).createDraft(),
            )
          : NotesListView(notes: notes),
    );
  }
}
```

A screen with filters resolves *filtered-empty* before *empty*: the ViewModel knows
whether a filter is active, so the View never has to guess why the list is short.
Complete file, including the delayed skeleton and the partial-failure row state:
`examples/async_state_view.dart`.

## The surface ladder

| Surface | Lifetime | Use it for | Never use it for |
|---|---|---|---|
| **Inline** (in the field/region it concerns) | Until resolved | Validation, a per-item failure, an empty region | A global condition |
| **Snackbar** | Seconds, auto-dismiss | A completed action + its Undo; a non-critical, already-recovered failure | Anything the user must act on, or anything they'd want to re-read |
| **Banner** (`showMaterialBanner`) | Until dismissed | An app-level condition that persists: offline, expired data, a degraded mode | A transient confirmation |
| **Dialog / modal sheet** | Blocks until resolved | A decision that must resolve *now*, an irreversible confirmation | Showing information, reporting a result, or anything you could render inline |

A per-item failure inside a list is an **inline row state**, not a screen state — one
row that failed to sync must not replace the other forty-nine.

## Feedback after a write

```dart
Future<void> _delete(BuildContext context, WidgetRef ref, NoteId id) async {
  // Capture BEFORE the await — the context may be gone when the write returns.
  final messenger = ScaffoldMessenger.of(context);
  final l10n = AppLocalizations.of(context);

  final result = await ref.read(notesProvider.notifier).softDelete(id);
  if (!context.mounted) return;

  switch (result) {
    case Ok():
      messenger.clearSnackBars(); // don't queue behind an older one
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.noteDeleted),
        // Undo instead of a pre-emptive "Are you sure?" dialog.
        action: SnackBarAction(
          label: l10n.undo,
          onPressed: () => ref.read(notesProvider.notifier).restore(id),
        ),
        // Auto-dismiss is a barrier for screen-reader and switch users.
        duration: MediaQuery.accessibleNavigationOf(context)
            ? const Duration(seconds: 30)
            : const Duration(seconds: 6),
      ));
    case Err(:final failure):
      // A failure the user must act on is NOT a snackbar.
      messenger.showMaterialBanner(deleteFailedBanner(l10n, failure.code));
  }
}
```

`SnackBarAction` is the Undo affordance for a *soft* delete: the row is flagged, not
destroyed, and the hard delete happens later (`error-handling-typed-results`). An Undo
that cannot actually restore the record is worse than no Undo.

## Confirming something irreversible

```dart
// Sealed outcome — dismissal is a real case, not a missing value.
sealed class ConfirmOutcome {}
final class ConfirmAccepted implements ConfirmOutcome {}
final class ConfirmDeclined implements ConfirmOutcome {}
final class ConfirmDismissed implements ConfirmOutcome {} // tapped outside / back

final outcome = await showDialog<ConfirmOutcome>(
      context: context,
      barrierDismissible: false, // a decision that must resolve does not evaporate
      builder: (_) => PermanentDeleteDialog(count: selected.length),
    ) ??
    ConfirmDismissed(); // null == dismissed — NEVER `?? ConfirmAccepted()`
```

The dialog's title names the consequence and the count; the confirming button carries
the verb ("Delete permanently"), never "OK". Destructive verbs and the count are what a
user reads before tapping — "Are you sure?" tells them nothing.

## Anti-patterns

- **`isLoading` + `errorMessage` + `items` as three fields** — impossible states become
  representable and eventually render.
- **`FutureBuilder` over a repository call inside `build()`** — refires on every rebuild
  and cannot be tested without a widget pump.
- **A centered spinner replacing loaded content on refresh** — loses scroll position and
  reads as data loss.
- **A spinner with no delay** — flashes on every fast load; the flash is the defect.
- **A skeleton that does not match the final layout** — content lands and everything
  jumps, which reads as jank.
- **"No items" shown for a failed load** — tells the user their data is gone.
- **`Text('${e}')` or a stack trace in the UI** — untranslatable, unactionable, leaky.
- **An error state with no action** — a transient failure becomes a dead end.
- **A dialog to report a result** ("Saved!") — blocks the user to say something a
  snackbar or nothing at all could say.
- **A critical warning in a snackbar** — auto-dismisses, may be missed, may never reach
  a screen reader.
- **`?? true` on a dialog's result** — a tap outside becomes a confirmed destruction.
- **`ScaffoldMessenger.of(context)` after an `await` with no `mounted` guard** — throws
  or targets a dead tree (`async-safety`).
- **A full-screen blocking barrier for a fast local write** — the app looks frozen.
- **A confirmation dialog on every delete instead of Undo** — punishes the 99% who meant
  it and does not actually protect the 1%.

## Definition of done

- [ ] The screen resolves exactly one of loading / empty / error / content in a single
      `switch`/`when`; no bool triple; no `FutureBuilder` over a repository call.
- [ ] Empty, filtered-empty, and error are distinct views; empty carries the primary
      action and filtered-empty offers to clear the filter.
- [ ] Error text comes from a typed `Failure.code` mapped through ARB; no exception,
      class name, or stack trace is rendered.
- [ ] Every error state has a retry/next action that preserves scroll, filters, and input.
- [ ] Refresh keeps previous content on screen; loading is a delayed skeleton matching
      the final layout.
- [ ] In-flight actions show progress on their own control; no app-wide barrier without
      a stated reason.
- [ ] Each message uses the lowest adequate surface; nothing actionable lives only in a
      snackbar; per-item failures render inline in their row.
- [ ] Destructive actions use soft delete + Undo, or a `barrierDismissible: false`
      dialog that names the consequence and count.
- [ ] Dialog dismissal is handled as its own outcome; no `?? <affirmative>`.
- [ ] `ScaffoldMessenger`/`Navigator` captured before every `await`; `mounted` guarded
      after; snackbars cleared before showing a new one.
- [ ] State changes are announced (`liveRegion`/`SemanticsService.announce`), and
      auto-dismiss is extended under `accessibleNavigation`.
- [ ] Widget tests cover all four states plus dismissal and retry.

## Related skills

- `state-management-riverpod` — where the state is decided, and `AsyncValue` ownership.
- `error-handling-typed-results` — the `Result`/`Failure` values rendered here, and the
  soft-delete/Undo write path.
- `async-safety` — capturing `context` before an `await` and guarding `mounted` after.
- `widget-composition` — dumb Views, extracted `const` state widgets, no logic in `build()`.
- `accessibility-as-code` — semantics, live regions, and the a11y flags read from
  `MediaQuery`.
- `motion-and-haptics` — the sensory half of feedback: what the transition into each of
  these states animates, the one haptic per committed action, and the reduced-motion path.
- `i18n-rtl-l10n` — every message in ARB, including failure-code messages.
- `app-startup-and-bootstrap` — the first-frame/splash path this skill does not cover.
- `widget-golden-and-a11y-testing` — pumping and asserting each of the four states.
- `design-system-structure` — where the skeleton, banner, and empty-state components live.

## References

- Material 3 — Snackbar: https://m3.material.io/components/snackbar/guidelines
- Material 3 — Banner (Material 2 spec, still the Flutter widget's basis): https://m2.material.io/components/banners
- Material 3 — Dialogs: https://m3.material.io/components/dialogs/guidelines
- Flutter — `ScaffoldMessenger`: https://api.flutter.dev/flutter/material/ScaffoldMessenger-class.html
- Flutter — `SemanticsService.announce`: https://api.flutter.dev/flutter/semantics/SemanticsService/announce.html
- Riverpod — `AsyncValue` (`when`, `skipLoadingOnRefresh`, `valueOrNull`): https://riverpod.dev/docs/essentials/async_initialization
- Nielsen Norman Group — Progress indicators and response times: https://www.nngroup.com/articles/response-times-3-important-limits/
