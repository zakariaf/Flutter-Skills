// Demonstrates reduced motion done right: durations/curves as a ThemeExtension
// token, one resolveMotion() helper that collapses to Duration.zero under the OS
// flag (never "gentler"), and the theme-root switches that each kill a different
// animation Material mounts by default. Durations here are illustrative placeholders.
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Motion token slot. Widgets read these; an inline Duration(milliseconds: 300)
// or Curves.easeOut in a widget fails the no-raw-values gate.
// ---------------------------------------------------------------------------
@immutable
class AppMotion extends ThemeExtension<AppMotion> {
  const AppMotion({required this.short, required this.medium, required this.enter});

  final Duration short;
  final Duration medium;
  final Curve enter; // non-interpolable -> snapped in lerp

  static AppMotion of(BuildContext context) {
    final ext = Theme.of(context).extension<AppMotion>();
    assert(ext != null, 'AppMotion missing. Attach it in your ThemeData.extensions.');
    return ext!;
  }

  @override
  AppMotion copyWith({Duration? short, Duration? medium, Curve? enter}) => AppMotion(
        short: short ?? this.short,
        medium: medium ?? this.medium,
        enter: enter ?? this.enter,
      );

  @override
  AppMotion lerp(covariant AppMotion? other, double t) {
    if (other == null) return this;
    Duration lerpD(Duration a, Duration b) =>
        Duration(microseconds: lerpDouble(a.inMicroseconds, b.inMicroseconds, t)!.round());
    return AppMotion(
      short: lerpD(short, other.short),
      medium: lerpD(medium, other.medium),
      enter: t < 0.5 ? enter : other.enter, // curves don't interpolate — snap
    );
  }
}

const appMotion = AppMotion(
  short: Duration(milliseconds: 120),
  medium: Duration(milliseconds: 240),
  enter: Curves.easeOutCubic,
);

// ---------------------------------------------------------------------------
// The ONE question a widget asks: "should I animate?" Reduced motion resolves to
// ZERO, never a shorter duration or a softer curve.
// ---------------------------------------------------------------------------
Duration resolveMotion(BuildContext context, Duration full) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : full;

class ExpandingPanel extends StatelessWidget {
  const ExpandingPanel({super.key, required this.expanded, required this.child});

  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = AppMotion.of(context);
    return AnimatedSize(
      // Under reduce-motion this is Duration.zero: the panel snaps to its final
      // size, which carries the same information without the transition.
      duration: resolveMotion(context, motion.medium),
      curve: motion.enter,
      child: expanded ? child : const SizedBox.shrink(),
    );
  }
}

// ---------------------------------------------------------------------------
// Theme-root: Material mounts three animations by default. NoSplash alone is NOT
// enough — the pressed highlight is a separate InkHighlight, and MaterialApp
// interpolates ThemeData unless you pass themeAnimationStyle.
// ---------------------------------------------------------------------------
ThemeData applyMotionRootSwitches(ThemeData base) => base.copyWith(
      splashFactory: NoSplash.splashFactory, // kills the splash...
      highlightColor: Colors.transparent, // ...but NOT the highlight fade — kill it too
    );

class LowMotionApp extends StatelessWidget {
  const LowMotionApp({super.key, required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: applyMotionRootSwitches(theme),
      // Without this, MaterialApp crossfades ThemeData over ~200ms on theme change.
      themeAnimationStyle: AnimationStyle.noAnimation,
      home: const SizedBox.shrink(),
    );
  }
}
