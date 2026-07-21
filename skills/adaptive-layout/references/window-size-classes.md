# Window size classes, MediaQuery aspects, insets, and foldables

## Why size classes, not devices

`Platform.isAndroid`, `Platform.isIOS`, and `kIsWeb` tell you the OS — never the space you have. All of these break device checks:

- A desktop window resized to 400px wide is "compact" but runs on macOS.
- Android split-screen gives your app half the width with no signal in `Platform`.
- A foldable's cover display is phone-sized; unfolded it is tablet-sized — same OS.
- iPad Slide Over / Split View hands you an arbitrary fraction of the screen.

The only durable input is the **constraints/size you are actually given**. Adapt to that.

## The Material 3 window size classes

These are STANDARD structural breakpoints published by Material 3 — a shared vocabulary, not aesthetic design tokens. Widths are logical pixels of the window.

| Class          | Width (px)   | Typical canonical layout                     |
| -------------- | ------------ | -------------------------------------------- |
| Compact        | `< 600`      | Phone portrait — single pane, bottom nav     |
| Medium         | `600–839`    | Phone landscape / small tablet — rail        |
| Expanded       | `840–1199`   | Tablet / small desktop — rail + two panes    |
| Large          | `1200–1599`  | Desktop — drawer + two/three panes           |
| Extra-large    | `≥ 1600`     | Large desktop — drawer + capped content      |

Encode them ONCE:

```dart
enum WindowSizeClass { compact, medium, expanded, large, extraLarge }

WindowSizeClass windowSizeClassFor(double width) => switch (width) {
      < 600 => WindowSizeClass.compact,
      < 840 => WindowSizeClass.medium,
      < 1200 => WindowSizeClass.expanded,
      < 1600 => WindowSizeClass.large,
      _ => WindowSizeClass.extraLarge,
    };

extension WindowSizeClassX on WindowSizeClass {
  bool get isCompact => this == WindowSizeClass.compact;
  bool get canShowTwoPanes => index >= WindowSizeClass.expanded.index;
}
```

Every screen imports this helper. If a designer says "the sidebar appears on tablets," that becomes `sc.canShowTwoPanes`, not a fresh `> 700` guess in one file.

## `LayoutBuilder` vs `MediaQuery.sizeOf`

Two different questions:

- **"How big is the whole window?"** → `MediaQuery.sizeOf(context)`. Use for the top-level shell that decides nav chrome.
- **"How big is THIS box?"** → `LayoutBuilder`'s `constraints.maxWidth`. Use inside a pane, a card grid, or any widget whose parent may itself be constrained (a widget can be laid out narrow even in a wide window — e.g. the detail pane inside a two-pane split).

Getting this wrong is a real bug: a card grid that reads `MediaQuery.sizeOf` will think it has the whole window's width even when it lives inside a 300px rail-adjacent column. Inside a sub-region, use `LayoutBuilder`.

```dart
// Grid column count from the LOCAL box, not the window.
LayoutBuilder(
  builder: (context, constraints) {
    const minCardWidth = 280.0; // structural minimum, not an aesthetic token
    final columns = (constraints.maxWidth / minCardWidth).floor().clamp(1, 5);
    return GridView.count(crossAxisCount: columns, children: cards);
  },
);
```

## Read the narrowest MediaQuery aspect

`MediaQuery.of(context)` subscribes the calling widget to EVERY field of `MediaQueryData` — size, padding, textScaler, viewInsets, platformBrightness, and more. When the keyboard opens, the widget rebuilds even if it only cared about width. Use the aspect getters, which subscribe to one field:

| Getter                              | Rebuilds when…                    | Use for                          |
| ----------------------------------- | --------------------------------- | -------------------------------- |
| `MediaQuery.sizeOf(context)`        | window size changes               | breakpoint decisions             |
| `MediaQuery.paddingOf(context)`     | safe-area padding changes         | cutouts / system bars            |
| `MediaQuery.viewPaddingOf(context)` | view padding changes (incl. under keyboard) | persistent inset math   |
| `MediaQuery.viewInsetsOf(context)`  | obscured insets change            | keyboard height                  |
| `MediaQuery.textScalerOf(context)`  | text scale changes                | text-scale-aware sizing          |
| `MediaQuery.orientationOf(context)` | orientation changes               | orientation-specific tweaks      |

See `flutter-performance` for the general rebuild-scope principle (`.select`, aspect getters).

## SafeArea, display cutouts, and system bars

`SafeArea` insets its child by `MediaQuery.paddingOf` so content avoids notches, punch-holes, rounded corners, and system bars. Wrap the outermost interactive region. Opt edges out deliberately:

```dart
Scaffold(
  // Body scrolls under a translucent status bar but respects the notch sides.
  body: SafeArea(
    bottom: false, // let the list scroll behind the NavigationBar
    child: bodyList,
  ),
  bottomNavigationBar: navBar, // Scaffold already handles its own safe inset
);
```

For edge-to-edge visuals (a hero image bleeding to the top), do NOT wrap the image in SafeArea — instead pad only the text overlay by `MediaQuery.paddingOf(context).top`.

## Keyboard insets

When a `TextField` gains focus, the keyboard covers the bottom of the screen. `MediaQuery.viewInsetsOf(context).bottom` is its height. Pad scrollable content so the focused field stays visible:

```dart
final keyboard = MediaQuery.viewInsetsOf(context).bottom;
return ListView(
  padding: EdgeInsets.only(bottom: keyboard + 16),
  children: fields,
);
```

`Scaffold` with `resizeToAvoidBottomInset: true` (the default) already resizes its body; keep it on. See `forms-and-input` for field focus and scroll-into-view.

## Do not lock orientation

`SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])` is a smell. It breaks tablets (which are used in landscape), foldables, car mounts, and accessibility rotation. Let the window size classes drive both orientations. Landscape phone → medium class → rail, automatically. If a single screen genuinely cannot work in landscape (rare — a full-bleed camera), scope the lock to that route and restore on pop, never globally in `main()`.

## Foldables and hinges

A foldable can report a `DisplayFeature` describing a fold or hinge that bisects the window. Read them via `MediaQuery.displayFeaturesOf(context)`. A vertical fold (`bounds.width == 0`) suggests splitting content left/right around the seam; a hinge (`bounds.width > 0`) is a dead zone to avoid placing interactive content across.

```dart
final features = MediaQuery.displayFeaturesOf(context);
final verticalSeam = features
    .where((f) =>
        (f.type == DisplayFeatureType.fold ||
            f.type == DisplayFeatureType.hinge) &&
        f.bounds.top == 0 && // starts at the top edge...
        f.bounds.width < f.bounds.height) // ...taller than wide => vertical
    .firstOrNull; // needs: import 'package:collection/collection.dart';

if (verticalSeam != null) {
  // List fills up to the seam; the hinge itself is a dead zone; the detail
  // pane spans from the seam to the right edge (never re-uses the left width).
  final bounds = verticalSeam.bounds;
  return Row(children: [
    SizedBox(width: bounds.left, child: listPane),
    SizedBox(width: bounds.width), // hinge dead zone (0 for a seamless fold)
    Expanded(child: detailPane), // seam -> right edge = maxWidth - bounds.right
  ]);
}
```

Treat this as a progressive enhancement: the size-class two-pane layout already works on foldables; hinge-awareness just aligns the split to the physical seam. Do not block the base adaptive layout on foldable support.

## Interaction with large text

Never hardcode a cell/row/tile height. At 200% text scale a two-line list tile can exceed 96px; a fixed `SizedBox(height: 56)` clips it. Let intrinsic sizing or `ListView` (which measures children) handle it, and test at the largest scale. This is owned by `accessibility-as-code` (never clamp `textScaler`) and `widget-composition` (computed sizing); adaptive layout just must not reintroduce fixed heights when packing tiles into panes.
