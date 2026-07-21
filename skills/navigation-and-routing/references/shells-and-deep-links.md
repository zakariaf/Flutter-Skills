# Shells, transitions, PopScope, and deep links

## Tab/branch shells: `StatefulShellRoute.indexedStack`

A bottom-nav or rail app has N branches, each with its **own navigation stack** that must survive switching away and back (scroll position, pushed detail, form state). `StatefulShellRoute.indexedStack` gives you exactly this: it keeps every branch alive in an `IndexedStack` and hands you a `navigationShell` to drive.

```dart
StatefulShellRoute.indexedStack(
  builder: (context, state, navigationShell) =>
      AppShell(navigationShell: navigationShell), // your Scaffold with the nav bar
  branches: [
    StatefulShellBranch(routes: [
      GoRoute(path: Routes.home, builder: (c, s) => const HomeScreen()),
    ]),
    StatefulShellBranch(routes: [
      GoRoute(
        path: Routes.items,
        builder: (c, s) => const ItemsScreen(),
        routes: [
          // pushes INSIDE the items branch — stays under the same tab
          GoRoute(path: ':id', builder: (c, s) =>
              ItemScreen(itemId: s.pathParameters['id']!)),
        ],
      ),
    ]),
    StatefulShellBranch(routes: [
      GoRoute(path: Routes.account, builder: (c, s) => const AccountScreen()),
    ]),
  ],
),
```

Switch branches with `navigationShell.goBranch`:

```dart
void _onTap(int index) => navigationShell.goBranch(
  index,
  // tapping the active tab again returns it to its branch root
  initialLocation: index == navigationShell.currentIndex,
);
```

### Rail vs bottom bar by width

The shell widget chooses the chrome, not the router. Use the Material 3 window size classes — `NavigationBar` at compact widths (< 600), `NavigationRail` at medium/expanded (≥ 600). `adaptive-layout` owns the breakpoint logic; the router is width-agnostic and just supplies `navigationShell`.

```dart
@override
Widget build(BuildContext context) {
  final wide = MediaQuery.sizeOf(context).width >= 600; // structural size class
  return wide
      ? Scaffold(body: Row(children: [
          NavigationRail(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _onTap,
            destinations: _railDestinations,
          ),
          const VerticalDivider(width: 1),
          Expanded(child: navigationShell),
        ]))
      : Scaffold(
          body: navigationShell,
          bottomNavigationBar: NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: _onTap,
            destinations: _barDestinations,
          ),
        );
}
```

A non-tab shell (shared chrome, one stack) can still use a plain `ShellRoute`. Reach for `StatefulShellRoute.indexedStack` specifically when branches must retain independent state.

## Page transitions: `CustomTransitionPage` + reduced motion

Return a `Page` from `pageBuilder` (instead of `builder`) to control the transition. Respect the platform reduced-motion request: collapse animated slides to a fade or no-op.

```dart
GoRoute(
  path: Routes.item(':id'),
  pageBuilder: (context, state) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    return CustomTransitionPage<void>(
      key: state.pageKey,
      child: ItemScreen(itemId: state.pathParameters['id']!),
      transitionsBuilder: (context, animation, secondary, child) {
        if (reduceMotion) return child; // or FadeTransition
        return SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: child,
        );
      },
    );
  },
),
```

Prefer resolving the motion decision through the design system's `resolveMotion` helper (see `design-system-structure`) rather than hand-reading flags at each route. The reduced-motion rule itself is owned by `accessibility-as-code`. For platform-default transitions, plain `builder` (which yields a `MaterialPage`/`CupertinoPage`) already adapts per platform — only reach for `CustomTransitionPage` when you need something specific.

## Intercepting back / unsaved changes: `PopScope`

`WillPopScope` is removed. Use `PopScope`: set `canPop: false` to block the pop, then decide in `onPopInvokedWithResult`. Only leave after the user confirms.

```dart
class EditItemScreen extends StatefulWidget { /* ... */ }

class _EditItemScreenState extends State<EditItemScreen> {
  bool _dirty = false;

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: !_dirty, // when clean, let the system pop normally
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;            // pop already happened; nothing to do
        final leave = await _confirmDiscard(context);
        if (leave && context.mounted) context.pop();
      },
      child: Scaffold(/* form ... */),
    );
  }
}
```

Notes:
- `canPop` must reflect current state; toggle it when the form becomes dirty/clean so the OS predictive-back gesture behaves correctly.
- The callback is `onPopInvokedWithResult(bool didPop, T? result)` (the older `onPopInvoked(bool)` is deprecated). When `didPop` is `true`, the frame already popped — do not pop again.
- Guard the post-`await` `context` use with `context.mounted` (see `async-safety`).

## Deep links and notification payloads → location (pure mapper)

An incoming deep link URI and a notification tap payload must both resolve to a **location string** through a **pure function** — no navigation inside the mapper. The caller then does the single `context.go`/`router.go`.

```dart
// pure: payload -> location; unit-testable, no Flutter, no BuildContext
String locationForPayload(NotificationPayload p) => switch (p) {
  ItemReminderPayload(:final itemId) => Routes.item(itemId),
  DigestPayload() => Routes.items,
  UnknownPayload() => Routes.home,
};
```

```dart
// at the tap handler / link handler — capture the router BEFORE any await
final router = ref.read(routerProvider);
final location = locationForPayload(payload);
router.go(location); // identity is in the path, so it survives cold start
```

Because the target location carries identity in its **path params**, a notification that launches the app from cold lands on the right screen with a full rebuild — `state.extra` would have been `null`. The payload schema and its versioning are owned by `local-notifications-scheduler`; this skill owns only the payload→location mapping and the navigation call.

For OS deep links, go_router consumes the incoming URI automatically via `MaterialApp.router`; you only configure platform intent filters / associated domains (see the Flutter deep-linking guide). No manual `Navigator` wiring.
