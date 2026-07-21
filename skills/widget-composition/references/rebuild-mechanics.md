# Rebuild mechanics — why a class beats a method, const, keys, select

The honest mechanism behind the composition rules. Read this when a reviewer asks "does extracting a widget actually make it faster?" — the answer is *sometimes*, and the correctness/testability wins matter more than the frame budget in most apps.

## A method has no Element; a class does

Flutter reconciles by walking `Element`s. When a parent rebuilds, each child `Element` runs `updateChild(oldWidget, newWidget)`:

- If `Widget.canUpdate(old, new)` is false (different `runtimeType` or `Key`), it rebuilds the subtree.
- If the new widget is **identical** (`identical(old, new)` — what `const` canonicalization produces) it can short-circuit and skip the subtree entirely.

A `Widget _buildHeader()` helper returns a subtree that is spliced directly into the *parent's* returned tree. It owns no `Element`, so there is no boundary at which `updateChild` can compare and prune — every parent rebuild rebuilds that subtree unconditionally. A separate `StatelessWidget` subclass gets its own `Element`; the framework can compare its widget instance against the previous one and skip.

Three wins that hold **regardless of performance**:

1. **Testable by type** — `find.byType(ProductCard)` reaches a class; it cannot reach a method's output. When the analyzer and the test suite are the whole feedback loop, an addressable unit is worth more than a micro-optimization.
2. **A subtree that *can* be `const`** — a method can never be.
3. **A grep-able, keyable name** a stranger inheriting the repo can find.

Do not extract widgets *for speed alone* in a static, animation-free screen — there is no frame to miss. Extract them for the boundary, the const-ness, the testability, and the name.

## const canonicalization

`const` expressions are canonicalized at compile time: two identical `const` widgets are literally the same object. That makes `updateChild`'s identity check true and prunes the subtree. Keep `prefer_const_constructors` and `prefer_const_constructors_in_immutables` on for two reasons even when the runtime saving is unmeasurable:

1. `dart fix --apply` writes it, so it costs nothing.
2. `const` documents "this widget has no dynamic inputs" to the next reader.

**Budget for hand-tuning const: zero minutes.** Never restructure a tree to make something const-able. Never add a `const` constructor to a class that would otherwise want a non-`final` field. If a reviewer's only finding is a missing `const`, the review found nothing — `dart fix` handles it.

## Keys — the one situation they matter

A `Key` only changes behaviour when the framework must decide whether an `Element` (and its attached `State`) can be reused for a new `Widget` at the same **position** in a child list. Without a key, position is identity: reorder a list and `Element`s stay put while their widgets swap, so a stateful child keeps `State` that belonged to a different item — a scroll offset, a half-typed field, an animation, leaking into the wrong row.

- **Give reorderable/filterable/variable-length list rows a `ValueKey(item.id)`** so identity tracks the data, not the slot. `KeyedSubtree` or a keyed builder result works the same way.
- **Fixed-order, fixed-length lists of stateless leaves need no key** — nothing reorders, nothing has `State` to leak, a key changes nothing.
- **Never `GlobalKey` for identity or cross-widget lookups.** It forces a global registry lookup, allows reparenting an `Element` across the tree, and is expensive to maintain. Legitimate uses are narrow (a `Form`/`Scaffold` state handle you genuinely cannot reach otherwise); reaching for one to read another widget's state is a design smell — lift the state to the ViewModel instead.
- **A stateless widget "wanting" a `GlobalKey`** is the signal to reconsider the design, not to add the key.

## Resolve identity, not content

The stable identity is the id/coordinate; the content behind it is not. A closure that captures a content value goes stale after an edit:

```dart
// WRONG — captures the value into the closure. A re-tap after an edit acts on stale data.
onTap: () => submit(item.currentLabel),

// RIGHT — resolve from the stable id at tap time; the Notifier reads current content.
onTap: () => onSubmit(item.id),
```

This is the same fact that makes keys unnecessary in fixed lists and closures dangerous in variable ones: position/id is stable, content is not.

## select — the leaf-const equivalent for state

`ref.watch(provider)` rebuilds the widget on any state change. `ref.watch(provider.select((s) => s.field))` rebuilds only when that derived value changes (compared with `==`), so an immutable state with value equality is a prerequisite. Use it to narrow a rebuild to exactly the field a leaf renders — the state-management equivalent of hoisting a `const` subtree. See `state-management-riverpod` and `flutter-performance` for the full watch/read/listen and rebuild-scoping treatment.

## Complexity limits are refactor prompts, not laws

`dart3-idioms-and-coding-standards` owns the numbers — its table sets `build()` ≤ 80 lines, ≤ 3 positional params, and the widget-tree exception of **build nesting ≤ 5** (deeper than the logic-nesting ≤ 3 limit, because a widget tree legitimately nests further). Treat them as prompts to extract, not hard failures. The fault curve is U-shaped — a screen shattered into forty two-line widgets is as hard to follow as one 300-line `build()`. Extract at the natural seams (a section, a reused row, a leaf with its own state), not to hit a number.
