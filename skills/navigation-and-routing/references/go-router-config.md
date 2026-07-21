# go_router configuration

The router is a **declarative data structure**: a tree of `GoRoute`s plus a pure `redirect`. Reachability is by URL, not by whoever happens to call `Navigator.push`.

## One router, one place

Construct `GoRouter(...)` in `lib/routing/` and nowhere else. Expose it through a provider so guards can watch app state, then hand it to the single `MaterialApp.router` in `app.dart`.

```dart
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  ref.listen(authNotifierProvider, (_, __) => refresh.value++);

  return GoRouter(
    initialLocation: Routes.home,
    debugLogDiagnostics: true,
    refreshListenable: refresh,
    redirect: (context, state) => appRedirect(ref.read(authNotifierProvider), state),
    errorBuilder: (context, state) => ErrorScreen(error: state.error),
    routes: [
      GoRoute(path: Routes.home, builder: (c, s) => const HomeScreen()),
      ...itemsRoutes, // a feature contributes its GoRoutes
    ],
  );
});
```

Why a provider and not a top-level `final`: the `redirect` needs to read live Riverpod state (auth, onboarding), and the `refreshListenable` needs a subscription that is disposed with the provider.

## `context.go` vs `context.push` — the mental model

`go_router` maintains a stack derived from the current location. The two verbs move through it differently:

| Call | Effect | Use for |
| --- | --- | --- |
| `context.go(loc)` | Sets the location; **replaces** the stack (or the matched sub-tree) | Tab roots, post-login home, "start over" destinations |
| `context.push(loc)` | **Pushes** a new page on top; returns a `Future` that completes on pop | Detail screens, modal/edit flows you pop back from |
| `context.pop([result])` | Pops the top page, optionally returning a value to the `push` awaiter | Returning up one level |
| `context.replace(loc)` | Replaces the top page in place (no back entry) | Swapping a step without a back stop |

Rule of thumb: if the user expects the system back button to return them to where they were, you `push`. If you are changing "what section of the app am I in," you `go`.

```dart
// stacked detail — awaited result
final saved = await context.push<bool>(Routes.editItem(id));
if (saved == true) { /* refresh */ }

// on the edit screen
context.pop(true);
```

## Path params vs query params vs `extra`

Three transports, three jobs:

- **Path params** (`/items/:id`) — **identity**. Anything the screen needs to reconstruct itself from a cold-start deep link. Always present; read `state.pathParameters['id']!`.
- **Query params** (`/items?status=open`) — **view state that belongs in the URL**: filters, sort, search terms. Read `state.uri.queryParameters['status']`. Optional and stringly-typed.
- **`state.extra`** — a **live in-memory object**, an optimisation only. It is `null` after a deep link, app restart, or state restoration. Never put identity here.

```dart
GoRoute(
  path: '/items/:id',
  builder: (context, state) {
    final id = state.pathParameters['id']!;              // identity
    final tab = state.uri.queryParameters['tab'];        // optional view state
    final preloaded = state.extra as Item?;              // optional fast-path
    return ItemScreen(itemId: id, initialTab: tab, preloaded: preloaded);
  },
),
```

The test: **can you paste the URL into a fresh launch and land on the exact same screen?** If not, identity leaked into `extra`.

## Typed access — constants first, codegen optional

Hand-concatenated path strings rot. Wrap them.

```dart
abstract final class Routes {
  static const home = '/';
  static const items = '/items';
  static String item(String id) => '/items/${Uri.encodeComponent(id)}';
  static const signIn = '/sign-in';
  static const onboarding = '/onboarding';
}
```

`go_router_builder` (`@TypedGoRoute`) generates fully typed route classes with `.go(context)` / `.push(context)` and typed params. It is a legitimate upgrade for large route tables, but it is an **opt-in**, not the baseline — the constant helpers above are enough for most apps and add no codegen step. If you adopt it, keep the generated `*.g.dart` out of the analyzer/coverage per `codegen-and-toolchain`.

```dart
// go_router_builder option (not the default)
@TypedGoRoute<ItemRoute>(path: '/items/:id')
class ItemRoute extends GoRouteData with _$ItemRoute {
  const ItemRoute({required this.id});
  final String id;
  @override
  Widget build(BuildContext context, GoRouterState state) => ItemScreen(itemId: id);
}
// call site: ItemRoute(id: item.id).push(context);
```

## Errors and 404

Set `errorBuilder` (whole-screen) — or `errorPageBuilder` if you need a custom transition — so an unmatched or malformed deep link lands on a designed screen with a way back home. You can also add an explicit catch-all `GoRoute(path: '/404', ...)` and redirect unknown locations to it.

```dart
errorBuilder: (context, state) => Scaffold(
  appBar: AppBar(title: Text(l10n.notFoundTitle)),
  body: Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.notFoundBody),
        TextButton(onPressed: () => context.go(Routes.home), child: Text(l10n.goHome)),
      ],
    ),
  ),
),
```

## Restoration

`MaterialApp.router` restores the current location automatically because it is a URL. That is exactly why identity must live in the path: restoration replays the location string, not your in-memory `extra` objects.
