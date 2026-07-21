// The single app GoRouter behind a Riverpod provider: typed route constants,
// path-param identity, an errorBuilder/404, and a StatefulShellRoute tab shell.
// This is the ONLY place GoRouter(...) is constructed; app.dart just watches it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

// --- Route constants: no hand-concatenated path strings at call sites. --------
abstract final class Routes {
  static const home = '/';
  static const items = '/items';
  static String item(String id) => '/items/${Uri.encodeComponent(id)}';
  static const account = '/account';
  static const signIn = '/sign-in';
  static const onboarding = '/onboarding';
}

sealed class AuthState {
  const AuthState();
}
class AuthUnknown extends AuthState { const AuthUnknown(); }
class AuthSignedOut extends AuthState { const AuthSignedOut(); }
class AuthSignedIn extends AuthState {
  const AuthSignedIn({required this.onboarded});
  final bool onboarded;
}

// Auth state as a manual Notifier provider (owned by state-management-riverpod;
// shown here as a stub contract). Manual providers are the default — NOT the
// legacy StateProvider, and NOT a *Controller.
final authNotifierProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

class AuthNotifier extends Notifier<AuthState> {
  @override
  AuthState build() => const AuthUnknown();
  // signIn()/signOut() etc. live in state-management-riverpod.
}

// --- Pure, loop-free redirect (see guards-and-redirects.md). ------------------
String? appRedirect(AuthState auth, GoRouterState state) {
  final loc = state.matchedLocation;
  final atSignIn = loc == Routes.signIn;
  final atOnboarding = loc == Routes.onboarding;
  return switch (auth) {
    AuthUnknown() => null,
    AuthSignedOut() => atSignIn ? null : Routes.signIn,
    AuthSignedIn(onboarded: false) => atOnboarding ? null : Routes.onboarding,
    AuthSignedIn(onboarded: true) =>
      (atSignIn || atOnboarding) ? Routes.home : null,
  };
}

// --- The single router. -------------------------------------------------------
final routerProvider = Provider<GoRouter>((ref) {
  // Bridge Riverpod auth changes to a Listenable the router re-evaluates on.
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  ref.listen(authNotifierProvider, (_, __) => refresh.value++);

  return GoRouter(
    initialLocation: Routes.home,
    refreshListenable: refresh,
    redirect: (context, state) => appRedirect(ref.read(authNotifierProvider), state),
    errorBuilder: (context, state) => _ErrorScreen(error: state.error),
    routes: [
      GoRoute(path: Routes.signIn, builder: (c, s) => const _SignInScreen()),
      GoRoute(path: Routes.onboarding, builder: (c, s) => const _OnboardingScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            _AppShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.home, builder: (c, s) => const _HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: Routes.items,
              builder: (c, s) => const _ItemsScreen(),
              routes: [
                GoRoute(
                  path: ':id', // identity in the PATH — deep-linkable on cold start
                  builder: (context, state) => _ItemScreen(
                    itemId: state.pathParameters['id']!,
                    // extra is an optional fast-path; screen works when null.
                    preloaded: state.extra as Item?,
                  ),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: Routes.account, builder: (c, s) => const _AccountScreen()),
          ]),
        ],
      ),
    ],
  );
});

// --- Tab shell chrome (rail vs bottom bar owned by adaptive-layout). ----------
class _AppShell extends StatelessWidget {
  const _AppShell({required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  void _onTap(int index) => navigationShell.goBranch(
        index,
        initialLocation: index == navigationShell.currentIndex,
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: _onTap,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.inventory_2_outlined), label: 'Items'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Account'),
        ],
      ),
    );
  }
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.error});
  final Exception? error;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Not found')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${error ?? 'Page not found'}'),
              TextButton(
                onPressed: () => context.go(Routes.home),
                child: const Text('Go home'),
              ),
            ],
          ),
        ),
      );
}

// --- Screen + model stubs so the example reads as a whole file. ---------------
class Item {
  const Item(this.id);
  final String id;
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen();
  @override
  Widget build(BuildContext context) => const Placeholder();
}
class _ItemsScreen extends StatelessWidget {
  const _ItemsScreen();
  @override
  Widget build(BuildContext context) => const Placeholder();
}
class _ItemScreen extends StatelessWidget {
  const _ItemScreen({required this.itemId, this.preloaded});
  final String itemId;
  final Item? preloaded;
  @override
  Widget build(BuildContext context) => const Placeholder();
}
class _AccountScreen extends StatelessWidget {
  const _AccountScreen();
  @override
  Widget build(BuildContext context) => const Placeholder();
}
class _SignInScreen extends StatelessWidget {
  const _SignInScreen();
  @override
  Widget build(BuildContext context) => const Placeholder();
}
class _OnboardingScreen extends StatelessWidget {
  const _OnboardingScreen();
  @override
  Widget build(BuildContext context) => const Placeholder();
}
