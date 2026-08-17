---
name: motion-and-haptics
description: >-
  Enforces designed interaction feedback instead of the framework default — every committing
  interaction acknowledged in the same frame, motion that decorates state but never IS the state
  (the end state is identical with animations off), a named catalog of moments each declaring its
  trigger, duration role, haptic slot and reduced-motion fallback at design time, haptics as a
  HapticTheme event-to-intensity map fired exactly once on the commit frame (never per animation
  frame, never per coalesced input, never heavyImpact for an error) behind one central toggle,
  every animation interruptible so a tap resolves it to its end state, a bounded celebration
  that plays once and never loops or blocks input, an explicit stop condition on every repeating
  animation (off-route, backgrounded, reduced motion), and feedback on more than one channel so
  haptics and sound survive reduced motion. Use when adding or tuning an animation, a success or
  error state, a haptic, a celebration, or a screen transition.
---

# Motion and haptics

What fires, when, exactly once, and how it degrades. Feedback is the layer users feel rather than
read — an app whose taps land, whose errors are felt, and whose success is acknowledged reads as
finished; the same app with default Material feedback reads as a prototype.

**Scope boundary.** Motion *tokens* — duration roles, curve slots, the no-raw-values gate, and
`resolveMotion` collapsing to `Duration.zero` under reduced motion — are owned by
`design-system-structure`. Painter/ticker mechanics are owned by `custom-canvas-and-gestures`.
*Which* surface a message uses — loading, empty, error, snackbar, banner, dialog, Undo, and
screen-reader announcements — is owned by `ui-states-and-feedback`. This skill owns the sensory
layer those decisions ride on: which moments exist, what each one commits to, how haptics are
mapped and fired, and what survives when the animation does not.

## Non-negotiable rules

1. **Every committing interaction is acknowledged in the same frame it happens.** Finger-down shows a
   press state immediately; the commit's own feedback follows on commit. WHY: a control that waits
   for an async result before showing anything is indistinguishable from a control that did not
   register the tap, and the user taps again.

2. **Motion decorates state; it is never the state.** The end state must be identical, correct, and
   reachable with all animations disabled. A selection that only exists while its animation runs, or
   a value that is only legible mid-transition, is a bug that reduced-motion users hit every time.

3. **Name your moments and design each one deliberately.** Every app has a small catalog — press
   acknowledgment, rejected input, the commit payoff, success, progress or streak increment, and the
   signature screen transition. Each moment declares five things: its **trigger**, what **changes**,
   which **duration role** and curve it spends, its **haptic slot**, and its **reduced-motion
   fallback**. A moment left unspecified is not "minimal" — it is the framework default, chosen by
   nobody. See `references/moment-catalog.md`.

4. **Every animation declares its reduced-motion behaviour at design time.** "It is small, nobody will
   mind" is not a fallback. The mechanism (`resolveMotion` → `Duration.zero`) belongs to
   `design-system-structure`; the *decision* — cross-fade to the end state, appear already-complete,
   omit the flourish entirely — is made per moment, here, and written down. Feature code never
   re-reads the platform flag per animation.

5. **Haptics are a map, not scattered calls.** A `HapticTheme` extension maps each event to at most
   one `HapticFeedback` verb: selection ≤ `selectionClick`, commit ≤ `lightImpact`/`mediumImpact`,
   rejection ≤ `lightImpact`, success ≤ `mediumImpact`, and `heavyImpact` reserved for a genuine
   milestone. A **`null` slot is a declared silence**, not an omission. WHY: haptics added ad hoc at
   call sites always drift upward in intensity until the app buzzes.

6. **Fire one haptic per committed event, on the commit frame.** Never inside an animation callback,
   never per frame, never once per input in a coalesced gesture — a drag emits at most an engage and
   a commit. WHY: a haptic per frame is a vibration, and a haptic per coalesced input turns a fast
   gesture into a rattle.

7. **`heavyImpact` is never the error sound.** Escalating intensity for failure punishes the user for
   a mistake the UI could have prevented. Rejection is acknowledged, not amplified.

8. **One in-app toggle gates every haptic, celebrations included.** Platforms have their own coarse
   system-haptics setting; an app that fires haptics needs its own switch too, and it must be a single
   central gate rather than a flag each call site remembers to check.

9. **Every animation is interruptible.** A tap during a transition or celebration resolves it to its
   end state immediately. Never block input for the duration of a flourish, and never make the user
   wait out a success. WHY: the second time a user sees a celebration they want to be past it.

10. **Celebrations have a budget.** Bounded element count, bounded time to the next interactive
    state, originating from the point of action rather than the screen edges, **played once, never
    looped**. Failure states get acknowledgment with no shaming motion. WHY: an unbounded celebration
    is a load screen the user did not ask for.

11. **Every repeating or ambient animation declares a stop condition.** It stops when its route is not
    current, when the app is backgrounded, and under reduced motion. A `repeat()` with no stop
    condition is a battery bug that no test will catch and no reviewer will see.

12. **Feedback is redundant across channels.** Haptics and sound survive reduced motion precisely
    because they are the remaining channels — so a state change may never be carried by motion alone.
    (Color-alone is owned by `accessibility-as-code`; this is the motion-alone half of the same rule.)

13. **Sound, if any, is the third channel and never the first.** Respect the platform's silent
    behaviour, keep it short, never require it to understand what happened, and gate it behind the
    same kind of central toggle as haptics.

14. **Transitions follow reading direction; a fixed content surface does not re-mirror.** A horizontal
    push flips under RTL because navigation is directional; a canvas, board, chart, or media surface
    whose own layout is direction-neutral stays as it is. Direction geometry is owned by
    `i18n-rtl-l10n`.

## The moment declaration

Write each moment down before implementing it. The table *is* the specification — an implementation
that cannot fill a column has not finished designing that moment.

| Moment | Trigger | What changes | Duration role | Haptic | Reduced-motion fallback |
|---|---|---|---|---|---|
| Press | pointer down | press transform | shortest | `selectionClick` | instant state, no transform |
| Reject | invalid input | bounded shake + message | short, interruptible | `lightImpact` | message only, no shake |
| Commit | state committed | the transformation itself | medium | `lightImpact` | end state appears instantly |
| Success | task complete | acknowledgment + result | long, skippable | `mediumImpact` | result appears already complete |
| Increment | counter advances | one emphasis pulse | short | `selectionClick` or silence | new value, no pulse |
| Transition | route change | the signature transition | medium | none | cross-fade or none |

Durations here are *roles*, not numbers — the numbers are tokens owned by `design-system-structure`.

## Firing a haptic exactly once

```dart
// The event map lives in the theme; call sites name an event, never an intensity.
@immutable
class HapticTheme extends ThemeExtension<HapticTheme> {
  const HapticTheme({this.select, this.commit, this.reject, this.success});

  /// A null slot is a DECLARED silence — the design said no haptic here.
  final Future<void> Function()? select;
  final Future<void> Function()? commit;
  final Future<void> Function()? reject;
  final Future<void> Function()? success;
  // copyWith / lerp omitted — see design-system-structure for the ThemeExtension contract.
}

// One central gate; no call site remembers to check the setting.
void fire(WidgetRef ref, Future<void> Function()? slot) {
  if (!ref.read(hapticsEnabledProvider)) return;
  slot?.call();
}

// At the commit — once, on the frame the state actually changed (rules 6, 8).
void onCommit(BuildContext context, WidgetRef ref, EditIntent intent) {
  ref.read(itemsProvider.notifier).apply(intent);          // state first
  fire(ref, Theme.of(context).extension<HapticTheme>()!.commit);
}
```

Never call `HapticFeedback.*` from an `AnimationController` listener, an `onEnd` callback, or a
per-item loop — those are the three places a single event becomes a burst.

## Anti-patterns

- **A control with no press state** — every "did that register?" double-tap starts here.
- **State that only exists while an animation runs** — turn animations off and the app must still be
  correct and legible.
- **An animation with no designed reduced-motion behaviour**, or feature code re-reading the platform
  flag per animation.
- **`HapticFeedback.mediumImpact()` sprinkled at call sites** — map events to slots once; ad-hoc
  haptics only ever escalate.
- **A haptic in an animation listener, an `onEnd`, or per item in a coalesced gesture** — one per
  committed event, on the commit frame.
- **`heavyImpact` for an error** — acknowledge failure, do not punish it.
- **An un-skippable celebration, or blocked input during a flourish** — a tap resolves it instantly.
- **A looping celebration, edge-spawned particles, or an unbounded element count** — budget it.
- **A "sad" failure animation** — the user already knows.
- **`repeat()` with no stop condition** — it must stop off-route, backgrounded, and under reduced motion.
- **Sound as the only signal**, or sound that ignores the platform's silent behaviour.
- **A mirrored content surface under RTL** — navigation direction flips, a direction-neutral canvas does not.

## Definition of done

- [ ] Every committing interaction acknowledges within the same frame.
- [ ] Every moment touched has a filled-in declaration row: trigger, change, duration role, haptic
      slot, reduced-motion fallback.
- [ ] The end state is identical and reachable with animations disabled; nothing is motion-only.
- [ ] Haptics come from the `HapticTheme` map, are at or below the intensity ceiling for their event,
      fire once per committed event on the commit frame, and are gated by one central toggle.
- [ ] `null` haptic slots are deliberate silences, recorded as such.
- [ ] Every animation is interruptible; a tap resolves it to its end state; input is never blocked.
- [ ] Celebrations are bounded, originate from the point of action, play once, and never loop.
- [ ] Every repeating animation has an explicit stop condition for off-route, backgrounded, and
      reduced motion.
- [ ] Sound (if any) is redundant, short, silent-mode-aware, and centrally gated.
- [ ] Transitions respect reading direction; direction-neutral content surfaces are not re-mirrored.

## Related skills

- See `design-system-structure` for the motion tokens, curve slots, and the `resolveMotion` helper
  this skill spends — including the three animations Material mounts by default.
- See `custom-canvas-and-gestures` for driving canvas animation from an `AnimationController` as
  `repaint:` and for `RepaintBoundary` placement.
- See `ui-states-and-feedback` for the state a moment is feedback *about* — loading/empty/error
  rendering, the snackbar/banner/dialog ladder, Undo, and `SemanticsService.announce`.
- See `accessibility-as-code` for the color-alone rule this skill's motion-alone rule mirrors, and for
  reading platform accessibility flags.
- See `flutter-performance` for disposal, boundary budgeting, and profile-mode measurement of anything
  that feels heavy.
- See `i18n-rtl-l10n` for directional geometry under RTL.
- See `design-review-workflow` for the end-of-build pass where every declared moment is verified on
  video with reduced motion on and off.

## References

- Flutter API — `HapticFeedback`: https://api.flutter.dev/flutter/services/HapticFeedback-class.html
- Flutter API — `SystemSound`: https://api.flutter.dev/flutter/services/SystemSound-class.html
- Flutter API — `MediaQueryData.disableAnimations`: https://api.flutter.dev/flutter/widgets/MediaQueryData/disableAnimations.html
- Flutter — animations overview: https://docs.flutter.dev/ui/animations
- Material 3 — motion: https://m3.material.io/styles/motion/overview
- Apple HIG — playing haptics: https://developer.apple.com/design/human-interface-guidelines/playing-haptics
- WCAG 2.2 — Animation from Interactions (2.3.3): https://www.w3.org/WAI/WCAG22/Understanding/animation-from-interactions.html
