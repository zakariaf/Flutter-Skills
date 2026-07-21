// Demonstrates: total (never-throwing) pure domain functions. Uncertainty is an
// explicit RETURN VALUE (a clamped result, a sealed "no match" outcome), a
// programmer invariant is an `assert` (stripped in release). No `throw` for a
// normal outcome, no `!`, no `dynamic`. These functions return for every input.

import 'package:meta/meta.dart';

/// Total: clamps an out-of-range index instead of throwing. `assert` guards a
/// programmer invariant (an empty list is a caller bug), not a normal outcome.
int clampIndex(int requested, int length) {
  assert(length >= 1, 'length must be positive');
  if (requested < 0) return 0;
  if (requested >= length) return length - 1;
  return requested;
}

/// A parse that cannot throw: the failure is a value the caller must handle.
@immutable
sealed class ParseResult {
  const ParseResult();
}

final class ParsedQuantity extends ParseResult {
  const ParsedQuantity(this.value);
  final int value;
}

final class NotAQuantity extends ParseResult {
  const NotAQuantity(this.rawInput);
  final String rawInput;
}

/// Total: every String maps to a ParseResult. `int.tryParse` returns null rather
/// than throwing; we convert that null into an explicit sealed outcome.
ParseResult parseQuantity(String raw) {
  final trimmed = raw.trim();
  final value = int.tryParse(trimmed);
  if (value == null || value < 0) return NotAQuantity(raw);
  return ParsedQuantity(value);
}

/// Total allocation-free min over a non-empty list; the invariant is asserted,
/// the result is always returned.
int smallest(List<int> values) {
  assert(values.isNotEmpty, 'smallest requires a non-empty list');
  var result = values.first;
  for (final v in values) {
    if (v < result) result = v;
  }
  return result;
}
