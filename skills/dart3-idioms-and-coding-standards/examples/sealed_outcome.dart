// Demonstrates: a sealed hierarchy of individually-actionable outcomes, an
// intermediate sealed layer, destructuring in an exhaustive switch with NO
// `default:`, and a switch EXPRESSION where every arm yields a value.
//
// Adding a new variant to any of these hierarchies turns every switch below
// into a compile error until the new case is handled — that is the whole point.

import 'package:meta/meta.dart';

@immutable
sealed class SaveOutcome {
  const SaveOutcome();
}

final class Saved extends SaveOutcome {
  const Saved(this.revision);
  final int revision;
}

/// Intermediate sealed layer: every [SaveFailure] carries the draft the caller
/// must not lose, so a switch can handle the whole group uniformly OR drill in.
@immutable
sealed class SaveFailure extends SaveOutcome {
  const SaveFailure(this.pendingDraft);
  final String pendingDraft;
}

final class OfflineNoConnection extends SaveFailure {
  const OfflineNoConnection(super.pendingDraft);
}

final class QuotaExceeded extends SaveFailure {
  const QuotaExceeded(super.pendingDraft, {required this.limitBytes});
  final int limitBytes;
}

/// Switch STATEMENT — arms perform effects, so this is not an expression.
/// No `default:`; a new SaveOutcome variant is a compile error here.
void handleSave(SaveOutcome outcome, void Function(String) keepDraft) {
  switch (outcome) {
    case Saved(:final revision):
      // ignore: avoid_print — illustrative only
      print('saved as revision $revision');
    case SaveFailure(:final pendingDraft):
      // Intermediate match: every failure keeps the draft, uniformly.
      keepDraft(pendingDraft);
  }
}

/// Switch EXPRESSION — every arm yields a value, exhaustive by construction.
/// Drilling into the concrete failures where the response differs.
String describe(SaveOutcome outcome) => switch (outcome) {
      Saved(:final revision) => 'Saved (r$revision)',
      OfflineNoConnection() => 'Offline — kept your draft',
      QuotaExceeded(:final limitBytes) => 'Over the $limitBytes-byte limit',
    };
