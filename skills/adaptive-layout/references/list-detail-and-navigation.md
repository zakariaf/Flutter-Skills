# List-detail (two-pane) and the navigation affordance

## The canonical adaptive pattern: one pane vs two

A list-detail screen (a.k.a. master-detail) shows a collection and a selected item's detail.

- **Compact** (`< 600`): show ONLY the list. Tapping an item navigates to a detail route. Back returns to the list. This is the phone flow.
- **Expanded and up** (`≥ 840`): show list and detail SIDE BY SIDE. Tapping an item updates the right pane in place — no navigation. The list stays visible.
- **Medium** (`600–840`) is a judgement call: usually still single-pane-navigate (a narrow tablet/landscape phone), sometimes a thin list + detail. Default to single-pane unless the detail is genuinely legible under ~480px.

The trap: rendering two panes on compact width forces horizontal scrolling and unreadable columns. Always collapse.

## Selection is shared state, not local

Both layouts must agree on "which item is selected." Keep the selected id in a Notifier (see `state-management-riverpod`), NOT in a `StatefulWidget`'s local field that resets when you cross a breakpoint (a rotation from portrait to landscape rebuilds the subtree).

```dart
// The selection lives above both panes so a resize preserves it.
final selectedItemProvider =
    NotifierProvider<SelectedItemNotifier, ItemId?>(SelectedItemNotifier.new);

class SelectedItemNotifier extends Notifier<ItemId?> {
  @override
  ItemId? build() => null;
  void select(ItemId id) => state = id;
  void clear() => state = null;
}
```

On compact, selecting pushes the detail route AND sets the provider; on expanded, selecting only sets the provider and the right pane rebuilds. When the window grows from compact to expanded while a detail route is on the stack, the shared selection means the two-pane view already shows the right item — the pushed route can be popped or ignored.

## Wiring it to go_router

`navigation-and-routing` OWNS the router. Adaptive-layout decides how many panes to paint, not the route graph. Two clean options:

1. **Single detail route, adaptive body.** The route `/items/:id` renders a widget that, at expanded width, shows `[list | detail]` and at compact shows just the detail. The list route `/items` similarly shows two panes at expanded. Simple; some duplication.

2. **Shell owns the split.** A `StatefulShellRoute` (or a plain shell widget) renders the list pane as fixed chrome at expanded width and the branch's content as the detail pane. Cleaner for a persistent list.

Either way, the *pane count* is a function of `MediaQuery.sizeOf(context).width`, and the *route* is a function of navigation intent. Keep them separate.

```dart
// Adaptive body used by the list route.
class ItemsScreen extends ConsumerWidget {
  const ItemsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final twoPane =
        windowSizeClassFor(MediaQuery.sizeOf(context).width).canShowTwoPanes;
    final selected = ref.watch(selectedItemProvider);

    if (!twoPane) return const ItemListPane(); // compact: list only

    return Row(
      children: [
        const SizedBox(width: 360, child: ItemListPane()), // structural list width
        const VerticalDivider(width: 1),
        Expanded(
          child: selected == null
              ? const _EmptyDetailPlaceholder()
              : ItemDetailPane(id: selected),
        ),
      ],
    );
  }
}
```

Note: the 360px list column is a deliberate *fixed list width paired with `Expanded` detail* — the list is a bounded control column, the content pane flexes. That is the one place a fixed width is idiomatic; the primary content region must still be `Expanded`/`Flexible`.

## Choosing the navigation affordance by width

Material 3 maps width to a navigation component. Decide ONCE in the shell so every screen is consistent:

| Width class      | Affordance          | Notes                                        |
| ---------------- | ------------------- | -------------------------------------------- |
| Compact          | `NavigationBar`     | 3–5 destinations along the bottom            |
| Medium, Expanded | `NavigationRail`    | vertical, left edge; `extended` at expanded  |
| Large, X-large   | `NavigationDrawer`  | always-visible standard drawer, labeled      |

```dart
Widget adaptiveShell({
  required WindowSizeClass sc,
  required int selectedIndex,
  required ValueChanged<int> onSelect,
  required List<NavItem> items,
  required Widget body,
}) {
  switch (sc) {
    case WindowSizeClass.compact:
      return Scaffold(
        body: body,
        bottomNavigationBar: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onSelect,
          destinations: [
            for (final it in items)
              NavigationDestination(icon: Icon(it.icon), label: it.label),
          ],
        ),
      );
    case WindowSizeClass.medium:
    case WindowSizeClass.expanded:
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            extended: sc == WindowSizeClass.expanded,
            selectedIndex: selectedIndex,
            onDestinationSelected: onSelect,
            labelType: sc == WindowSizeClass.expanded
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            destinations: [
              for (final it in items)
                NavigationRailDestination(
                    icon: Icon(it.icon), label: Text(it.label)),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    case WindowSizeClass.large:
    case WindowSizeClass.extraLarge:
      return Scaffold(
        body: Row(children: [
          NavigationDrawer(
            selectedIndex: selectedIndex,
            onDestinationSelected: onSelect,
            children: [
              for (final it in items)
                NavigationDrawerDestination(
                    icon: Icon(it.icon), label: Text(it.label)),
            ],
          ),
          Expanded(child: body),
        ]),
      );
  }
}
```

`onSelect` should call the router (`navigation-and-routing`) — e.g. `goBranch(index)` on a `StatefulShellRoute`'s navigation shell — so the affordance is just chrome and the route graph stays the single source of navigation truth.

## Verify at every breakpoint

An adaptive layout has at least three states (compact/medium/expanded) that a single simulator never exercises together. Drive a golden matrix (see `widget-golden-and-a11y-testing`) sizing the test surface to 400 / 700 / 1000 / 1400 px, each also at the largest text scale and in RTL. The list-detail transition (does selection survive a resize? does the placeholder show when nothing is selected?) is the highest-value assertion.
