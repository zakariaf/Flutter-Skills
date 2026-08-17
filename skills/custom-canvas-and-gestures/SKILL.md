---
name: custom-canvas-and-gestures
description: Enforces CustomPainter/Canvas discipline — the View/Painter/Scene split with a dumb painter fed one immutable Scene value type, shouldRepaint as a single value compare kept strictly separate from the AnimationController-as-repaint animation path, one shared affine transform read by BOTH painter and hit-tester (toCanvas/toLogical exact inverses, never re-derive scale), geometry hit-testing (integer lattice or rasterized region-ID buffer, never Path.contains), zero-allocation paint(), gesture-as-pure-translator emitting a typed command to a Notifier (never mutating in the handler), ExcludeSemantics + sibling Semantics speaking display values with redundant non-colour encoding, measured TextPainter fitting, first-party RoundedSuperellipseBorder, physical-pixel hairlines, and Directional-only geometry. Use when writing or reviewing a CustomPainter/CustomPaint, gestures on a canvas, tap/drag hit-testing, canvas animation, measured text fitting, or Semantics over custom-drawn pixels.
---

# Custom Canvas & Gestures

Hand-painted surfaces (`CustomPainter`/`Canvas`) own every pixel, so they look byte-identical across platforms — but only if the painter stays dumb, the coordinate math is shared, and gestures translate rather than decide. This skill is the contract for that layer: how it splits, how pixels and pointers agree, and how a screen reader hears a canvas.

Read the reference for the task at hand:
- `references/painter-and-scene.md` — the View/Painter/Scene split, the shared transform, hit-testing by geometry class, zero-allocation `paint()`, the two-path repaint pitfall.
- `references/gestures-and-semantics.md` — gesture-as-translator, arena arbitration, clamp-not-collision drags, custom-canvas Semantics, action/gesture parity.
- `references/text-and-shapes.md` — measured `TextPainter` fitting, optical centring, `RoundedSuperellipseBorder`, physical-pixel hairlines, concentric radii, painter-over-image-asset.

Run `scripts/check_painter_hygiene.sh` and `scripts/analyze.sh` before a PR.

## Non-negotiable rules

1. **A canvas surface is three collaborators — a View, a Painter, and an immutable Scene — never one god-widget.** The View watches the ViewModel, builds an immutable `Scene` value type holding *everything the painter needs and nothing more*, and hands it to `CustomPaint`. The `Painter extends CustomPainter` is dumb: no `Notifier`, no `BuildContext`, no `DateTime`, no domain rules — it draws the Scene and never decides state. A dumb painter is testable and re-skinnable.

2. **`shouldRepaint` is one value compare — `old.scene != scene` — and nothing else.** Because `Scene` has value equality, this is both correct and cheap. `=> true` repaints every frame; a wrong `false` freezes the surface — both fail silently. Config-driven repaints go through `shouldRepaint`; per-frame animation goes through the `repaint:` `Listenable`. The two paths must never double-repaint.

3. **Exactly one affine transform maps logical space ↔ canvas pixels, read by BOTH the painter and the hit-tester.** Build it once per layout from the incoming `Size`; expose `toCanvas`/`toLogical` as exact inverses. The single most corrosive bug is a painter and hit-tester that disagree by a few pixels; a shared, tested transform forecloses it. The hit-tester **never re-derives scale from `size`** — it calls `transform.toLogical`.

4. **Hit-test by geometry class — integers for a lattice, a rasterized ID buffer for irregular regions — never `Path.contains` in the hot path.** A grid cell is `(x ~/ cell, y ~/ cell)`, one division per axis. An irregular region is resolved by indexing a `cell → RegionId` `Uint32List` rasterized **once at load**. O(1) and concavity-proof; testing a tap against N concave polygons every touch is not.

5. **Allocate nothing inside `paint()`.** Precompute every `Paint`, `Path`, and `Gradient` as painter fields and mutate `.color` per element rather than constructing. `Paint()`/`Path()` inside `paint()` is the classic jank source; reserve `saveLayer` for a real group opacity/blend, never a plain fill.

6. **Every animation is driven by an `AnimationController` passed as the painter's `repaint:` `Listenable` — never `setState`/`notifyListeners` in a ticker.** That repaints the painter directly without rebuilding the widget tree. Resolve the animation's duration through `design-system-structure`'s reduced-motion token / `resolveMotion` helper (it owns that rule — collapse to zero, not gentler); when motion is suppressed, cut straight to the end state rather than tweening. A state change must never rely on motion or hue as its *only* signal — carry a redundant non-colour channel (shape + label + haptic) per `accessibility-as-code`.

7. **A gesture handler is a pure translator: pointer → `localPosition` → shared transform → hit-test → typed immutable command → a ViewModel method. It mutates nothing.** Read `TapDownDetails.localPosition`/`DragUpdateDetails.localPosition` (never `globalPosition`), map through `transform.toLogical`, and call `ref.read(vmProvider.notifier).<command>(...)`. Wrap the `CustomPaint` in `HitTestBehavior.opaque` so the whole rect is live over transparent gaps.

8. **One verb, one recognizer; arbitrate collisions explicitly in the arena.** The primary verb owns a single recognizer; secondary verbs get separate recognizers. Where two can claim a pointer, resolve it via `RawGestureDetector` — do not hope. An axis-locked drag is a **clamp** (bounds snapshot at drag-start), not per-frame collision detection.

9. **Canonical in, display out — never convert units, format dates, or shape numerals inside `paint()`.** The painter receives values already converted to display units and formatted upstream; it maps numbers to pixels. Bucket/downsample large histories off-isolate via `Isolate.run`, keyed off a revision counter — never loop thousands of points in `paint()`.

10. **A custom-drawn surface is opaque to screen readers — author Semantics explicitly.** Either wrap the `CustomPaint` in `ExcludeSemantics` with a sibling `Semantics` node that speaks the **display value** (the answer, not the shape), or return `List<CustomPainterSemantics>` from `semanticsBuilder` for per-element nodes. Colour is never the only channel — the never-colour-alone rule is owned by `accessibility-as-code`. The a11y action commits the **same** command the gesture does.

11. **Geometry is direction-agnostic; only chrome mirrors.** Plotted data, a physical drag, a waveform have no handedness — never flip them for RTL. Legends, tooltips, axis placement, and label lead-edge mirror. Derive any sign from `Directionality.of(context)` and use `*Directional` insets — never a hard-coded `Offset(-x, y)`, `.left`, or `.right`.

12. **Isolate the surface behind a `RepaintBoundary`.** It gets its own compositor layer so a canvas tick does not repaint the surrounding chrome and vice versa. Set `isComplex`/`willChange` honestly. Do not blanket-wrap everything — each boundary costs GPU memory.

## View / Painter / Scene

The Scene is the painter's entire input, an immutable value type (`@freezed` or a hand-rolled `@immutable` with `==`/`hashCode`). Value equality is what makes `shouldRepaint` a cheap compare.

```dart
@immutable
class ChartScene {
  const ChartScene({required this.points, required this.transform, required this.phase});
  final List<Offset> points;        // logical space, already downsampled upstream
  final CanvasTransform transform;  // the ONE mapping (rule 3)
  final double phase;               // 0..1 animation value, or 0 when idle

  @override
  bool operator ==(Object other) =>
      other is ChartScene &&
      identical(other.points, points) &&   // Notifier hands a new list only on real change
      other.transform == transform &&
      other.phase == phase;
  @override
  int get hashCode => Object.hash(points.length, transform, phase);
}
```

The View watches the ViewModel (a Riverpod `Notifier`/`AsyncNotifier`), projects its state into the Scene, and never mutates state from inside the painter. See `state-management-riverpod` for the ViewModel spine.

## The shared transform

One uniform `scale` + centering `origin`; `toLogical` is the exact inverse of `toCanvas`. Both the painter and the hit-tester read it.

```dart
class CanvasTransform {
  const CanvasTransform({required this.scale, required this.origin});
  final double scale;   // logical unit -> px
  final Offset origin;  // top-left of the drawn rect within the canvas, in px

  Offset toCanvas(Offset logical) => origin + logical * scale;
  Offset toLogical(Offset canvasPx) => (canvasPx - origin) / scale; // exact inverse

  factory CanvasTransform.fit(Size size, Size logicalBounds) {
    final scale = math.min(size.width / logicalBounds.width,
                           size.height / logicalBounds.height);
    final drawn = logicalBounds * scale;
    return CanvasTransform(
      scale: scale,
      origin: Offset((size.width - drawn.width) / 2, (size.height - drawn.height) / 2),
    );
  }
}
```

## Hit-testing by geometry class

```dart
// Lattice: pure integers, one division per axis.
({int col, int row})? hitLattice(Offset p, int cols, int rows) {
  final c = p.dx.floor(), r = p.dy.floor();
  if (c < 0 || r < 0 || c >= cols || r >= rows) return null;
  return (col: c, row: r);
}

// Irregular regions: index a Uint32List rasterized ONCE at load — O(1), concavity-proof.
int? hitRegion(Offset p, RegionIdMap m) {
  final gx = (p.dx * m.cols / m.logicalWidth).floor();
  final gy = (p.dy * m.rows / m.logicalHeight).floor();
  if (gx < 0 || gy < 0 || gx >= m.cols || gy >= m.rows) return null;
  return m.ids[gy * m.cols + gx];
}
```

Build the buffer once by drawing each region in a unique id-colour into a `PictureRecorder` → `Picture.toImage` → `Image.toByteData`, read into a `Uint32List`, and cache it. Rebuild only on a genuine geometry change. Full recipe in `references/painter-and-scene.md`.

## Zero-allocation paint()

```dart
class ChartPainter extends CustomPainter {
  ChartPainter(this.scene, {required Listenable repaint}) : super(repaint: repaint);
  final ChartScene scene;

  // Paints are FIELDS — allocate nothing in paint() (rule 5).
  final Paint _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  @override
  void paint(Canvas canvas, Size size) {
    if (scene.points.length < 2) return; // empty state handled by the View, not here
    final t = scene.transform;           // the SAME transform the hit-tester inverts (rule 3)
    final first = t.toCanvas(scene.points.first);
    final path = Path()..moveTo(first.dx, first.dy);
    for (final p in scene.points.skip(1)) {
      final c = t.toCanvas(p);           // logical -> canvas px, mapped here in the painter
      path.lineTo(c.dx, c.dy);
    }
    canvas.drawPath(path, _line);
  }

  @override
  bool shouldRepaint(ChartPainter old) => old.scene != scene; // one value compare (rule 2)
}
```

## Gesture → typed command

```dart
class ChartView extends ConsumerWidget {
  const ChartView({required this.scene, super.key});
  final ChartScene scene;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vm = ref.read(chartNotifierProvider.notifier);
    return RepaintBoundary(                        // own compositor layer (rule 12)
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,          // whole rect is live (rule 7)
        onTapUp: (d) {
          final logical = scene.transform.toLogical(d.localPosition); // never globalPosition
          final hit = hitLattice(logical, scene.cols, scene.rows);
          if (hit != null) vm.select(hit.col, hit.row); // typed command; no mutation here
        },
        child: CustomPaint(
          painter: ChartPainter(scene, repaint: ref.watch(chartTickProvider)),
          isComplex: true,
          willChange: scene.phase != 0,
        ),
      ),
    );
  }
}
```

## Semantics over a canvas

```dart
// Simple case: the whole surface speaks one display value.
Semantics(
  label: 'Balance trending up, from 12 to 41 over the last 30 days', // the answer, display values
  child: ExcludeSemantics(                          // the painter itself says nothing
    child: RepaintBoundary(child: CustomPaint(painter: ChartPainter(scene, repaint: tick))),
  ),
)
```

For per-element nodes (each tappable), return `List<CustomPainterSemantics>` from `semanticsBuilder` and override `shouldRebuildSemantics` — see `references/gestures-and-semantics.md`. The a11y `onTap` must call the same command the gesture does.

## Measured text fitting

Scale text to a measured width with a linear `TextPainter` probe. Layout **unconstrained** — a constrained `layout()` wraps and `tp.width` then reports the constraint, silently returning the same size for every line.

```dart
double fitFontSize(String text, TextStyle style, double maxWidth,
    {double min = 12, double max = 96}) {
  const probe = 100.0;
  final tp = TextPainter(
    text: TextSpan(text: text, style: style.copyWith(fontSize: probe)),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(); // NO maxWidth — glyph advances scale linearly with fontSize
  return (probe * maxWidth / tp.width).clamp(min, max);
}
```

Set weight with `fontWeight` **only** — do not also pass `FontVariation('wght', …)`; `FontWeight` drives the axis and passing both conflicts. Fix optical centring metrically with `TextHeightBehavior(applyHeightToFirstAscent: false, applyHeightToLastDescent: false, leadingDistribution: TextLeadingDistribution.even)` — never a hardcoded pixel nudge, which breaks at 200% text scale. Never `FittedBox`/auto-shrink for content that must stay a uniform size. Details in `references/text-and-shapes.md`.

## Shapes & hairlines

- **Prefer a `CustomPainter` over an image asset** for repeated vector detail — it stays crisp at every DPR and theme. For many identical marks, draw them in one `Canvas` pass rather than N widgets.
- **First-party squircle:** `RoundedSuperellipseBorder` / `ClipRSuperellipse` / `Canvas.drawRSuperellipse` are first-party with an Impeller GPU path. Do not reach for `figma_squircle`/`smooth_corner`; `ContinuousRectangleBorder` is not an iOS-grade squircle.
- **A true hairline is one physical pixel:** `1.0 / MediaQuery.devicePixelRatioOf(context)` with `strokeAlign: BorderSide.strokeAlignInside`. `Border.all()` defaults to 1.0 *logical* px = ~3 physical px on a modern phone — a table border, not a hairline.
- **Nested corners are concentric by construction:** `inner = outer - padding`, computed, never a second constant that drifts.

## Anti-patterns

- `shouldRepaint(_) => true`, or a `shouldRepaint` that deep-walks mutable objects — the Scene is a value type; compare it (rule 2).
- A god widget that holds state, reads `ref` inside `paint()`, or decides a rule in the painter — the painter is dumb (rule 1).
- A hit-tester that re-derives `scale` from `size`, or math off `globalPosition` — always `transform.toLogical(localPosition)` (rules 3, 7).
- `Path.contains(tap)` in the touch path, or re-rasterizing the ID buffer per tap/frame — it is geometry-stable (rule 4).
- `Paint()`/`Path()` allocated inside `paint()` (when hoistable), a per-frame `ui.Gradient`, or `saveLayer` for a plain fill (rule 5).
- Animating by `setState`/`notifyListeners` every ticker frame — pass the controller as `repaint:` instead (rule 6).
- An un-skippable animation, or motion/hue as the *only* signal for a state change (rule 6).
- Converting units / formatting dates / shaping numerals inside `paint()`, or looping raw history there — do it upstream, off-isolate (rule 9).
- One opaque `Semantics(label: 'chart')` that describes the shape instead of the value, or no `ExcludeSemantics` on the decorative painter (rule 10).
- A hard-coded `Offset(-x, y)`, `.left`/`.right`, or `Alignment.centerRight` in a painter — derive from `Directionality.of(context)` (rule 11).
- `FittedBox`/auto-shrink where uniform sizing is required; a constrained `TextPainter.layout()` in a fitter (measured-fit section).
- `Border.all()` for a hairline; `ContinuousRectangleBorder`/third-party squircle packages (shapes section).
- A `CustomPaint` with no `RepaintBoundary`, or blanket boundaries everywhere (rule 12).

## Definition of done

- [ ] The surface is a View + a `Painter extends CustomPainter` + an immutable `Scene`; the painter holds no `Notifier`/`BuildContext`/`DateTime`/rule (rule 1).
- [ ] `shouldRepaint` returns `old.scene != scene` only; per-frame animation flows through `repaint:`, not `shouldRepaint` (rules 2, 6).
- [ ] Exactly one transform is built per layout and read by both painter and hit-tester; `toLogical`/`toCanvas` are exact inverses; the hit-tester never re-derives scale (rule 3).
- [ ] Hit-testing uses integer lattice math or a `Uint32List` region-ID buffer rasterized once; no `Path.contains` in the hot path; no target below ~44 pt (rules 4, 7).
- [ ] `paint()` allocates nothing hoistable — `Paint`/`Path`/`Gradient` are fields, `.color` mutated per element, `saveLayer` only for a real group blend (rule 5).
- [ ] Animation is driven by an `AnimationController` as `repaint:`; motion is resolved through `design-system-structure`'s `resolveMotion` (cut to end state when suppressed); no state change relies on hue or motion alone (rule 6).
- [ ] Gesture handlers translate `localPosition` → transform → hit-test → typed command → ViewModel method and mutate nothing; the `CustomPaint` is under `HitTestBehavior.opaque` (rule 7).
- [ ] One recognizer per verb; arena collisions resolved via `RawGestureDetector`; axis-locked drags clamp to a drag-start bound (rule 8).
- [ ] `paint()` receives canonical→display values formatted upstream; large histories are downsampled off-isolate keyed on a revision (rule 9).
- [ ] The painter is `ExcludeSemantics`, and a sibling `Semantics`/`semanticsBuilder` speaks display values with a redundant non-colour channel; the a11y action equals the gesture command (rule 10).
- [ ] No hard-coded directional sign in any painter; geometry is direction-agnostic, chrome mirrors from `Directionality.of(context)` (rule 11).
- [ ] The surface sits under a `RepaintBoundary`; `isComplex`/`willChange` set honestly (rule 12).
- [ ] `scripts/check_painter_hygiene.sh` and `scripts/analyze.sh` pass.

## Related skills

- See `state-management-riverpod` for the `Notifier`/`AsyncNotifier` ViewModel the View watches and the commands gestures call.
- See `widget-composition` for the small-const-widget composition the View lives inside and controller disposal.
- See `flutter-performance` for `.select` rebuild scoping, `RepaintBoundary` budgeting, and off-isolate work.
- See `design-system-structure` for the theme colours, hairline/shape, and reduced-motion tokens the View snapshots at the widget layer and passes into painter/Scene fields — the painter never reads `BuildContext`. It owns the `resolveMotion` reduced-motion helper this skill's animation path defers to.
- See `accessibility-as-code` for the never-colour-alone, MediaQuery-a11y-flag, redundant-channel, 44px-target, and `sortKey` rules the Semantics here obey.
- See `i18n-rtl-l10n` for the canonical-store + localize-at-render contract that feeds display values into `paint()`.
- See `motion-and-haptics` for what animation on this surface commits to: one haptic per committed gesture, interruptibility, and the declared reduced-motion end state.
- See `widget-golden-and-a11y-testing` for pinning the painted surface with a golden on real fonts.

## References

- Flutter API — `CustomPainter` (`paint`, `shouldRepaint`, `semanticsBuilder`, `repaint`): https://api.flutter.dev/flutter/rendering/CustomPainter-class.html
- Flutter API — `CustomPaint` (`isComplex`, `willChange`, `foregroundPainter`): https://api.flutter.dev/flutter/widgets/CustomPaint-class.html
- Flutter API — `Canvas`: https://api.flutter.dev/flutter/dart-ui/Canvas-class.html
- Flutter API — `PictureRecorder` / `Picture.toImage` (rasterize-once ID buffer): https://api.flutter.dev/flutter/dart-ui/PictureRecorder-class.html
- Flutter — Taps, drags, and other gestures (arena, `localPosition`): https://docs.flutter.dev/ui/interactivity/gestures
- Flutter — Performance best practices (`RepaintBoundary`, `saveLayer`): https://docs.flutter.dev/perf/best-practices
- Flutter API — `RoundedSuperellipseBorder`: https://api.flutter.dev/flutter/painting/RoundedSuperellipseBorder-class.html
- Flutter API — `TextPainter`: https://api.flutter.dev/flutter/painting/TextPainter-class.html
- Flutter — Accessibility & Semantics (`CustomPainterSemantics`): https://docs.flutter.dev/ui/accessibility-and-internationalization/accessibility
- W3C — WCAG 2.2 §1.4.1 Use of Color: https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html
