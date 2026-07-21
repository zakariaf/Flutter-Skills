// A pure, loop-free auth+onboarding guard plus the refreshListenable bridge.
// The guard is a plain function over a state snapshot and GoRouterState — no I/O,
// no navigation, no BuildContext — so it is trivially unit-testable.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

// Sealed auth state (owned by state-management-riverpod). Exhaustive switch, no default.
sealed class AuthState {
  const AuthState();
}
class AuthUnknown extends AuthState { const AuthUnknown(); }        // still resolving
class AuthSignedOut extends AuthState { const AuthSignedOut(); }
class AuthSignedIn extends AuthState {
  const AuthSignedIn({required this.onboarded});
  final bool onboarded;
}

abstract final class Routes {
  static const home = '/';
  static const signIn = '/sign-in';
  static const onboarding = '/onboarding';
}

/// Returns the location to redirect to, or `null` to allow the requested one.
///
/// Loop-free by construction: every branch ALLOWS the destination it would
/// otherwise send the user to (an authed user is not bounced to /sign-in, a
/// signed-out user at /sign-in is left alone).
String? appRedirect(AuthState auth, GoRouterState state) {
  final loc = state.matchedLocation;
  final atSignIn = loc == Routes.signIn;
  final atOnboarding = loc == Routes.onboarding;

  return switch (auth) {
    AuthUnknown() => null, // splash renders at the initial location until resolved
    AuthSignedOut() => atSignIn ? null : Routes.signIn,
    AuthSignedIn(onboarded: false) => atOnboarding ? null : Routes.onboarding,
    AuthSignedIn(onboarded: true) =>
      (atSignIn || atOnboarding) ? Routes.home : null,
  };
}

/// Adapts any auth [Stream] into a [Listenable] for GoRouter.refreshListenable,
/// so the router re-evaluates [appRedirect] the instant auth changes.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<AuthState> stream) {
    notifyListeners();
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<AuthState> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

// Illustrative unit test (see testing-strategy):
//
//   test('signed-out user is sent to sign-in from a protected route', () {
//     final r = appRedirect(const AuthSignedOut(), _stateAt('/items/42'));
//     expect(r, Routes.signIn);
//   });
//
//   test('no loop: signed-out user at sign-in is allowed', () {
//     final r = appRedirect(const AuthSignedOut(), _stateAt(Routes.signIn));
//     expect(r, isNull);
//   });
//
//   test('authed+onboarded user is bounced off the sign-in screen', () {
//     final r = appRedirect(const AuthSignedIn(onboarded: true), _stateAt(Routes.signIn));
//     expect(r, Routes.home);
//   });
