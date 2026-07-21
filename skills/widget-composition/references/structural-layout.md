# Structural layout — background vs content, computed sizing, grids, IME

Structural, token-agnostic layout rules. This file prescribes *how* space is organized, never specific spacing values, radii, elevations, or colors — those belong to `design-system-structure`.

## The window is edge-to-edge; the targets are inset

These are two independent decisions, and conflating them is the common bug. On modern Android (SDK 35+) the window is edge-to-edge and apps cannot opt out; iOS has always drawn under the notch/home indicator. So:

- **Paint the background full-bleed, behind the system bars.** Set `Scaffold.backgroundColor` (or a bottom-most `ColoredBox`/`DecoratedBox`) with **no `SafeArea` above it**. A background that stops at the status bar leaves a visible band.
- **Wrap the interactive content in `SafeArea`,** then add design margins *inside* it. The margin is an ergonomic/aesthetic choice, not a platform requirement — `SafeArea` handles the platform intrusions; the margin is yours.

```dart
Scaffold(
  backgroundColor: Theme.of(context).colorScheme.surface, // full-bleed, under the bars
  body: SafeArea(
    child: Padding(
      padding: const EdgeInsetsDirectional.all(16), // your inset, RTL-safe
      child: content,
    ),
  ),
)
```

`SafeArea` can be scoped per-edge (`top: false`, `bottom: false`) when a section should bleed to one edge only — e.g. a bottom bar that intentionally extends under the home indicator with its own internal padding.

## Directional insets always

Use `EdgeInsetsDirectional` and `AlignmentDirectional` for any value that is start/end-specific, so RTL locales mirror by construction. `EdgeInsets.all`/`.symmetric` is fine when all affected edges are equal; the moment left ≠ right, switch to the directional variant. Hardcoded `left`/`right` is a bug in an app that ships any RTL locale — see `i18n-rtl-l10n`.

## Computed cell sizing — never hardcode, never floor

A tile/cell dimension is `(viewport − chrome − gaps) / count`, computed at layout time from `LayoutBuilder` or the grid delegate — not a constant. Two rules:

- **Never hardcode a tile dimension.** It breaks on the next screen size and on text scaling.
- **Never assert a *minimum* tile size.** A size floor fires exactly where large text needs the room most: at 200% `textScaler` the label block may need nearly the whole tile, and a floor that "protects" a minimum tile actually clips the label. The real constraint is that **the label fits** — assert that in a widget test across text scales (see `widget-golden-and-a11y-testing`), not a pixel floor.

`SliverGridDelegateWithMaxCrossAxisExtent` (size-driven) adapts column count to available width; `...FixedCrossAxisCount` (count-driven) fixes the columns and lets the cell width float. Pick by whether the *count* or the *cell size* is the invariant.

## The GridView axis trap

In a **vertical** `GridView`/sliver grid the spacing names are counter-intuitive and the mistake is silent (it looks almost right):

| delegate property | what it controls in a vertical grid |
|---|---|
| `crossAxisSpacing` | the gap **between columns** (horizontal gap) |
| `mainAxisSpacing` | the gap **between rows** (vertical gap) |
| `childAspectRatio` | cell width ÷ height — the usual cause of unexpected overflow |

Getting cross/main backwards swaps your horizontal and vertical gutters. If the design uses unequal gutters, this is visible; if equal, it silently masks the bug until the design changes.

## IME / keyboard insets

`resizeToAvoidBottomInset` (default `true`) shrinks the body by `MediaQuery.viewInsets.bottom` when the keyboard opens, so a scrollable form stays reachable. Two cases:

- **Scrollable form** — leave it `true` (the default). The content scrolls above the keyboard.
- **Fixed-position layout** (a grid whose positions are load-bearing / must not reflow) — set `resizeToAvoidBottomInset: false` so the keyboard overlays the layout instead of squashing it. Do **not** compensate by padding with `MediaQuery.viewInsets.bottom`; if reflow is forbidden, the overlap is intended, and the field you want visible should be placed where the keyboard won't cover it (typically the top).

**Never `autofocus: true`** on a field that opens a keyboard over primary content at cold launch — the user lands on a screen whose content is hidden behind an IME they did not ask for.

For field validation, focus traversal, and keyboard-action wiring inside these layouts, see `forms-and-input`; for how the whole layout reflows on tablets/foldables, see `adaptive-layout`.

## Spanning cells

If a layout has one wide cell among uniform ones (a search/input field spanning the full width above a grid), prefer a `Column` of that widget plus the grid over a spanning `GridView` cell — it is simpler and the seam is invisible as long as the wide cell reuses the same corner radius, fill, and the row gap below it. Reach for a true spanning grid (`StaggeredGrid`, custom `SliverGridDelegate`) only when spans are genuinely dynamic.

## Reachability vs. traversal order are independent

Physical placement (thumb-reachable lower-center) and semantic traversal order (what a screen reader/switch-access visits first) are **separate** and both required. A high-priority target placed low-and-center is reached last by a row-major traversal unless you decouple them with an explicit `Semantics(sortKey: OrdinalSortKey(...))` keyed to priority — never to the grid index or row. See `accessibility-as-code`.
