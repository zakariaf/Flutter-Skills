---
name: widget-composition
description: Enforces Flutter widget composition — extract named const Widget classes never `Widget _buildX()` methods, lean build() (no I/O/formatting/domain math, precompute in the ViewModel), dumb Views that watch one Notifier and route intents via ref.read, StatelessWidget by default with every controller disposed, lazy `.builder` lists, cheapest-widget choices (SizedBox/ColoredBox/Align over Container), a strict key policy (ValueKey for reorderable lists, never GlobalKey), gesture→visible-focusable-fallback wiring, plus structural layout — full-bleed background vs SafeArea content, computed cell sizing, the GridView cross/main-axis spacing trap, EdgeInsetsDirectional, and resizeToAvoidBottomInset/IME handling. Use when building or refactoring any screen or widget, splitting a large build() into components, writing GridView/ListView/LayoutBuilder/SafeArea/Scaffold, wiring onTap/onLongPress/Draggable, choosing a key or data class, or reviewing widget code in a diff.
---

# Widget Composition

Build every screen from many small, `const`, single-purpose widget **classes**. A widget that does one thing rebuilds cheaply, reads clearly, tests in isolation, and can be lifted into a shared component library. The View is *dumb*: it watches one ViewModel and renders; logic lives in the Notifier, state in immutable value objects, layout in directional structural primitives. Applies to any screen, list, card, or shared component.

Read the reference for the task at hand:
- `references/rebuild-mechanics.md` — why a class beats a method (`Element.updateChild`), `const` canonicalization, the full key policy, and `.select` for narrowed rebuilds.
- `references/structural-layout.md` — edge-to-edge background vs `SafeArea` content, computed cell sizing, the `GridView` cross/main-axis trap, directional insets, and IME/`resizeToAvoidBottomInset`.
- `references/widget-and-data-selection.md` — cheapest-widget table, data-class decision table (drift row vs record vs hand-written vs freezed), and gesture→fallback rules.

Run `scripts/check-widget-composition.sh` before a PR.

## Non-negotiable rules

1. **Extract a `Widget` class, never a `Widget`-returning method.** `Widget _buildHeader()` is *not* a widget — its subtree has no `Element` of its own, so `Element.updateChild` never gets to compare old vs. new and short-circuit; it rebuilds with the parent, cannot be `const`, cannot take a `Key`, and `find.byType` cannot reach it in a test.
2. **`const` everywhere it is legal, every field `final`.** `const` constructors canonicalize identical widgets to the same object, letting Flutter prune the subtree rebuild. Turn on `prefer_const_constructors` + `prefer_const_constructors_in_immutables`. Budget zero minutes hand-tuning const — let `dart fix --apply` write it; never restructure a tree to make something const-able.
3. **Keep `build()` small and shallow.** Past the complexity limits owned by `dart3-idioms-and-coding-standards` (`build()` ≤ 80 lines; **widget build nesting ≤ 5** — the deeper-nesting exception that table states for widget trees vs. logic ≤ 3), extract child widget classes. A `build()` you must scroll to read is too big.
4. **One responsibility per widget.** A component renders one thing; it does not also fetch data, format values, read a clock, hold app state, or schedule side effects.
5. **No I/O, formatting, or domain math in `build()`.** `build()` can run 60×/second — no repository/DAO call, no `DateTime.now()`, no `NumberFormat`, no sorting. The Notifier precomputes a ready-to-render UI-state value; the widget only paints it.
6. **The View is dumb and watches exactly one ViewModel.** A `ConsumerWidget` does `ref.watch(oneNotifierProvider)` and renders; intents go back via `ref.read(...notifier)`. It never reaches a repository or DAO directly and never mutates persisted state.
7. **`StatelessWidget`/`ConsumerWidget` by default.** Use `StatefulWidget`/`ConsumerStatefulWidget` only for genuinely local, ephemeral UI state (`AnimationController`, `TextEditingController`, `ScrollController`, `FocusNode`). App/domain/session state lives in the Notifier.
8. **Always `dispose()` controllers created in `State`.** Leaked `AnimationController`/`TextEditingController`/`ScrollController`/`FocusNode`/subscriptions retain memory and fire after teardown. `cancel_subscriptions`/`close_sinks` are errors.
9. **Lists are lazy.** Use `ListView.builder`/`SliverList` for variable/long lists. Never `ListView(children: items.map(...).toList())` for unbounded data — it builds every row eagerly.
10. **Resolve identity, not content, in callbacks.** A tap closure captures the stable id (`onTap: () => onSelect(item.id)`), never a captured content value — a re-tap after an edit must not act on a stale capture.
11. **Every gesture needs a visible, focusable fallback.** Any behaviour reachable by touch must also be reachable by a labelled focusable control. A drag-only or long-press-only action is unreachable to switch-access and screen-reader users.
12. **Style from theme/tokens and logical directions.** Colors/text styles come from `Theme.of(context)` or a `ThemeExtension`, never literal hex. Use `EdgeInsetsDirectional`/`AlignmentDirectional` (`start`/`end`), never hardcoded left/right, so RTL mirrors by construction.

## Extract a widget vs. a method

```dart
// WRONG — helper method: rebuilds with parent, no const, no key, no isolation, untestable
Widget _buildProductCard(Product product) {
  return Card(child: Text(product.name));
}

// RIGHT — widget class: const-constructible, keyable, independently rebuildable, testable
class ProductCard extends StatelessWidget {
  const ProductCard({required this.name, required this.price, this.onTap, super.key});

  final String name;          // already-localized; the feature mapped Product -> name
  final String price;         // already-formatted; no currency math here
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context); // read theme in the leaf that uses it
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsetsDirectional.all(12), // logical, RTL-safe
          child: Row(
            children: [
              Expanded(child: Text(name, style: theme.textTheme.titleMedium)),
              Text(price, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
```

## Keep build() lean — the Notifier precomputes

```dart
// WRONG — domain math + formatting inside build()
@override
Widget build(BuildContext context, WidgetRef ref) {
  final order = ref.read(orderRepositoryProvider).find(id); // repo call in build!
  final remaining = order.total - order.paid;               // domain math in UI
  final label = NumberFormat.currency().format(remaining);  // formatting in UI
  return Text(remaining <= 0 ? 'Done' : label);
}

// RIGHT — the Notifier exposes ready-to-render UI state; select narrows the rebuild
@override
Widget build(BuildContext context, WidgetRef ref) {
  final status = ref.watch(orderNotifierProvider(id).select((s) => s.balanceStatus));
  return Text(status.label, style: status.isSettled ? _settledStyle : _dueStyle);
}
```

`ref.watch(p.select((s) => s.field))` rebuilds only when that field changes — the Riverpod equivalent of a leaf `const`. See `state-management-riverpod` for the watch/read/listen split and `flutter-performance` for `.select` and const-subtree scoping.

## Composition guidance

- **Split a screen into sections** (header, body, footer) as separate widget classes; split a row into its parts when a part is reused or complex.
- **Pass data down, callbacks up.** A component receives what it shows and exposes `onX` callbacks; it never reaches into a parent or a provider it does not own.
- **Read `MediaQuery`/`Theme` in the leaf that needs it**, not at the top of a big `build()` — reading at the top rebuilds the whole subtree on every metrics change.
- **Prefer the cheapest widget:** `SizedBox` over `Container` for spacing; `ColoredBox`/`DecoratedBox` over `Container` for a single effect; `Align`/`Center` over `Row`+`Spacer`. See `references/widget-and-data-selection.md`.
- **Hoist unchanging subtrees into `const` locals** so they survive rebuilds.
- **A shared component is domain-blind and provider-free.** It takes primitives, localized labels, immutable view-data, and callbacks through its constructor — never a domain entity, a repository, or a `ref`. The dependency arrow is one-way: features import the shared library, never the reverse.

## Keys

Keys matter in exactly one situation: the framework must decide whether an `Element` (and its `State`) can be reused for a new `Widget` at the same position in a child list. The classic bug is stale `State` bleeding into a reused slot after a list reorders.

| Situation | Key |
|---|---|
| A row in a reorderable / filterable / variable list | `ValueKey(item.id)` — stable identity survives the move |
| A fixed-order, fixed-length list; leaf stateless widgets | none — a key changes nothing |
| Swapping two widgets of the same type and needing to preserve state | a `ValueKey` distinguishing them |
| A widget that suddenly "wants" a `GlobalKey` | **stop** — that is a design smell, not a fix |

Never add `GlobalKey` for identity or lookups — it forces a global registry lookup and enables cross-tree reparenting, machinery most apps do not need. Full mechanism in `references/rebuild-mechanics.md`.

## Data classes for view-data

Do not hand-roll a data class where a generator already emits one. The decision rule:

| Shape | Use |
|---|---|
| Persisted row | the drift-generated row class directly — it has `==`, `hashCode`, `copyWith` already |
| Ephemeral multi-return inside one layer | a **record** — `(int row, int col)`; never crosses a layer boundary |
| Hand-authored domain value / UI-state | `@immutable`+`const`+`final` for a trivial value; `freezed` for non-trivial value types, unions, or `copyWith` churn — `dart3-idioms-and-coding-standards` owns the threshold |
| A joined shape no generator emits | hand-written `@immutable` class |

Do not add `equatable` for one `==`; `Object.hash(...)` is five lines. Full table and rationale in `references/widget-and-data-selection.md`. See `dart3-idioms-and-coding-standards` for value-type and record rules.

## Structural layout

The window is edge-to-edge; the *targets* are inset — never the same question. Paint the background full-bleed behind the system bars, then wrap the interactive content in `SafeArea` and add margins inside it.

```dart
Scaffold(
  backgroundColor: Theme.of(context).colorScheme.surface, // full-bleed, behind bars
  resizeToAvoidBottomInset: false, // a fixed grid must not reflow under the IME
  body: SafeArea(
    child: Padding(
      padding: const EdgeInsetsDirectional.all(16), // logical inset, RTL-safe
      child: child,
    ),
  ),
)
```

Compute cell size from the viewport; never hardcode a tile dimension and never assert a minimum one (a size floor fires exactly where large text needs the room most — the real constraint is that the label *fits*). The `GridView` axis trap is silent: in a vertical grid, `crossAxisSpacing` is the **column** gap and `mainAxisSpacing` is the **row** gap.

```dart
GridView.builder(
  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 3,
    crossAxisSpacing: 12, // COLUMN gap in a vertical grid
    mainAxisSpacing: 16,  // ROW gap
  ),
  itemCount: items.length,
  itemBuilder: (context, i) => ProductCard(name: items[i].name, price: items[i].price),
);
```

Full treatment — computed sizing math, IME behaviour, `MediaQuery.viewInsets`, and when to use a `Column`+grid instead of a spanning cell — in `references/structural-layout.md`. See `accessibility-as-code` for reading a11y state from `MediaQuery` and never clamping `textScaler`, and `design-system-structure` for token/theme structure.

## Anti-patterns

- **`Widget _buildXxx()` helper methods** for any non-trivial UI — no `Element` boundary, no const, no key, untestable. Make a class.
- **God-widget**: a 300-line `build()` with the whole screen inline.
- **Repository/DAO/`SharedPreferences` call in `build()` or `initState()`** — route through the Notifier and a single write path.
- **`DateTime.now()` in a widget** — a widget never reads a wall clock; the Notifier precomputes time-derived values from `Clock` injected via `clockProvider` (see `state-management-riverpod`).
- **Creating controllers in `build()`** (recreated every frame) instead of in `State` + `dispose()`.
- **`setState()` to refresh app/session data** that belongs in a Notifier — `setState` is only for local ephemeral UI.
- **`ListView(children: hugeList.map(...).toList())`** — builds every row eagerly. Use `.builder`.
- **`Container` for everything** (over-wrapping) — use the specific, cheaper widget.
- **`GlobalKey`/`ObjectKey` for identity** — delete; use `ValueKey(id)` where a list reorders.
- **Hardcoded hex / left-right padding / literal user strings** — use theme tokens, `EdgeInsetsDirectional`, and ARB localization.
- **A gesture with no visible fallback**, or clamping `textScaler` to force a layout to fit — fix the layout, not the scale.
- **A shared-library widget importing a domain type or reading a provider** — it can no longer be reasoned about or tested in isolation.

## Definition of done

- [ ] Every reusable/non-trivial subtree is a `Widget` **class** (not a `_buildX()` method); `const` where legal; all fields `final`.
- [ ] `build()` ≤ ~80 lines; nesting shallow; complex parts extracted.
- [ ] No I/O, repository call, `DateTime.now()`, formatting, or domain math in `build()` — the Notifier precomputes UI state.
- [ ] The View is a `ConsumerWidget` watching one Notifier; intents routed via `ref.read(...notifier)`; nothing mutates persisted state in the widget.
- [ ] `StatefulWidget` only for local ephemeral state; every created controller `dispose()`d.
- [ ] Long/variable lists use `.builder`; reorderable lists carry `ValueKey(id)`; no `GlobalKey` for identity.
- [ ] Callbacks resolve a stable id, not a captured content value.
- [ ] Any shared widget takes primitives/callbacks only, imports no domain type and no provider.
- [ ] Background full-bleed, content in `SafeArea`; directional insets; `GridView` spacing axes correct; no hardcoded/floored cell size.
- [ ] Styling from theme/tokens; every gesture has a visible focusable fallback; `textScaler` never clamped.
- [ ] `dart format` clean; `dart analyze --fatal-infos` clean; `scripts/check-widget-composition.sh` passes.

## Related skills

- `flutter-architecture` — the layer DAG and the dumb-View contract this widget sits inside; widget-composition is the deep dive on building those Views.
- `flutter-performance` — const subtrees, `.select` rebuild scoping, `RepaintBoundary`, dispose discipline, measuring in profile mode.
- `state-management-riverpod` — the one-Notifier-per-feature ViewModel this View watches, and the watch/read/listen split.
- `design-system-structure` — how tokens/theme/components are structured and consumed (the source of the styles this skill reads).
- `accessibility-as-code` — reading a11y state from `MediaQuery`, `Semantics` roles/labels, sort keys, never clamping `textScaler`.
- `i18n-rtl-l10n` — owns the directional-geometry (`EdgeInsetsDirectional`/`AlignmentDirectional`) and ARB-localization rules the strings and insets these widgets render must follow.
- `dart3-idioms-and-coding-standards` — the complexity-limit table these rules cite; which construct each data class earns; records intra-layer only; immutable value types.
- `adaptive-layout` — responsive breakpoints, tablet/foldable master-detail, and NavigationRail-vs-BottomNav by width (the responsiveness layer around these structural primitives).
- `forms-and-input` — `Form`/`TextFormField` validation, focus traversal, and keyboard-action wiring for the input fields these screens compose.
- `widget-golden-and-a11y-testing` — pumping an extracted widget class and asserting layout/overflow/golden across device and scale.
- `custom-canvas-and-gestures` — the one exception where pixels live on a `CustomPainter` instead of a widget tree.

## References

- Flutter — [Performance best practices](https://docs.flutter.dev/perf/best-practices) (const constructors, minimize rebuilds, lazy builders)
- Flutter — [UI layer case study / dumb views](https://docs.flutter.dev/app-architecture/case-study/ui-layer)
- Flutter API — [`StatelessWidget`](https://api.flutter.dev/flutter/widgets/StatelessWidget-class.html) · [`ListView.builder`](https://api.flutter.dev/flutter/widgets/ListView/ListView.builder.html) · [`EdgeInsetsDirectional`](https://api.flutter.dev/flutter/painting/EdgeInsetsDirectional-class.html) · [`SafeArea`](https://api.flutter.dev/flutter/widgets/SafeArea-class.html)
- Riverpod — [Reading a provider / `ConsumerWidget`, `select`](https://riverpod.dev/docs/concepts/reading)
- Dart — [Effective Dart: Style](https://dart.dev/effective-dart/style) · [Linter rules](https://dart.dev/tools/linter-rules)
