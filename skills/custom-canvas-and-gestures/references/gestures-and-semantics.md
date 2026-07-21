# Gestures & Semantics over a canvas — deep dive

The input half of the skill: how raw pointer events become typed commands, how to arbitrate
recognizers, and how a screen reader hears pixels it cannot see.

## The gesture is a pure translator

The gesture layer is the one place a raw pointer becomes a domain intent. It is a *pure translator*
and decides nothing:

```
pointer event → localPosition → transform.toLogical → hit-test → typed immutable command → ViewModel method
```

It never mutates state, never counts, never declares a rule satisfied — the ViewModel/domain owns
those. Get this wrong and taps land a cell off, two recognizers double-fire one intent, or an
accessibility path diverges from the gesture path.

Rules:
- Read `TapDownDetails.localPosition` / `DragUpdateDetails.localPosition` — never `globalPosition`,
  never re-derive `scale` from `size`.
- Wrap the `CustomPaint` in `HitTestBehavior.opaque` so the whole rect is live over transparent gaps.
- Build a typed immutable command value and call `ref.read(vmProvider.notifier).<command>(cmd)`.
- Feedback (haptic/sound) fires **once, on commit**, from the ViewModel/animation layer — never from
  `onUpdate` per-frame math.

## One verb, one recognizer

The primary verb owns a single, deliberately chosen recognizer. Secondary verbs get *separate*
recognizers. Never stack two verbs on one recognizer — it reintroduces gesture-disambiguation latency
and cross-fires.

Where two recognizers can both claim a pointer, resolve it **explicitly** in the gesture arena via
`RawGestureDetector` — do not hope the defaults win:

```dart
RawGestureDetector(
  behavior: HitTestBehavior.opaque,
  gestures: <Type, GestureRecognizerFactory>{
    PanGestureRecognizer: GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
      PanGestureRecognizer.new,
      (r) => r
        ..onStart = _onStart
        ..onUpdate = _onUpdate
        ..onEnd = _onEnd,
    ),
  },
  child: CustomPaint(painter: painter),
)
```

On a zoomable surface, disambiguate by pointer count: one finger draws/slides, two fingers pan/zoom.
Coalesce rapid taps so a burst animates as one continuous motion.

## Axis-locked drag is a clamp, not collision detection

Compute the movement bound **once at drag-start**, then clamp every frame — never run per-frame
overlap detection:

1. On drag-start, snapshot occupancy *excluding the dragged element* and scan to the first blocker to
   get `[minPx, maxPx]`.
2. Project the delta onto the element's axis, discard the cross component.
3. `live = (live + along).clamp(minPx, maxPx)` — overlap is now structurally impossible.
4. Snap to the nearest cell on release. A drag that returns to origin commits **nothing**; one
   committed move of any distance is **one** command.

The live drag preview is the *only* legitimate `setState` in this layer — it moves a preview offset,
not domain state. Animation still goes through the controller-as-`repaint` path.

## Semantics over a custom-drawn surface

A canvas is opaque to TalkBack/VoiceOver — you must author the semantics. Two shapes:

### Whole-surface node (a chart, a vital)

The painter is decorative; a sibling `Semantics` node speaks the **answer** in display values:

```dart
Semantics(
  label: 'Spend by category: Groceries 120, Transport 80, Other 40',
  child: ExcludeSemantics(                 // the painter says nothing
    child: RepaintBoundary(child: CustomPaint(painter: BarPainter(scene, repaint: tick))),
  ),
)
```

- Speak the **value**, not the shape ("trending 12 to 41", not "an upward line").
- Add `liveRegion: true` for a value that updates and should be announced.
- Colour is never the only channel (rule owned by `accessibility-as-code`): pair every categorical
  encoding with a direct text label and a redundant non-colour cue (a hatch/pattern on the
  highlighted element).

### Per-element nodes (each tappable)

Return `List<CustomPainterSemantics>` from `semanticsBuilder`, gated by `shouldRebuildSemantics`:

```dart
@override
SemanticsBuilderCallback get semanticsBuilder => (size) => [
  for (final e in scene.elements)
    CustomPainterSemantics(
      rect: scene.transform.toCanvas(e.center) & const Size(48, 48), // >= 44 pt
      properties: SemanticsProperties(
        label: e.a11yLabel,   // localized fragments, includes state — not English concatenation
        button: true,
        onTap: e.onActivate,  // the SAME command the gesture emits (parity)
      ),
    ),
];

@override
bool shouldRebuildSemantics(BarPainter old) => old.scene.elements != scene.elements;
```

## Action / gesture parity

The accessibility action path and the gesture path must produce the **same** command, and stay
strictly separate so one intent never double-fires:
- A preview/adjust action costs zero commits; the activation commits exactly one command regardless of
  span.
- Give each node a `sortKey: OrdinalSortKey(...)` authored from priority when default row-major
  traversal would bury the important action — see `accessibility-as-code`.
- Announce the result with `SemanticsService.announce(localizedResult, TextDirection.ltr)` after a
  committed move, and keep focus on the acted element.

## RTL

Geometry is direction-agnostic — a physical drag, a plotted trend, a waveform have no handedness and
must **never** flip for RTL. Only chrome mirrors: legends, tooltips, axis placement, label lead-edge,
time-axis direction. Derive any sign from `Directionality.of(context)` and use `*Directional` insets;
a hard-coded `Offset(-x, y)`, `.left`, or `.right` is an RTL bug. See `i18n-rtl-l10n`.
