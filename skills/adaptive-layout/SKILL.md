---
name: adaptive-layout
description: Enforces adapting layout by available CONSTRAINTS/size, never device or platform checks — LayoutBuilder + MediaQuery.sizeOf/paddingOf/viewInsetsOf (not .of) for narrow rebuilds, Material 3 window size classes (compact <600, medium 600-840, expanded 840-1200, large >1200) as the breakpoint vocabulary, navigation affordance chosen by width (NavigationBar → NavigationRail → NavigationDrawer), list-detail single-pane-vs-two-pane, readable max-width via ConstrainedBox, Flexible/Expanded/FractionallySizedBox over fixed widths, SafeArea + display cutouts + keyboard insets, never lock orientation, foldable/hinge awareness via MediaQuery.displayFeatures, and golden-matrix verification across sizes. Use when building responsive or adaptive UI, tablet/desktop/foldable support, master-detail or two-pane screens, a NavigationRail-vs-BottomNav shell, breakpoints, LayoutBuilder, MediaQuery sizing, SafeArea/cutouts, or fixing overflow at large widths.
---

# Adaptive Layout

Adapt to the **space you are given**, never to the device you think you are on. A phone in a foldable's front display, a resized desktop window, and a tablet in split-screen all defeat `Platform.isX` checks — but they all report their real constraints. Branch on width, not hardware.

Read the reference for the task at hand:

- `references/window-size-classes.md` — the Material 3 window size-class breakpoints as a shared vocabulary, the `WindowSizeClass` enum pattern, `MediaQuery.sizeOf`/`paddingOf`/`viewInsetsOf` vs `.of`, readable max-width, SafeArea and display cutouts, keyboard insets, orientation, foldable hinge awareness.
- `references/list-detail-and-navigation.md` — single-pane-navigate vs side-by-side two-pane, choosing the navigation affordance by width and coordinating with the go_router shell, keeping selection state in a Notifier so both panes agree.

Run `scripts/check_adaptive.sh` before a PR.

## Non-negotiable rules

1. **Adapt by constraints/size, never by device or platform.** No `Platform.isAndroid`/`Platform.isIOS`/`kIsWeb` to pick a *layout*. Use `LayoutBuilder` (local box constraints) or `MediaQuery.sizeOf(context)` (window size). WHY: a resized window, split-screen, and foldable all break device checks; constraints are always true.

2. **Use the Material 3 window size classes as the breakpoint vocabulary.** Compact `<600`, medium `600–840`, expanded `840–1200`, large `1200–1600`, extra-large `≥1600` (logical px width). WHY: these are STANDARD structural breakpoints (not design tokens); one shared enum keeps every screen's breakpoints identical.

3. **Read the narrowest MediaQuery aspect: `sizeOf` / `paddingOf` / `viewInsetsOf` / `viewPaddingOf`, not `MediaQuery.of(context)`.** WHY: `.of` subscribes the widget to EVERY MediaQuery change (keyboard, rotation, text scale); the aspect getters rebuild only when that one field changes — see `flutter-performance`.

4. **Pick the navigation affordance by width, not by a per-screen guess.** `NavigationBar` (compact) → `NavigationRail` (medium/expanded) → `NavigationDrawer` (large). Decide once in the shell. WHY: mixing affordances across screens disorients; one width→affordance map is consistent by construction. Coordinate with `navigation-and-routing`'s `StatefulShellRoute`.

5. **List-detail collapses to one pane on compact and splits on expanded.** Compact: the list navigates to a detail route. Expanded: list and detail sit side-by-side; selection is shared state. WHY: two panes on a phone are unreadable; one pane on a desktop wastes 70% of the width.

6. **Never lock orientation** (`SystemChrome.setPreferredOrientations` to force portrait). WHY: it breaks tablets, foldables, and accessibility mounts. Let the size classes handle both orientations.

7. **Constrain readable content with a max width; use `Flexible`/`Expanded`/`FractionallySizedBox`, not fixed pixel widths, for top-level regions.** WHY: full-width body text on a wide screen is unreadable (~40–75 chars/line is legible); fixed region widths overflow or leave dead space.

8. **Wrap edge content in `SafeArea` and respect display cutouts + keyboard insets.** Read cutouts/system bars via `MediaQuery.paddingOf`/`viewPaddingOf`; the keyboard via `MediaQuery.viewInsetsOf`. WHY: notches, punch-holes, and the on-screen keyboard occlude content that ignores insets.

9. **Never assume a fixed cell/row height.** Large text scale can double a cell's height; let content size itself. WHY: a hardcoded `SizedBox(height: 48)` clips at 200% text scale — see `accessibility-as-code` and `widget-composition`.

10. **Verify across sizes with a golden matrix, not one device.** Snapshot each adaptive screen at compact/medium/expanded (+ largest text, LTR/RTL). WHY: adaptive bugs only appear at the breakpoint you did not open — see `widget-golden-and-a11y-testing`.

## Size classes as one shared enum

Define the breakpoints once; every screen reads the same map.

```dart
enum WindowSizeClass { compact, medium, expanded, large, extraLarge }

WindowSizeClass windowSizeClassFor(double width) => switch (width) {
      < 600 => WindowSizeClass.compact,
      < 840 => WindowSizeClass.medium,
      < 1200 => WindowSizeClass.expanded,
      < 1600 => WindowSizeClass.large,
      _ => WindowSizeClass.extraLarge,
    };

// In a widget: rebuilds only when the window SIZE changes.
final sizeClass = windowSizeClassFor(MediaQuery.sizeOf(context).width);
```

Prefer `LayoutBuilder` when the decision depends on the LOCAL box (a widget inside a split view, a card grid), and `MediaQuery.sizeOf` when it depends on the whole window (the top-level shell).

```dart
// Local constraints drive a card grid's column count.
LayoutBuilder(
  builder: (context, constraints) {
    final columns = constraints.maxWidth ~/ 280; // min card width, structural
    return GridView.count(crossAxisCount: columns.clamp(1, 4), children: cards);
  },
);
```

## Readable width and flexible regions

```dart
// Center and cap body text to a legible measure; never full-bleed on desktop.
Center(
  child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 720), // structural readable cap
    child: article,
  ),
);

// Split a wide body proportionally, not with magic fixed widths.
Row(
  children: [
    Expanded(flex: 2, child: primaryPane),
    Expanded(flex: 3, child: secondaryPane),
  ],
);
```

## Insets, cutouts, keyboard, foldables

```dart
// Keyboard height: rebuilds only when the keyboard shows/hides.
final keyboard = MediaQuery.viewInsetsOf(context).bottom;

// Notch/system-bar padding without subscribing to text-scale/rotation changes.
final safeTop = MediaQuery.paddingOf(context).top;

// Foldable: a vertical fold/hinge spanning the full height => split around it.
final seam = MediaQuery.displayFeaturesOf(context)
    .where((f) =>
        (f.type == DisplayFeatureType.fold ||
            f.type == DisplayFeatureType.hinge) &&
        f.bounds.top == 0 && // starts at the top edge...
        f.bounds.width < f.bounds.height) // ...taller than wide => vertical
    .firstOrNull; // firstOrNull: import 'package:collection/collection.dart';
```

Wrap the outermost interactive region in `SafeArea`; opt specific edges out (`bottom: false`) when a `NavigationBar` or scrolling body should reach the edge.

## Navigation affordance by width

```dart
// One place decides the shell chrome; screens stay affordance-agnostic.
Widget shellFor(WindowSizeClass sc, {required Widget body, required int index}) {
  return switch (sc) {
    WindowSizeClass.compact =>
      Scaffold(body: body, bottomNavigationBar: _NavBar(index: index)),
    WindowSizeClass.medium || WindowSizeClass.expanded =>
      Scaffold(body: Row(children: [_Rail(index: index), Expanded(child: body)])),
    WindowSizeClass.large || WindowSizeClass.extraLarge =>
      Scaffold(body: Row(children: [_Drawer(index: index), Expanded(child: body)])),
  };
}
```

See `examples/adaptive_scaffold.dart` for the full shell and `examples/list_detail_pane.dart` for the two-pane pattern.

## Anti-patterns

- `if (Platform.isIOS) ... else ...` to choose a layout. Branch on `MediaQuery.sizeOf(context).width`.
- `MediaQuery.of(context).size.width` — subscribes to every MediaQuery change. Use `MediaQuery.sizeOf(context)`.
- `SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])` to dodge landscape layout. Support both.
- `Container(width: 375)` or `SizedBox(width: 320)` sizing a top-level pane. Use `Expanded`/`Flexible`/`FractionallySizedBox`/`ConstrainedBox`.
- A `bool isTablet = MediaQuery.of(context).size.shortestSide > 600` flag threaded everywhere. Compute a `WindowSizeClass` from width at the shell.
- Two panes shown on compact width, forcing horizontal scroll. Collapse to one pane and navigate.
- Full-width paragraphs on desktop with no max-width. Cap the measure.
- Assuming the keyboard is hidden — content jumps under it. Pad by `MediaQuery.viewInsetsOf(context).bottom`.

## Definition of done

- No `Platform.is*`/`kIsWeb`/`dart:io` used to select a layout (platform-specific *plugins* are fine).
- Breakpoints come from the shared `WindowSizeClass` helper, not ad-hoc numbers scattered per screen.
- MediaQuery is read via `sizeOf`/`paddingOf`/`viewInsetsOf`/`viewPaddingOf`, not `.of`.
- Navigation affordance is chosen by width in ONE place (the shell), coordinated with `navigation-and-routing`.
- List-detail screens collapse to one pane on compact and split on expanded, sharing selection state.
- No fixed pixel widths on top-level regions; readable content is max-width capped.
- Orientation is not locked; edge content uses `SafeArea`; keyboard insets are respected.
- Golden matrix covers compact/medium/expanded (+ largest text, RTL).
- `scripts/check_adaptive.sh` passes.

## Related skills

- `widget-composition` — structural layout primitives, computed sizing, edge-to-edge vs SafeArea, never-fixed cell heights.
- `navigation-and-routing` — the `StatefulShellRoute` this shell renders; width picks the chrome, routes pick the branch.
- `flutter-performance` — why `sizeOf`/`select` beat `.of` for rebuild scope.
- `accessibility-as-code` — large text scale interacts with every adaptive cell.
- `widget-golden-and-a11y-testing` — the device × text-scale × RTL golden matrix that proves adaptivity.
- `state-management-riverpod` — where shared list-detail selection lives.

## References

- Material 3 layout / window size classes: https://m3.material.io/foundations/layout/applying-layout/window-size-classes
- Adaptive & responsive design (Flutter): https://docs.flutter.dev/ui/adaptive-responsive
- `MediaQuery` API (aspect getters): https://api.flutter.dev/flutter/widgets/MediaQuery-class.html
- `LayoutBuilder`: https://api.flutter.dev/flutter/widgets/LayoutBuilder-class.html
- `NavigationRail`: https://api.flutter.dev/flutter/material/NavigationRail-class.html
- `DisplayFeature` / foldables: https://api.flutter.dev/flutter/dart-ui/DisplayFeature-class.html
