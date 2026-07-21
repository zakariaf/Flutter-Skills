// Demonstrates the Future-dropped-in-a-callback hole that NO lint catches, its
// structural fix, and the one legitimate shape of an `// ignore:` suppression.
//
// The point: a green analyzer is not proof an operation ran. The mitigation is
// structural (a void-returning method), never disciplinary (remembering to
// await). See references/config-mechanics.md for why the lints miss this.

import 'dart:async';

// ---------------------------------------------------------------------------
// THE HOLE
// ---------------------------------------------------------------------------
// `onPressed: () => repository.save(note)` is flagged by NOTHING:
//   - not discarded_futures: the arrow closure RETURNS the Future, so the rule
//     considers it used;
//   - not unawaited_futures: the target type is VoidCallback, so Dart discards
//     the returned Future silently before any async body sees it.
// The save fails, the error evaporates, and the analyzer stays green.

// ---------------------------------------------------------------------------
// THE FIX: a void-returning intent method a callback can hold safely.
// ---------------------------------------------------------------------------
class NoteController {
  NoteController(this._repository);

  final NoteRepository _repository;

  /// Persists [note] as fire-and-forget from a UI callback. Returns `void` so
  /// no caller can accidentally drop a Future; failures are routed to the
  /// report path instead of vanishing.
  void saveNow(Note note) {
    unawaited(_repository.save(note).catchError(_report));
  }

  void _report(Object error, StackTrace stack) {
    // Forward to your logging/reporting seam (never print in shipped lib/).
  }
}

// A callback then never touches a Future, so the hole is unreachable:
//   onPressed: () => controller.saveNow(note),

// ---------------------------------------------------------------------------
// THE ONE LEGITIMATE SUPPRESSION SHAPE
// ---------------------------------------------------------------------------
// Line-scoped, on a non-promoted STYLE lint only, with the reason on the line
// above. Never `// ignore_for_file:`, never on a promoted safety rule (a cast,
// a dropped Future, a swallowed catch), never on an architecture/import gate.
// Here: two sequential appends read more clearly as separate statements than
// folded into a cascade — `cascade_invocations` is pure style, so silencing it
// hides no bug. That is the only kind of rule a line ignore may touch.
String renderHeader(Note note) {
  final buffer = StringBuffer()..write(note.id);
  // ignore: cascade_invocations — kept as its own statement so the body append
  // diffs cleanly; a style lint, never a promoted rule, so nothing is silenced.
  buffer.write(': ${note.body}');
  return buffer.toString();
}

// ---------------------------------------------------------------------------
// Minimal collaborators so this file is self-contained.
// ---------------------------------------------------------------------------
class Note {
  const Note(this.id, this.body);
  final String id;
  final String body;
}

abstract interface class NoteRepository {
  Future<void> save(Note note);
}
