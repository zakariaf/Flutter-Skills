# Motion tokens and reduced motion

Durations and curves are tokens like any other value. The extra work is that Material animates several things by default, so honoring reduced motion means switching off machines you never turned on.

## Motion lives in tokens

A `MotionTheme` extension holds duration roles and curve families; widgets read the token, never an inline `Duration(milliseconds: 300)` or `Curves.easeOut` (both fail the gate). Keep an ordering invariant so the scale reads sensibly — e.g. `short < medium < long`. Curves are non-interpolable, so `lerp` snaps them.

Canvas/painter animations consume the *same* motion tokens as chrome, snapshotted into painter fields, so the whole app feels like one system.

## The one question a widget asks

```dart
Duration resolveMotion(BuildContext context, Duration full) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : full;
```

**Reduced motion resolves to `Duration.zero`, never to a shorter duration or a "gentler" curve.** A user who asked the OS to stop animations asked for *stop*. If a code path reads the flag only to pick between two non-zero durations, that path already violates the rule — remove the animation, not the branch. The end state must carry the same information without the transition (a cross-fade to the final frame, not a disappearance).

`accessibleNavigationOf` (a screen reader / switch access active) may legitimately change layout or semantics, never timing.

## The three animations Material mounts by default

Reducing motion — or committing to a low/no-motion identity — means killing three independent machines, each of which one switch does *not* cover:

1. **Theme interpolation.** `MaterialApp` mounts an `AnimatedTheme` and interpolates `ThemeData` over `kThemeAnimationDuration` (~200ms). Pass `themeAnimationStyle: AnimationStyle.noAnimation` to stop it. This matters even with a step-function `lerp`: without it, the `ColorScheme` crossfades while your extension snaps at the midpoint — worse than either alone.
2. **Ink splash.** `splashFactory: NoSplash.splashFactory` removes the expanding splash.
3. **Ink highlight.** `NoSplash` does **not** touch the pressed-state highlight — `InkResponse.updateHighlight()` independently creates an `InkHighlight` with its own ~200ms fade. "We don't animate" becomes false the moment anyone drops in a Material button. Set `highlightColor`/`splashColor` transparent, or use a plain `GestureDetector(behavior: HitTestBehavior.opaque)` for a truly instant control.

Plus **route transitions**: a custom `PageTransitionsTheme` (or `AnimationStyle.noAnimation` where a widget exposes a `*AnimationStyle` parameter) governs navigation motion.

The general lesson for *any* app (not just no-motion ones): `NoSplash.splashFactory` is not a complete "no ink animation" — verify the highlight too.

## Restore theme before first paint (a motion concern too)

A flash of the wrong theme at startup is a sudden large luminance change — exactly the event reduced-motion users want to avoid, and one they did not cause. Load the persisted theme before `runApp`; see the SKILL body and `app-startup-and-bootstrap`.

## Tests: don't use `pumpAndSettle` as an "animation is done" wait

`pumpAndSettle()` exists to wait out animations. In a low-motion surface it can only add flake: it carries a 10-minute default timeout and truncates its stack trace on timeout.

```dart
// If there is no animation to settle, one pump is enough:
await tester.tap(find.byType(SubmitButton));
await tester.pump();
```

Be honest about scope: `pump()` does **not** advance the fake clock. `Timer`, `Future.delayed`, debounces, and any minimum-hold floor still need `pump(duration)` or `fakeAsync`. The convention worth enforcing with a grep over `test/`:

> Never use `pumpAndSettle` as an animation wait. Use `pump()` for state changes and `pump(duration)` for time-based async.

A spot check after a tap catches stray animations:

```dart
await tester.tap(find.byType(MyControl));
await tester.pump();
expect(tester.binding.hasScheduledFrame, isFalse,
    reason: 'Tapping scheduled another frame => something animates.');
```

Honest limit: this misses `Timer`-driven repaints and at-rest implicit animations, and only checks the widgets actually tapped. When it goes red, find the animating widget — never silence it with `pumpAndSettle`, which hides the symptom and ships the bug.

## Honest limit on reduced motion

`MediaQuery.disableAnimationsOf` reflects the OS "reduce motion" setting where the platform reports it. It does not catch every animation a third-party widget starts internally; audit dependencies, and for a widget that insists on animating with no opt-out, replace it.
