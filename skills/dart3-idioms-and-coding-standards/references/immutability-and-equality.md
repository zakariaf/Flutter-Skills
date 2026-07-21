# Immutability, equality, and identity

Domain values are immutable value types. This is the four-line hand-rolled pattern for a *trivial* immutable (1–3 fields), plus the rules for when to hand-write equality and how to model identity. Once `copyWith`/`==`/`hashCode`/sealed-union boilerplate dominates a non-trivial domain or UI-state type, reach for `freezed` instead — see the `freezed` verdict in `references/construct-verdict-table.md`. The equality and identity rules below apply either way.

## The immutable value type

```dart
@immutable
final class Account {
  const Account({
    required this.id,
    required this.name,
    required this.balanceMinor,
  });

  final String id;
  final String name;
  final int balanceMinor;

  Account copyWith({String? name, int? balanceMinor}) => Account(
        id: id,
        name: name ?? this.name,
        balanceMinor: balanceMinor ?? this.balanceMinor,
      );
}
```

- `@immutable` (from `package:meta`, re-exported by Flutter) makes a mutable field a lint error.
- `const` constructor where every field is `const`-compatible — a `const` value can be shared and a `const` widget subtree is skipped on rebuild.
- `final` fields, always. A mutable value handed to a widget is a rebuild-and-golden-test hazard.
- `copyWith` is the only way to derive a changed value. Never mutate.
- Prefer `final` locals and `const` constructors everywhere the analyzer allows (`prefer_final_locals`, `prefer_const_constructors`).

## `copyWith` and nullable fields

The `field ?? this.field` idiom cannot distinguish "leave unchanged" from "set to null" for a nullable field. When a field is nullable *and* must be clearable, use a sentinel or a wrapper rather than a bare `T?` parameter:

```dart
// A sentinel object distinguishes "omitted" from "set to null".
static const _unset = Object();

Reminder copyWith({Object? note = _unset}) => Reminder(
      id: id,
      note: identical(note, _unset) ? this.note : note as String?,
    );
```

Reach for this only on the rare nullable-and-clearable field; most `copyWith`s do not need it.

## When to hand-write `==` / `hashCode`

Add value equality only when the type is compared, deduplicated, or used as a `Map` key / `Set` member. A type that is only ever switched on or read does not need it.

```dart
@override
bool operator ==(Object other) =>
    other is Account &&
    other.id == id &&
    other.name == name &&
    other.balanceMinor == balanceMinor;

@override
int get hashCode => Object.hash(id, name, balanceMinor);
```

Rules: `==` and `hashCode` are always defined together; every field in `==` is in `hashCode` and vice versa; use `Object.hash` / `Object.hashAll` (never a hand-rolled XOR). For a collection field, compare with `package:collection`'s `const DeepCollectionEquality()` and hash with `Object.hashAll`.

## Identity vs value equality — keep them separate

**Identity is an explicit stable field; it is not the same thing as value equality.**

- A value type that represents an *entity* (something with a lifetime — a `Task`, an `Account`, an `Order`) carries a stable `final String id` (or a typed id) assigned once at creation. `ForEach`/list-diffing/selection all key off `id`.
- Deriving identity from equals-on-all-fields collapses two distinct entities that happen to share values — two `Item`s both titled "Draft", two `Account`s both at zero balance — into one. Selection jumps, list animations glitch, a set silently drops one.
- A pure *value* with no lifetime (a `Money`, a `Coord`, a `DateRange`) has no id and *is* defined by its fields — value equality is correct there.

Rule of thumb: if you would ever ask "is this the *same* one?" (not "does it have the same contents?"), it needs an `id`.

## Make illegal states unrepresentable

Prefer a type that cannot express a bad state over a type plus a guard.

```dart
// BAD — four fields, only ever one set; every reader must guess which.
class LoadState {
  final bool isLoading;
  final List<Item>? items;
  final String? errorMessage;
}

// GOOD — a sealed union: the compiler enforces exactly one case.
@immutable
sealed class LoadState {
  const LoadState();
}
final class Loading extends LoadState { const Loading(); }
final class Loaded extends LoadState {
  const Loaded(this.items);
  final List<Item> items;
}
final class LoadFailed extends LoadState {
  const LoadFailed(this.failure);
  final Failure failure; // a typed failure, not a String — see error-handling skill
}
```

No reader has to check `isLoading && items != null`; a `switch` with no `default:` forces every case to be handled and every new case to be a compile error.
