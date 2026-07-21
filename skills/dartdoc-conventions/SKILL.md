---
name: dartdoc-conventions
description: Enforces Effective-Dart documentation on the public surface — a `///` doc on every public class/method/getter/field/typedef, a one-sentence standalone summary that says WHY plus units/ranges/nullability/throws/side-effects (never a restatement of the name), verb-phrase method docs, "Whether…" boolean getters, `[bracket]` cross-links, one `library;` doc per exported barrel, in-body `//` that explains why not what, and the enforced invariant restated at its enforcement point — backed by `public_member_api_docs` and `dangling_library_doc_comments` as analyzer errors. Use when adding or reviewing a public API, a Notifier/provider, a Service interface, a sealed Failure, a value type, or preparing a package's dartdoc.
---

# Dartdoc Conventions — the public surface is a contract

Public code is read far more than it is written. A symbol with no leading `_` is a **contract** callers depend on, so it carries a `///` doc a reader understands without opening the body. Doc comments use `///` and follow *Effective Dart: Documentation*. Applies whenever you add or change a public declaration, or write an in-body `//` comment.

## Non-negotiable rules

1. **Every public declaration gets a `///` doc** — public classes, constructors, methods, getters, top-level functions, typedefs, and fields. `public_member_api_docs` is an **error** with no "obvious member" exemption: it flags *every* undocumented public member, so a missing doc fails the build. Making a symbol public "just in case" is a review reject — make it `_`-private instead so it needs no doc and no contract.
2. **`///`, never `/** */`.** Dartdoc only recognizes `///`. A JavaDoc block is silently ignored and the symbol reads as undocumented. `slash_for_doc_comments` flags it.
3. **First line is one standalone sentence ending in a period, in its own paragraph.** Tools show only this sentence in API lists, so it must stand alone; a blank `///` line separates it from the body.
4. **Method/function docs start with a verb phrase** (third person): "Returns…", "Schedules…", "Loads…", "Marks…". A boolean getter or `bool`-returning method starts with "Whether…".
5. **Never restate the name.** `/// The name.` on `String name`, `/// Returns the total.` on `total()` — banned. If a public member has nothing to add beyond its name, that is the signal to make it `_`-private (a private member needs no doc, so the tension disappears). A member that must stay public still needs a real `///` — never leave it public-and-undocumented; add meaning: **units, ranges, nullability, throws, side effects**, and the invariant the symbol enforces.
6. **Cross-link identifiers in `[brackets]`** so dartdoc resolves them: `/// Throws [StateError] if [id] is unknown; see [copyWith].` `comment_references` warns on a broken link.
7. **In-body `//` explains *why*, never *what*.** The code already says what. Narrating comments (`// loop over items`) rot out of sync and become misinformation. Comment the reason, the gotcha, or the invariant.
8. **Restate an enforced invariant at its enforcement point.** Where one line upholds a guarantee — an ordering, a clamp, a persist-before-publish, a canonical-unit conversion — a terse `//` states it so a diff that weakens it gets an unmissable flag. Same for a magic constant: cite where the number comes from.
9. **Docs change in the same diff as the code.** A wrong doc is worse than none. Every comment your change touches must still be true — put it on the PR checklist.
10. **One library doc per exported barrel.** The public entry point (e.g. `my_package.dart`) gets a `///` library doc above the `library;` directive. `dangling_library_doc_comments` is an **error** — a leading `///` with no attached declaration must be a real library doc, not an orphan above a blank line or an `export`.

## Documenting a value type

```dart
/// A note the user has authored and can later edit or archive.
///
/// Immutable; derive changes with [copyWith]. [updatedAt] is UTC and never
/// precedes [createdAt].
class Note {
  /// Creates a note; [updatedAt] must not precede [createdAt].
  const Note({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Stable unique identifier, assigned once at creation.
  final String id;

  /// Human-readable heading shown in lists; may be empty, never null.
  final String title;

  /// Creation instant, in **UTC**.
  final DateTime createdAt;

  /// Last-edit instant, in **UTC**; equals [createdAt] until first edited.
  final DateTime updatedAt;

  /// Returns a copy with the given fields replaced.
  Note copyWith({String? title, DateTime? updatedAt}) => Note(
        id: id,
        title: title ?? this.title,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
```

Every public field carries a `///`, including `title` — under the enforced `public_member_api_docs` a field that "restates the name" is not a licence to drop the doc but a prompt to say something real (or make the field `_`-private). Document units and constraints explicitly where the type does not carry them: minor currency units, a `0`–`23` hour, an inclusive/exclusive range, what `null` means, "must be `> 0`".

## Documenting behavior — throws, async, side effects

```dart
/// Schedules a reminder for [task] at [when].
///
/// [when] must be in the future; a past instant is clamped to now. Persists the
/// scheduled row before arming the OS notification, so a crash mid-call cannot
/// leave a notification the store never recorded.
///
/// Throws [PermissionDeniedException] if the OS denied notification permission.
Future<void> scheduleReminder(Task task, DateTime when) async {
  // persist-before-arm: the store is the source of truth, the OS mirrors it
  await _store.saveScheduled(task.id, when);
  await _plugin.schedule(task.id, when);
}
```

State async behavior, what a method writes or mutates, and every exception it can throw. If a function is **total** (returns for every input, never throws), say so — it is a real guarantee callers rely on.

## Library docs and the exported barrel

```dart
/// Pure-Dart domain core: value types, typed failures, and total functions.
///
/// No Flutter, Riverpod, or `dart:io` import — this purity is what lets the
/// core be unit-tested without a widget harness and reused across platforms.
library;

export 'src/note.dart';
export 'src/task.dart';
```

The `///` attaches to the `library;` directive. Never leave a `///` dangling above an `export` or a blank line.

## Restating the invariant at the enforcement point

Where a symbol *enforces* a rule, document the rule as part of its contract and pin it in-body at the one line that upholds it:

```dart
/// Failure modes of a checkout. Switched exhaustively by the caller, so a new
/// case is a compile error at every call site.
sealed class CheckoutFailure {
  /// Const base constructor, so subclasses can be `const`.
  const CheckoutFailure();
}

/// The account balance was below the order total; no charge was made.
final class InsufficientFunds extends CheckoutFailure {
  /// Creates an [InsufficientFunds] failure.
  const InsufficientFunds();
}

/// Read-only view of the current order; mutated only through this notifier.
class OrderNotifier extends Notifier<Order> {
  @override
  Order build() => Order.empty();

  /// Adds [item] and recomputes the total.
  ///
  /// Persists via the repository before emitting, so a mid-write crash cannot
  /// surface a line the store never saw.
  Future<void> addItem(Item item) async {
    // persist-before-emit: emitted state is always a state the store holds
    await _repository.append(item);
    state = state.withItem(item);
  }
}
```

## Anti-patterns

- **`/** JavaDoc-style */`** — dartdoc ignores it; the symbol reads as undocumented and fails `public_member_api_docs`.
- **Restating the name** — `/// Gets the id.` on `String get id`. Delete it or add units/ranges/invariants.
- **A paragraph before the one-sentence summary** — the first sentence must stand alone in list views.
- **Narrating mechanics in-body** — `// loop over items`, `i++ // increment`. Explain *why*, or delete.
- **A magic constant with no source** — a bare `3` for a cap with no comment saying where the number is defined.
- **Stale docs** describing pre-refactor parameters, or an invariant comment left on code that no longer honors it.
- **Commented-out code** "just in case" — git remembers. **`// TODO` with no owner or issue link** — write `// TODO(name): reason` or nothing.
- **Documenting private trivia** while a public method sits undocumented.
- **A dangling `///`** above a blank line or an `export` — fails `dangling_library_doc_comments`.
- **Banner / ASCII-art comment dividers** that bloat files; rely on structure and naming.

## Definition of done

- [ ] Every public declaration in the touched code has a `///` doc; first line is a standalone sentence ending in a period.
- [ ] Method/function docs start with a verb; boolean getters start with "Whether".
- [ ] Units, ranges, nullability, throws/`Result`, and side effects documented where they exist.
- [ ] Identifiers cross-linked with `[brackets]`; no broken `comment_references`.
- [ ] Enforced invariants restated at their enforcement points; magic constants cite their source.
- [ ] No restated-name docs, no narrating `//`, no commented-out code, no ownerless TODO, no JavaDoc blocks.
- [ ] Each exported barrel has a `library;` doc; no dangling doc comments.
- [ ] Every comment the diff touched is still true.
- [ ] `dart analyze --fatal-infos --fatal-warnings` clean; `dart doc` generates without warnings for packages.

## Related skills

- See `lint-and-style-config` for wiring `public_member_api_docs`, `dangling_library_doc_comments`, and `comment_references` as analyzer errors.
- See `naming-conventions` for the role-suffix names (`Notifier`/`Repository`/`Service`/`Failure`) these docs describe.
- See `dart3-idioms-and-coding-standards` for the sealed-type and total-function guarantees the docs promise.
- See `error-handling-typed-results` for the `Result`/`Failure` contract a method doc must state.

## References

- [Effective Dart: Documentation](https://dart.dev/effective-dart/documentation)
- [`dart doc` tool](https://dart.dev/tools/dart-doc)
- [Linter rules](https://dart.dev/tools/linter-rules) — `public_member_api_docs`, `dangling_library_doc_comments`, `comment_references`, `slash_for_doc_comments`
- [Developing packages & plugins](https://docs.flutter.dev/packages-and-plugins/developing-packages)
