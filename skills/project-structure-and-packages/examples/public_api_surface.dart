// Demonstrates the public-API-surface discipline for an extracted package:
// one file exposes stable public types while keeping helpers package-private,
// and a sealed hierarchy lives entirely in one file (the file IS the closed set).
//
// In a real package this content would sit under lib/src/ and be re-exported by
// the single barrel lib/<package>.dart with `export 'src/order.dart' show Order, ...;`.
// This file is self-contained and compiles on its own (pure Dart, no Flutter).

import 'package:meta/meta.dart';

/// A customer order — a public value type, exported from the package barrel.
@immutable
final class Order {
  const Order({required this.id, required this.lines});

  final String id;
  final List<OrderLine> lines;

  /// Derived, never stored: the total is a pure function of the lines.
  int get totalMinorUnits =>
      lines.fold(0, (sum, line) => sum + line._extended());

  @override
  bool operator ==(Object other) =>
      other is Order &&
      other.id == id &&
      _sameLines(other.lines, lines);

  @override
  int get hashCode => Object.hash(id, Object.hashAll(lines));
}

/// A single line on an [Order] — also public.
@immutable
final class OrderLine {
  const OrderLine({required this.priceMinorUnits, required this.quantity});

  final int priceMinorUnits;
  final int quantity;

  // Package-private helper: leading underscore keeps it off the public surface,
  // so it never needs its own file and never leaks from the barrel.
  int _extended() => priceMinorUnits * quantity;

  @override
  bool operator ==(Object other) =>
      other is OrderLine &&
      other.priceMinorUnits == priceMinorUnits &&
      other.quantity == quantity;

  @override
  int get hashCode => Object.hash(priceMinorUnits, quantity);
}

/// The outcome of persisting an order. A sealed hierarchy is the one case where
/// several types share a file, because the file boundary is the closed set the
/// compiler exhaustively checks in a switch.
sealed class SaveOutcome {
  const SaveOutcome();
}

final class SaveSucceeded extends SaveOutcome {
  const SaveSucceeded(this.order);
  final Order order;
}

final class SaveRejected extends SaveOutcome {
  const SaveRejected(this.code);

  /// A stable machine code, never a localized string (see error-handling-typed-results).
  final String code;
}

bool _sameLines(List<OrderLine> a, List<OrderLine> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
