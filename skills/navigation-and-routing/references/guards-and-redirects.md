# Guards and redirects

Access control (auth gate, onboarding gate, "email not verified") is expressed as a **pure `redirect` function**, not as scattered `if (!loggedIn) context.go(...)` inside widgets. One place decides where a location is allowed to resolve.

## The contract

`redirect: (BuildContext context, GoRouterState state) => String?`

- Return `null` → allow the requested location.
- Return a location `String` → send the navigation there instead (a redirect, no history entry).
- It is **pure**: given the same app-state snapshot + `state`, same answer. No I/O, no `await`, no `context.go`, no provider mutation. It runs on **every** navigation and may run repeatedly for a single navigation while it settles.

Feed it a snapshot of the state you need via `ref.read` at the call site in the provider, and re-run it reactively with `refreshListenable`.

## Making it reactive: refreshListenable

The router only re-evaluates `redirect` when navigation happens OR when its `refreshListenable` fires. Bridge the Riverpod auth provider to a `Listenable` so that logging in/out immediately re-runs the guards.

```dart
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  // Re-evaluate redirect whenever auth state changes.
  ref.listen(authNotifierProvider, (_, __) => refresh.value++);

  return GoRouter(
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authNotifierProvider);
      return appRedirect(auth, state);
    },
    routes: appRoutes,
  );
});
```

A small dedicated `Listenable` adapter is also fine:

```dart
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;
  @override
  void dispose() { _sub.cancel(); super.dispose(); }
}
```

## The pure guard function

Keep the decision in a plain testable function that takes the state snapshot and returns a location — no Flutter needed beyond `GoRouterState`.

```dart
// auth + onboarding gate, pure and loop-free
String? appRedirect(AuthState auth, GoRouterState state) {
  final loc = state.matchedLocation;
  final goingToSignIn = loc == Routes.signIn;
  final goingToOnboarding = loc == Routes.onboarding;

  return switch (auth) {
    AuthUnknown() => null,                       // splash still resolving; let it be
    AuthSignedOut() => goingToSignIn ? null : Routes.signIn,
    AuthSignedIn(onboarded: false) =>
        goingToOnboarding ? null : Routes.onboarding,
    AuthSignedIn(onboarded: true) =>
        // already authed: bounce away from auth-only screens
        (goingToSignIn || goingToOnboarding) ? Routes.home : null,
  };
}
```

Note the sealed `AuthState` with an exhaustive `switch` and no `default` (see `dart3-idioms-and-coding-standards`). The `Failure`/state types come from `state-management-riverpod`.

## Avoiding redirect loops

A loop happens when the location you redirect TO is itself redirected. Two disciplines prevent it:

1. **Always allow the guard's own target.** If signed-out users go to `/sign-in`, then `/sign-in` must return `null` for signed-out users (the `goingToSignIn ? null : ...` pattern above).
2. **Compare against `state.matchedLocation`** (the resolved route), not the raw URI, so query strings and sub-paths don't defeat the check.

If `redirect` returns the same location it was given, go_router treats it as "allow" — but rely on explicit checks, not that fallback.

## Route-level vs top-level redirect

- **Top-level `redirect`** (on `GoRouter`) — cross-cutting gates: auth, onboarding, maintenance mode. Runs for every location.
- **Per-`GoRoute` `redirect`** — a rule local to one subtree, e.g. `/items` redirects to `/items/recent` as a default landing. Keep these tiny and still pure.

```dart
GoRoute(
  path: '/items',
  redirect: (context, state) =>
      state.matchedLocation == '/items' ? '/items/recent' : null,
  routes: [ /* children */ ],
),
```

## The "splash while auth resolves" case

Return `null` (allow) while `AuthState` is `AuthUnknown()` and render a splash at the initial location, or redirect everything to a `/splash` route until auth is known. Do **not** block inside `redirect` waiting for the future — that violates purity. The `refreshListenable` fires when auth resolves and the guard re-runs.

## What NEVER goes in a guard

- `await` / any Future.
- `context.go` / `context.push` — return a location string instead.
- `ref.read` of something that triggers a rebuild or a write.
- Reading `DateTime.now()` for a time-based gate — inject a `Clock` (see D3) into the state snapshot instead.
