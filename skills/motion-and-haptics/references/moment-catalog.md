# The moment catalog

Six moments cover almost every app. Design each one *once*, deliberately, and reuse it — that
consistency is most of what "feels designed" means. An app that specifies all six and an app that
specifies none use the same amount of code; only one of them chose.

## 1. Press acknowledgment

**Trigger:** pointer down, before anything async happens.
**Design:** a transform, elevation, or fill change that is visible within the same frame. It must
appear on *down*, not on *up* — waiting for the tap to complete makes a fast tap feel like a miss.
**Haptic:** at most a selection-level tick, and only for controls where selection is the meaning
(pickers, toggles, cells). A haptic on every button press is noise.
**Reduced motion:** the state swaps instantly. Never remove the press state itself — it is
information, not decoration.

## 2. Rejection

**Trigger:** input the app cannot accept.
**Design:** bounded, brief, and **interruptible by the next input** — the user is already correcting.
Pair it with the message that says *why*; motion alone never explains a rejection.
**Haptic:** the lightest slot that registers. Never `heavyImpact`: escalating intensity punishes a
mistake the interface could usually have prevented.
**Reduced motion:** the message, without the shake. The message was always the payload.

## 3. Commit

**Trigger:** state actually changed.
**Design:** the app's single biggest feedback investment, because it is the moment the user's
intention became real. Decide where it originates (the touch point, the affected element) and what it
reveals. Visual, haptic, and sound all fire **synchronized from the one commit frame** — a haptic
scheduled from an animation callback drifts away from its own visual by a frame or more.
**Reduced motion:** the end state appears instantly, carrying the same information.

## 4. Success

**Trigger:** a task completed.
**Design:** on a budget. Bounded element count, originating from the point of action rather than the
screen edges, resolving to the next interactive state quickly, **tap-to-skip**, played once. Failure
gets acknowledgment at the same level *without* shaming motion — the user knows.
**Haptic:** the app's strongest routine slot; reserve the heaviest for a genuine milestone.
**Reduced motion:** the result appears already complete; the flourish is omitted entirely rather than
shortened.

## 5. Increment

**Trigger:** a counter, streak, score, or progress value advances.
**Design:** one emphasis pulse on change, and a **static** element at rest. An ambient loop on a
progress ornament is a battery drain and a distraction; if the design wants one, it obeys rule 11's
stop conditions. Never use motion to create pressure (a "hurry up" pulse near a deadline) — that is
anxiety, not feedback.
**Reduced motion:** the new value, no pulse.

## 6. Transition

**Trigger:** route change.
**Design:** one signature transition used consistently. Horizontal pushes follow reading direction and
flip under RTL; vertical sheets do not. A direction-neutral content surface (canvas, chart, media)
is not re-mirrored by the transition.
**Haptic:** normally none — navigation is not an event that needs confirming.
**Reduced motion:** cross-fade, or nothing.

## Calibration starting points, not a mandate

Duration *values* are tokens owned by `design-system-structure`. If you are choosing them from
scratch, these ranges are where most apps land, and the **ordering matters far more than the
numbers**:

```
press/flash    60–140 ms     immediate acknowledgment
quick         140–250 ms     small state change
move          200–350 ms     an element travels
reveal        280–450 ms     new information appears
celebrate     500–1200 ms    a bounded success moment
transition    220–400 ms     route change
```

Keep `press < quick < move ≤ reveal`, and keep nothing on the retry loop (input → response → retry)
longer than `move` — that loop is the one users repeat dozens of times, and every extra 100 ms is
paid over and over. A calmer or snappier identity moves the whole scale; it does not invert it.

## Verifying a moment

A moment is not done because the code runs. In the end-of-build pass (`design-review-workflow`):

- record it as **video**, not a screenshot — skippability and the reduced-motion end state are only
  judgeable in motion;
- record it twice, reduced motion off and on;
- tap mid-animation on purpose and confirm it resolves to the end state;
- confirm one haptic per event by feel on a real device — emulators do not reproduce this at all.
