# Value-type domain modelling

The money core is a set of pure, immutable value types with an explicit compute
pipeline. This file pins the modelling choices; the math lives in
`allocate-and-splitting.md`.

## Value types, not mutable records

- **Domain models are immutable value types** with value equality (`==` +
  `hashCode` over all data fields, or a `freezed`/records equivalent). Copied
  freely, comparable, trivially safe to pass around and test.
- **Illegal states unrepresentable via sealed types.** A tip is
  `PercentTip | FixedTip`; a payment state is `sealed`. Switch exhaustively with
  **no `default`**, so a new case is a compile error until every site handles it.
- **State is private + mutated only through intent methods** (in the ViewModel
  layer — see `state-management-riverpod`). The value objects themselves are
  `const`-constructible and never mutate in place.

## Identity: explicit stable id

```dart
final class Participant {
  const Participant({required this.id, required this.name});
  final String id;   // stable identity (e.g. a UUID) — NOT derived from fields
  final String name;
}
```

Never derive identity from equality-on-all-fields, or two participants named
"Sam" collapse into one. The `id` is assigned once and never changes.

## Relationships are id links, not embedded copies

Model an assignment as a **set of ids on the item**, kept separate from the
item's price and label:

```dart
final class LineItem {
  const LineItem({
    required this.id,
    required this.label,
    required this.amount,          // Money
    required this.assigneeIds,     // Set<String> — links, empty ⇒ unassigned
  });
  final String id;
  final String label;
  final Money amount;
  final Set<String> assigneeIds;
}
```

Consequences: editing a price leaves assignments intact; deleting a participant
just drops their id from sharer sets; an empty assignee set surfaces as
*unassigned* (flagged, never charged silently) rather than crashing.

## Derive, don't store totals

A stored, denormalized total is the classic drift bug — the moment an item or
assignment changes, the stored total is stale. Compute results on read from the
inputs, and return them in a **derived** result type that is never persisted:

```dart
// Persisted inputs:
final class Order {
  const Order({
    required this.currency,
    required this.participants,
    required this.items,
    required this.taxMinor,
    required this.tip,
  });
  final Currency currency;
  final List<Participant> participants;
  final List<LineItem> items;
  final int taxMinor;   // exact printed tax, in minor units
  final TipMode tip;
}

// Derived — NEVER stored on Order:
final class Breakdown {
  const Breakdown({required this.subtotal, required this.tax,
      required this.tip, required this.total});
  final Money subtotal, tax, tip, total;
}

final class OrderResult {
  const OrderResult({required this.perParticipant, required this.grandTotal});
  final Map<String, Breakdown> perParticipant; // keyed by participant id
  final Money grandTotal;
}
```

## One currency per aggregate

Make `currency` a fact of the enclosing aggregate (`Order`), not of each
`Money`-carrying field. Then `Money` arithmetic within the aggregate never has to
guard currency equality, and cross-currency mixing is structurally impossible
without going through an explicit FX conversion boundary.

## Pure, total compute functions

The compute pipeline is a set of **pure, total** functions — they never throw for
user input; they validate/clamp at entry and return a derived result:

```dart
abstract final class OrderMath {
  /// Per-participant subtotals; shared items split via allocate([1,…]).
  static Map<String, Money> subtotals(Order order) => /* … */ {};

  /// percent → minor units ONCE (rounding site #2), then allocate.
  static int resolveTipMinor(Order order, int subtotalMinor) => /* … */ 0;

  /// subtotals → allocate(tax, subtotals) → allocate(tip, subtotals).
  static OrderResult compute(Order order) => /* … */
      throw UnimplementedError();
}
```

The only real error surface is persistence and parsing at the edges — those
return the sealed `Result`/`Failure` (see `error-handling-typed-results`), never
throw across the boundary. The core throws only for **programmer errors**
(currency mismatch, unsupported exponent) via `ArgumentError`/`StateError`/`assert`.
