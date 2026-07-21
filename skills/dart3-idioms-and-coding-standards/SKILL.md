---
name: dart3-idioms-and-coding-standards
description: "Enforces which Dart 3 construct each declaration earns — sealed class + exhaustive switch with no `default:`/`case _:`, the three class modifiers (`sealed`/`final`/`abstract interface class`) and skip the rest, records as intra-layer tuples only, immutable value types (`final` fields, `const` ctor, value equality) hand-rolled when trivial and `freezed` when boilerplate dominates, explicit stable identity, total non-throwing domain functions, make-illegal-states-unrepresentable, and firm method/build/file/nesting complexity limits (the single-source-of-truth table other skills cite) — while banning `late`/`!`/`dynamic` honesty dodges. Use when authoring or reviewing any Dart type or declaration: class vs enum vs record vs typedef, hand-rolled vs `freezed`, adding a `switch`/`if-case`, writing `copyWith` or `==`/`hashCode`, deciding identity, keeping a domain function total, or hitting a length/nesting limit."
---

# Dart 3 idioms and coding standards

Modern Dart 3.x, value-type-first, total functions for domain logic. A language feature earns its place when it converts a runtime silence into a **compile error**; everything else is decoration. This skill governs how each declaration is *typed, named, kept immutable, and kept total* — the error-handling architecture that rides on top of these mechanics lives in `error-handling-typed-results`.

Read the reference for the task at hand:

- `references/construct-verdict-table.md` — the feature-by-feature verdict table (sealed / enum / record / class modifiers / `extension type` / codegen packages), with the rationale for each Use / Skip.
- `references/immutability-and-equality.md` — immutable value types, `copyWith`, when to hand-write `==`/`hashCode`, and stable-identity vs value-equality.
- `references/complexity-and-honesty.md` — the length/nesting limits with their evidence, and the `late`/`!`/`dynamic` honesty-dodge bans in full.

Run `scripts/check-dart3-idioms.sh` before a PR.

## Non-negotiable rules

1. **A `switch` on a sealed type or enum carries no `default:` and no `case _:`.** A wildcard makes the switch compile forever, discarding the one compile-time guarantee the type exists for — adding a variant then falls through silently at runtime. Exhaustiveness is the whole product.
2. **Reach for exactly three class modifiers; ignore the rest.** `sealed class` for a closed variant set the compiler must exhaust; `final class` for every concrete leaf; `abstract interface class` for a seam a test fake implements. Default concrete types to `final`. Skip `base`, `extension type`, primary constructors, and macros.
3. **Model closed sets of *individually actionable* cases as a `sealed` hierarchy, payload-free closed sets as an `enum`.** Start with `enum`; convert to `sealed` + `final class` the moment any member needs a field. Never bolt nullable fields onto an enum for data that applies to only some members — that turns every access into a null-check the compiler cannot reason about.
4. **Records never cross a layer boundary.** A record is a nameless, positional, undocumented shape — fine for an ephemeral multi-value return *inside one layer*. The moment a shape is returned from a repository, stored, or passed to a widget constructor, it is a named class.
5. **Domain values are immutable: `final` fields, a `const` constructor where legal, value equality, and `copyWith` to derive.** Mutating a value handed to a widget is a rebuild-and-golden-test killer. Prefer `final` locals and `const` constructors everywhere the analyzer allows.
6. **Identity is an explicit stable field, never equals-on-all-fields.** A value type used in a list or as a map key carries `final String id` (or a typed id). Deriving identity from all fields collapses two distinct entities that happen to share values (two `Item`s both named "Draft") into one.
7. **Make illegal states unrepresentable.** Encode a discriminated choice as a sealed variant or an enum-keyed union, not as a bag of nullable fields where only one is ever set. If the type cannot express the bad state, no branch has to guard against it.
8. **Domain functions are total — they never throw.** Every pure function returns a value for every input; uncertainty is an explicit output (a clamped value, a "no result within N steps" outcome, a low-confidence flag). Programmer invariants use `assert` (stripped in release), never `throw`. Recoverable I/O failures return a typed result — see `error-handling-typed-results`.
9. **No honesty dodges: no `late` to dodge nullability, no `!` on a value that matters, no `dynamic`/`Map<String, dynamic>` as an ad-hoc model.** Each hides a runtime failure the type system would otherwise force you to handle. Use `?.`/`??`/promotion for null, and a typed model for structured data.
10. **Effective Dart casing, verbatim; constants are `lowerCamelCase`.** `UpperCamelCase` types/extensions/enums; `lowercase_with_underscores` files/dirs/import prefixes; `lowerCamelCase` vars/params/methods/**constants** (`maxItems`, never `MAX_ITEMS`); acronyms over two letters capitalize as a word (`JsonMap`, `HttpClient`, not `JSONMap`). File name = its primary declaration.
11. **Respect the complexity limits as firm defaults — this table is the library's single source of truth; other skills cite it, they do not restate numbers:** method ≤ ~30 lines, `build()` ≤ ~80, file ≤ ~300, class public API ≤ ~10 members, positional params ≤ 3, **logic nesting ≤ 3**. Widget build trees legitimately nest deeper — **widget build nesting ≤ 5** is the one explicit exception (referenced by `widget-composition`). Refactor prompts, not laws — a cohesive overrun (a single state machine scattered across five fragments is worse) is justified in the PR.
12. **Prefer immutable value types; hand-roll trivial ones, reach for `freezed` when the boilerplate dominates.** For a trivial immutable (1–3 fields) hand-write `@immutable` + `const` ctor + `final` fields (+ manual `==` / `Object.hash` when a map key). For a domain or UI-state value type where `copyWith`/`==`/`hashCode`/sealed-union boilerplate gets tedious, `freezed` is allowed and is the default — `*.freezed.dart` is a first-class generated artifact. Skip `equatable` (five lines of `==` + `Object.hash` cover it), `fpdart`/`dartz` (an `Either` erases exhaustiveness), and any `--enable-experiment` flag (an abandoned repo stops building the day the flag is dropped).

## Sealed classes: the load-bearing idiom

Model a closed set of individually actionable cases as one sealed hierarchy in one file. `sealed` requires every subtype to live in the same library — the file **is** the closed set and the compiler enforces it.

```dart
@immutable
sealed class SyncOutcome {
  const SyncOutcome();
}

final class SyncApplied extends SyncOutcome {
  const SyncApplied(this.appliedCount);
  final int appliedCount;
}

final class SyncSkipped extends SyncOutcome {
  const SyncSkipped(this.reason);
  final String reason;
}
```

Switch with **no** `default:` — adding a variant is then a compile error until every site handles it:

```dart
// RIGHT — exhaustive, no wildcard.
switch (outcome) {
  case SyncApplied(:final appliedCount):
    log.info('applied $appliedCount');
  case SyncSkipped(:final reason):
    log.warning('skipped: $reason');
}
```

A dropped branch reports as `non_exhaustive_switch_statement` from `dart analyze` **and** fails `dart compile`. Never suppress it; a suppressed analyzer diagnostic still fails the AOT build, so CI must build, not merely analyze.

## Class modifiers: reach for three

| Intent | Declaration |
|---|---|
| A closed set of variants the compiler must exhaust | `sealed class` (implicitly abstract; not constructible or implementable outside its library) |
| A concrete leaf — a variant, a service impl, a value type | `final class` |
| A seam a test fake must satisfy | `abstract interface class` |

Default every concrete type to `final class`: it blocks both extension and implementation, so no subclass silently inherits half a behaviour and no test accidentally `implements` a concrete class to pick up its fields. `abstract interface class` says "implement me, don't extend me" — exactly the contract a fake wants; a bare `abstract class` permits `extends`, and an inherited default on a service interface is how a fake ends up quietly calling the real implementation. Skip `base` (it polices a library-boundary invariant a single-package app does not have) and `extension type` (an explicitly *unsafe* abstraction — the representation stays reachable).

## Records: where they win, where they cost

Use a record for an ephemeral multi-value return **inside a single layer**: `(int row, int col)` as a local coordinate is ideal — structural equality free, no class, no codegen. Name the fields once a record survives more than a few lines: `({int row, int col})` reads at the use site; `(int, int)` is a swap bug the compiler cannot see.

```dart
// Intra-layer only. Two same-typed positional fields = a latent swap bug.
({int page, int size}) nextPage(({int page, int size}) current) =>
    (page: current.page + 1, size: current.size);
```

Do not `typedef` a record shape into existence to dodge the class decision — a named shape used across files wants a class.

## Enum or sealed

Start with an `enum` when the set is closed and every member is payload-free — a display category, a mode. Enums get the same compiler exhaustiveness in a switch and cost one line each. Convert to `sealed` + `final class` the moment any member needs a field.

```dart
enum OrderStatus { draft, submitted, shipped, cancelled }

// A member needs data -> sealed, not an enum with parallel nullable fields.
@immutable
sealed class Payment {
  const Payment();
}
final class Cash extends Payment { const Cash(); }
final class Card extends Payment {
  const Card(this.last4);
  final String last4;
}
```

## Switch expressions and if-case

Prefer a switch **expression** when every arm produces a value and no arm has a statement body — exhaustive by construction, cannot fall through:

```dart
final label = switch (status) {
  OrderStatus.draft => 'Draft',
  OrderStatus.submitted => 'Submitted',
  OrderStatus.shipped => 'Shipped',
  OrderStatus.cancelled => 'Cancelled',
};
```

Use a switch **statement** when arms perform effects; do not contort effects into an expression with a `void` sink. Use `if (x case Pattern)` for a single interesting shape where a switch would be one real branch plus a dead one — but **never** `if-case` on a sealed type, which silently reintroduces the non-exhaustive hole a switch would have caught.

```dart
if (settings.retry case final RetryPolicy p when p.isEnabled) {
  await scheduler.arm(p);
}
```

## Immutable value types and identity

Four lines replace a code generator. Hand-write `==`/`hashCode` only when the type is a map key or set member; carry a stable `id` for identity in lists.

```dart
@immutable
final class Task {
  const Task({required this.id, required this.title, required this.done});

  final String id; // identity — NOT derived from title/done
  final String title;
  final bool done;

  Task copyWith({String? title, bool? done}) =>
      Task(id: id, title: title ?? this.title, done: done ?? this.done);

  @override
  bool operator ==(Object other) =>
      other is Task && other.id == id && other.title == title && other.done == done;

  @override
  int get hashCode => Object.hash(id, title, done);
}
```

## Total domain functions

A pure function returns for every input. Uncertainty is a value; a programmer invariant is an `assert`.

```dart
/// Total: clamps rather than throwing on an out-of-range page.
int clampPage(int requested, int pageCount) {
  assert(pageCount >= 1, 'pageCount must be positive'); // programmer invariant
  if (requested < 0) return 0;
  if (requested >= pageCount) return pageCount - 1;
  return requested;
}
```

## Anti-patterns

- `default:` or `case _:` on a sealed type or enum — discards exhaustiveness; a new variant falls through at runtime instead of failing to compile.
- `if (x case SomeVariant())` on a sealed type — reintroduces the non-exhaustive hole a `switch` catches.
- An `enum` with a constructor and nullable fields that apply to only some members — every access is a null-check the compiler cannot reason about; use `sealed` + `final class`.
- A record returned from a repository, stored, or passed across a widget constructor — a nameless positional shape as a domain type; make a class.
- `class Order extends ChangeNotifier` used as a mutable domain model — domain values are immutable; mutate through a ViewModel (see `state-management-riverpod`).
- Identity derived from `==`-on-all-fields — two entities sharing values collapse into one; carry a stable `id`.
- `late Foo foo;` / `foo!.value` to dodge a null, `Map<String, dynamic>` as a model — hides a runtime failure; use `?.`/`??`/promotion and a typed model.
- `throw` from a pure domain function to signal a normal outcome — return the outcome; `assert` for programmer invariants only.
- `const MAX_ITEMS` / `class JSONModel` / `final s = 3;` — SCREAMING_CAPS, mis-cased acronym, abbreviation; use `maxItems`, `JsonModel`, full words.
- `Widget _buildHeader() => ...` — rebuilds with its parent, can't be `const`; extract a `const` widget class (see `widget-composition`).
- Adding `equatable`/`fpdart`/`dartz` or an `--enable-experiment` flag — redundant weight or an exhaustiveness-erasing `Either`; hand-roll the four lines, or reach for `freezed` when the boilerplate genuinely dominates.

## Definition of done

- [ ] Every `switch` on a sealed type or enum is exhaustive with no `default:`/`case _:`.
- [ ] Concrete types are `final class`; seams are `abstract interface class`; closed sets are `sealed`/`enum`; no `base`/`extension type`/experiment flags.
- [ ] Closed actionable sets are `sealed` + `final class`; payload-free sets are `enum`; no nullable-field-tagged enums.
- [ ] Records stay intra-layer; every cross-boundary shape is a named class.
- [ ] Domain values are immutable (`final` fields, `const` ctor where legal, `copyWith`); identity is a stable `id`, not equals-on-all-fields.
- [ ] Illegal states are unrepresentable (sealed/enum unions, not nullable bags).
- [ ] Domain functions are total — return uncertainty, never throw; invariants use `assert`.
- [ ] No `late`/`!`/`dynamic`/`Map<String,dynamic>` honesty dodge on a value that matters.
- [ ] Effective Dart casing verbatim; constants `lowerCamelCase`; file = its primary declaration.
- [ ] Complexity limits respected or a cohesive overrun justified in the PR.
- [ ] `scripts/check-dart3-idioms.sh` passes; `dart analyze` clean.

## Related skills

- `error-handling-typed-results` — the Result/Failure spine and global error net that ride on these sealed-type mechanics.
- `naming-conventions` — the role-suffix naming (Screen/Notifier/Repository/Service/Failure) that names the layer.
- `state-management-riverpod` — where mutable state lives (Notifier ViewModels over immutable state); domain values here stay immutable.
- `widget-composition` — extract `const` widget classes, not `_buildX()` methods.
- `dart3-idioms-and-coding-standards` is enforced in CI by `lint-and-style-config` and `ci-pipeline-and-gates`.

## References

- Dart team. *Effective Dart* (Style / Documentation / Usage / Design). https://dart.dev/effective-dart
- Dart team. *Class modifiers.* https://dart.dev/language/class-modifiers
- Dart team. *Patterns & pattern types* (destructuring, `if-case`). https://dart.dev/language/patterns
- Dart team. *Branches — exhaustiveness.* https://dart.dev/language/branches#exhaustiveness-checking
- Dart team. *Records.* https://dart.dev/language/records
- Dart team. *Sound null safety.* https://dart.dev/null-safety
