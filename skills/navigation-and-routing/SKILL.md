---
name: navigation-and-routing
description: Enforces one app-wide GoRouter in lib/routing/ wired via MaterialApp.router, deep-linkable identity in path params never state.extra, context.go-vs-context.push discipline, redirect guards as pure functions driven by a Riverpod refreshListenable, StatefulShellRoute.indexedStack for branch-state-preserving BottomNavigationBar/NavigationRail shells, CustomTransitionPage transitions that respect reduced motion, PopScope (canPop/onPopInvokedWithResult) for unsaved-changes interception, and an errorBuilder 404 route. Use when adding routes, GoRoute, redirect, auth/onboarding gates, deep links, ShellRoute or nested navigation, bottom-nav/rail tab shells, page transitions, back-button/unsaved-changes handling, notification-payload-to-location mapping, typed routes, go_router_builder, or wiring go_router into app.dart.
---

# Navigation and routing

This skill owns app navigation with `go_router`. There is exactly ONE `GoRouter` for the app, defined in `lib/routing/`, and every screen is reachable by a URL. Navigation is a data structure (routes + a pure redirect), not a pile of imperative `Navigator.push` calls.

Read the reference for the task at hand:
- `references/go-router-config.md` — the single router, `context.go` vs `context.push`, path params vs `state.extra`, typed route helpers, `errorBuilder`/404.
- `references/guards-and-redirects.md` — pure `redirect` functions, the Riverpod `refreshListenable`, auth + onboarding gates, avoiding redirect loops.
- `references/shells-and-deep-links.md` — `StatefulShellRoute.indexedStack` for bottom-nav/rail shells, `CustomTransitionPage`, `PopScope`, and notification-payload → location mapping.

Run `scripts/check_routing.sh` before a PR.

## Non-negotiable rules

1. **Exactly ONE `GoRouter`, built in `lib/routing/`, wired once via `MaterialApp.router` in `app.dart`.** Multiple routers fragment history, deep links, and back-button behaviour. The router is created behind a provider so guards can watch app state.
2. **Deep-linkable identity lives in PATH PARAMS, never in `state.extra`.** `extra` is a live Dart object: it is `null` on a cold start from a deep link and after process death / restoration. A screen that needs an id to rebuild must read it from `state.pathParameters` so the URL alone fully reconstructs the screen.
3. **`state.extra` is ONLY an optional non-identity optimisation** (a pre-fetched object to avoid a reload flash). The screen must still work — refetch by id — when `extra` is `null`.
4. **Use `context.go` to replace the stack (declarative destinations, tabs, post-login home); use `context.push` to stack a screen you expect to pop back from (a detail, a modal flow).** Mixing them wrong breaks the back button. Know which one every call site needs.
5. **Guards are PURE `redirect` functions.** `redirect` returns a new location `String?` (or `null` to allow) from `GoRouterState` + a snapshot of app state. No I/O, no navigation calls, no side effects inside `redirect` — it runs on every navigation and can run repeatedly.
6. **Reactive guards use a `refreshListenable`, not polling.** Bridge the Riverpod auth/onboarding provider to a `Listenable`; the router re-evaluates `redirect` whenever it fires. See `state-management-riverpod`.
7. **Redirects must be loop-free.** Always allow the destination the guard sends you TO (e.g. never redirect `/sign-in` back to `/sign-in`). Guard against `A→B→A` by checking the current location before redirecting.
8. **Tab/branch shells use `StatefulShellRoute.indexedStack`.** It preserves each branch's navigation stack and state across tab switches; a plain `ShellRoute` with an `IndexedStack` you wire by hand does not survive router rebuilds as cleanly. Switch branches with `navigationShell.goBranch(index)`.
9. **Custom transitions go through `CustomTransitionPage` and respect reduced motion.** When the platform requests reduced motion, collapse to a no-op/fade. Read the flag from `MediaQuery`, resolve motion via the design system — see `accessibility-as-code` and `design-system-structure`.
10. **Intercept back / unsaved changes with `PopScope`, not `WillPopScope`** (removed). Set `canPop: false` and handle in `onPopInvokedWithResult(bool didPop, T? result)`; only navigate away after the user confirms.
11. **Provide an `errorBuilder` and a real 404/error route.** An unmatched deep link must land on a designed error screen, never a red error box.
12. **Never hold a `BuildContext` across an `await` before navigating.** Capture `GoRouter.of(context)` (or the router) before the await, or guard with `context.mounted` after. See `async-safety`.
13. **A feature does not build its own router.** `scaffold-feature-module` registers a feature's `GoRoute` INTO this router's route list; features never instantiate `GoRouter`.

## The single router

`app.dart` reads the router from a provider and hands it to `MaterialApp.router`. The router itself lives in `routing/` and is the only place `GoRouter(...)` is constructed.

```dart
// routing/app_router.dart
final routerProvider = Provider<GoRouter>((ref) {
  // Bridge Riverpod auth state to a Listenable the router can watch.
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  ref.listen(authNotifierProvider, (_, __) => refresh.value++);

  return GoRouter(
    initialLocation: Routes.home,
    refreshListenable: refresh,
    redirect: (context, state) => appRedirect(ref.read(authNotifierProvider), state),
    errorBuilder: (context, state) => ErrorScreen(error: state.error),
    routes: $appRoutes, // assembled from feature route lists
  );
});
```

```dart
// app.dart — the only MaterialApp.router
class MyApp extends ConsumerWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      routerConfig: router,
      theme: lightTheme,
      darkTheme: darkTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    );
  }
}
```

## Identity in the path, not in extra

```dart
// GOOD: id is in the URL — a cold-start deep link to /items/42 fully rebuilds.
GoRoute(
  path: '/items/:id',
  builder: (context, state) {
    final id = state.pathParameters['id']!; // always present
    // extra is an OPTIONAL fast-path; screen must work when it is null.
    final preloaded = state.extra as Item?;
    return ItemScreen(itemId: id, preloaded: preloaded);
  },
),
```

```dart
// BAD: identity smuggled through extra — null on cold start / after process death.
context.push('/item', extra: item); // no id in the URL => not deep-linkable
```

## Typed route helpers (constants, not string soup)

Prefer small constant/builder classes so call sites never hand-concatenate paths. `go_router_builder` codegen is an OPTIONAL upgrade, not the default.

```dart
// routing/routes.dart
abstract final class Routes {
  static const home = '/';
  static const items = '/items';
  static String item(String id) => '/items/$id';
  static const signIn = '/sign-in';
}

// call site
context.push(Routes.item(item.id));
```

## go vs push

```dart
context.go(Routes.home);          // replace whole stack: post-login, tab roots
context.push(Routes.item(id));    // stack a detail you'll pop back from
context.pop(result);              // return up, optionally with a result
```

## Anti-patterns

- Two `GoRouter` instances, or a nested `Navigator`/`MaterialApp` inside a screen for "sub-navigation." Use nested routes / `StatefulShellRoute`.
- Passing a domain id through `state.extra` and reading `extra!` in `build` — crashes on cold start.
- I/O, `ref.read` of async work, or calling `context.go` INSIDE `redirect`. Redirect is pure and returns a location.
- A `redirect` that can bounce forever because it also redirects its own target.
- Mixing `Navigator.pushNamed('/x')` string routes with go_router — one navigation system only.
- `WillPopScope` (removed) instead of `PopScope`.
- Awaiting then using the same `context` to navigate without a `mounted` check.
- A feature package/folder constructing its own `GoRouter`.

## Definition of done

- One `GoRouter` in `lib/routing/`, one `MaterialApp.router` in `app.dart`.
- Every screen reachable by a URL; every id-bearing screen reads its id from `state.pathParameters`.
- `state.extra` is only ever an optional optimisation; every such screen renders correctly with `extra == null`.
- Guards are pure `redirect` functions with a `refreshListenable`; no redirect loops.
- Tab shells use `StatefulShellRoute.indexedStack`; branch state survives tab switches.
- Transitions respect reduced motion; `errorBuilder` + 404 route present.
- `PopScope` guards unsaved changes; no `BuildContext` used across an await when navigating.
- `scripts/check_routing.sh` passes.

## Related skills

- `app-startup-and-bootstrap` — owns `main()`/`bootstrap()` ordering and where `MaterialApp.router` is mounted.
- `state-management-riverpod` — the auth/onboarding providers the `refreshListenable` bridges.
- `scaffold-feature-module` — registers a feature `GoRoute` into this router.
- `adaptive-layout` — chooses `NavigationRail` vs `BottomNavigationBar` by width for the shell.
- `accessibility-as-code` — reduced-motion flag and semantics for navigation.
- `design-system-structure` — the reduced-motion token / `resolveMotion` helper for transitions.
- `async-safety` — `BuildContext`/`mounted` rules around awaited navigation.
- `local-notifications-scheduler` — the notification payload whose pure mapper produces a location.

## References

- go_router package: https://pub.dev/packages/go_router
- go_router API docs: https://pub.dev/documentation/go_router/latest/
- Flutter navigation & routing: https://docs.flutter.dev/ui/navigation
- Deep linking: https://docs.flutter.dev/ui/navigation/deep-linking
- PopScope API: https://api.flutter.dev/flutter/widgets/PopScope-class.html
