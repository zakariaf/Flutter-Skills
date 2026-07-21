# Widget & data selection — cheapest widget, data classes, gestures

Which widget, which data class, which gesture wiring. All choices are about picking the smallest correct primitive.

## Prefer the cheapest widget

`Container` is a convenience wrapper that composes up to a dozen widgets. When you need one effect, use the single-purpose widget — it allocates less, reads clearer, and is more likely to be `const`.

| You need | Use — not `Container` |
|---|---|
| Fixed-size gap / box | `SizedBox` (`SizedBox.shrink()`, `SizedBox.square`) |
| A solid background color | `ColoredBox` |
| A border / rounded / gradient decoration | `DecoratedBox` |
| Padding only | `Padding` |
| Center a child | `Center` (or `Align`) |
| Position a child (edge/corner) | `Align` / `AlignmentDirectional` |
| Push siblings apart | `Spacer` in a `Flex`, or `Align` — not `Row` + empty `Expanded` hacks |
| Constrain size | `ConstrainedBox` / `SizedBox` |
| Clip to a shape | `ClipRRect` / `ClipRSuperellipse` / `ClipOval` |

Reach for `Container` only when you genuinely need several of its effects at once; even then, a purpose-built widget tree often reads better.

Other cheap-vs-expensive choices:
- `Text` with a `TextStyle` from `Theme.of(context).textTheme`, not a hand-built `RichText`, unless you need inline spans.
- `ListView.builder` / `SliverList` over eager `ListView(children: [...])` for anything variable or long.
- `Visibility`/`Offstage` sparingly — a widget that is usually absent should be built conditionally (`if (x) Widget()`), not always built and hidden.

## Data-class decision table

Do not hand-roll (or code-generate) a data class where an equivalent already exists. Choose by shape:

| Shape | Use | Why |
|---|---|---|
| A persisted row (`Task`, `Order`, `Item` table) | the **drift-generated row class**, directly | it already has `==`, `hashCode`, `toString`, `copyWith`; a second generator over the same class is redundant, and a row→model mapping layer is the "separate API/domain model" pattern meant for apps with a network API |
| Ephemeral multi-value return **inside one layer** | a **record** — `(int index, String label)` | zero boilerplate; but it has no name/doc and a positional shape that silently changes meaning when reordered |
| Hand-authored domain value or UI-state class | `@immutable`, `const` ctor, `final` fields; write `copyWith` only where a call site needs it | four lines beats a code generator for a simple immutable |
| A large sum type / union, or heavy `copyWith` churn | `sealed` classes, or `freezed` if the boilerplate is real | earns the generator; see `dart3-idioms-and-coding-standards` |
| A joined/derived shape no generator emits (a row that spans two tables) | hand-written `@immutable` class | drift emits one class per *table*, never per join |
| Must be a `Map`/`Set` key and isn't one of the above | manual `==` + `Object.hash(...)` | five lines; do not add `equatable` for a single `==` |

**Records never cross a layer boundary.** `(int, int)` is fine as a coordinate inside the layout layer; it is not a domain type and must not appear in a repository or Notifier signature — give crossing shapes a name.

For hand-written immutables: `@immutable`, a `const` constructor, `final` fields. Write `copyWith` by hand only when a call site actually calls it — an unused `copyWith` with an `Object? sentinel` dance is pure surface area.

## Gestures — the smallest correct wiring

- **A tap on a control that should show Material feedback** — `InkWell`/`InkResponse` inside a `Material`. The ripple is the affordance.
- **A tap on a custom surface with no ink wanted** — `GestureDetector(behavior: HitTestBehavior.opaque, onTap: ...)`. `HitTestBehavior.opaque` is load-bearing: without it only the painted child is hittable and the padding around a short label becomes dead space, so a near-miss does nothing.
- **Resolve the id at tap time**, never a captured content value (see `references/rebuild-mechanics.md`).

### Every gesture needs a visible, focusable fallback

Any behaviour reachable by touch must also be reachable by a labelled, focusable control. Non-obvious gestures fail whole classes of users:

- **Long-press** collides with dwell/switch-access input where *holding is the ordinary activation*, and it is an invisible timed state machine — nothing on screen says a press is being measured. Prefer a **visible mode toggle** (a button that changes the screen) over a hidden long-press.
- **Drag / swipe** silently repoints muscle memory: an item the user learned by position quietly moves and the wrong thing fires. Do reordering through explicit controls in an edit mode, not `Draggable`/`Dismissible`, unless the drag is *also_ reachable another way.
- **Double-tap** delays or eats the single tap — latency on a primary action is a bug.
- **Multi-touch / pinch-zoom** to resize text is wrong: text scales via the platform `TextScaler`; never intercept it and never clamp it.

If an action is reachable *only* by a gesture, it is unreachable to switch-access and screen-reader users — add the button. See `accessibility-as-code`.

## Where widget state comes from

- **App/domain/session state** → the Notifier, via `ref.watch`.
- **Platform accessibility state** (bold text, high contrast, text scale, reduce-motion) → read from `BuildContext` at build time (`MediaQuery.boldTextOf(context)`, `MediaQuery.highContrastOf(context)`, `MediaQuery.textScalerOf(context)`), **not** routed through app state. `MediaQuery` is an `InheritedWidget` with correct-by-construction invalidation; mirroring it into a provider trades a compiler-guaranteed rebuild for a manual sync that is stale for a frame. Read it, never clamp it.
- **Local ephemeral UI state** (an `AnimationController`, `TextEditingController`, `FocusNode`, a scroll offset) → `State`, disposed in `dispose()`.
