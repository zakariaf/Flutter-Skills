# Painter, Scene, transform & hit-testing — deep dive

The rendering half of the skill: how the surface splits, why the transform is shared, how to
hit-test without polygon math, and how to keep `paint()` allocation-free.

## The View / Painter / Scene split

Three collaborators, never one widget:

| Collaborator | Responsibility | Forbidden to hold |
|---|---|---|
| **View** (`ConsumerWidget`) | watches the ViewModel, projects state into an immutable `Scene`, wires gestures, isolates repaints | `paint()` logic |
| **Painter** (`extends CustomPainter`) | maps the Scene to pixels; compares scenes; synthesises Semantics | `Notifier`, `BuildContext`, `DateTime`, domain rules |
| **Scene** (immutable value type) | the painter's *entire* input — everything it needs, nothing more | mutable fields, live objects |

Why the split earns its keep:
- **Testability.** A dumb painter is a pure function of the Scene; you golden-test it by constructing a Scene, no app wiring.
- **Re-skinnable.** The same logical state can be drawn one way today, another tomorrow, with zero ViewModel change.
- **Cheap `shouldRepaint`.** Splitting the input into one value type is what makes equality a single compare.

## The two-path repaint pitfall

A painter has **two** independent triggers, and conflating them is the classic bug:

1. **Config path — `shouldRepaint(old) => old.scene != scene`.** Fires when the widget rebuilds with a new Scene (a selection changed, data arrived). One value compare.
2. **Animation path — `CustomPainter(repaint: controller)`.** The `AnimationController` (a `Listenable`) repaints the painter directly *without rebuilding the widget tree* on every ticker frame.

Rules that keep them from fighting:
- `=> true` repaints every frame even when idle — wasteful and it hides the real trigger. A wrong `false` freezes a genuine change.
- Do **not** put animation values inside the Scene *and* drive them through `repaint:` — you double-repaint. Pick one: put the current phase in the Scene (rebuild per frame — expensive, avoid), or drive phase through the controller and read `controller.value` in `paint()` (preferred).
- The preferred shape: the Scene carries a *static* description; the controller carries the *motion*. `shouldRepaint` compares the static Scene; the controller repaints for motion.

## The one shared transform

A uniform `scale` plus a centering `origin` translate — an affine mapping invertible both ways.
Build it **once per layout** from the incoming `Size` (inside `paint()` you receive `size`; for the
hit-tester store it on the Scene).

```dart
class CanvasTransform {
  const CanvasTransform({required this.scale, required this.origin});
  final double scale;
  final Offset origin;
  Offset toCanvas(Offset logical) => origin + logical * scale;
  Offset toLogical(Offset canvasPx) => (canvasPx - origin) / scale;
}
```

Invariant to test: `t.toLogical(t.toCanvas(p))` returns `p` (within float epsilon) for any `p`. A unit
test on that inverse is the cheapest insurance against the "taps land one cell off" bug — the single
most corrosive defect in a hand-painted surface. The hit-tester **must** call `toLogical`; it must never
re-derive `scale` from `size`, because a second derivation drifts from the first.

## Hit-testing by geometry class

Never call `Path.contains(tap)` in the touch path, and never re-rasterize per tap or per frame.

### Lattice (regular grid)

Pure integer math — one floor per axis, O(1):

```dart
({int col, int row})? hitLattice(Offset p, int cols, int rows) {
  final c = p.dx.floor(), r = p.dy.floor();
  if (c < 0 || r < 0 || c >= cols || r >= rows) return null;
  return (col: c, row: r);
}
```

### Irregular regions (rasterized ID buffer)

Rasterize each region in a unique id-colour **once at load**, read the pixels into a `Uint32List`,
and index it per tap. Concavity-proof and O(1).

```dart
Future<Uint32List> rasterizeIdBuffer(List<RegionShape> regions, int w, int h) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()..style = PaintingStyle.fill;
  for (final r in regions) {
    paint.color = Color(0xFF000000 | r.id); // encode the id in the pixel value
    canvas.drawPath(r.path, paint);
  }
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint32List(); // cache it; index per tap
}

int? hitRegion(Offset p, RegionIdMap m) {
  final gx = (p.dx * m.cols / m.logicalWidth).floor();
  final gy = (p.dy * m.rows / m.logicalHeight).floor();
  if (gx < 0 || gy < 0 || gx >= m.cols || gy >= m.rows) return null;
  return m.ids[gy * m.cols + gx];
}
```

Rebuild the buffer only on a genuine geometry change (a resize, a merge) — cache it on a geometry
value type alongside the cached `Path`s. Keep every hit target ≥ ~44 pt even when the painted mark is
smaller; the hit rect is not the painted shape.

## Zero-allocation paint()

`paint()` runs on the raster path; allocations there churn the GC and cause jank.

- Hoist every `Paint`, and any `Path`/`Gradient`/`Shader` that is **geometry-stable**, to painter
  fields. Mutate `.color` per element rather than constructing a new `Paint`.
- A `Path` that depends only on layout (a seam union, an axis frame) is built once when geometry
  changes, not per frame. A `Path` that depends on the animated phase is unavoidably per-frame — keep
  it minimal.
- Stroke many like elements in **one** `drawPath` call over a combined `Path` rather than N calls.
- Reserve `canvas.saveLayer` for a genuine group opacity or blend; a plain fill never needs it, and
  each `saveLayer` allocates an offscreen buffer.
- Set `isComplex: true` to hint caching for a static, expensive surface; set `willChange: true` only
  while it is actually animating — an honest hint, not a blanket one.

## Canonical in, display out

`paint()` maps numbers to pixels and nothing else. Unit conversion, date formatting, and numeral
shaping happen **upstream** (in the ViewModel/repository) so the painter receives display-ready
values. Memoize formatted axis labels keyed by `(value, locale)` — reformatting per frame is
expensive. Bucket/downsample large histories off the UI isolate:

```dart
// In the Notifier/repository, NOT in paint():
final points = await Isolate.run(() => downsample(rawRows, bucket)); // plain in, plain out
```

Recompute only when a revision counter changes; the painter gets the finished, projected list.

## Off-screen and multi-package notes

- **In a single-package app:** shared painter primitives (`CanvasTransform`, hit-testers, base Scene
  types) are pure foundation — they live under `lib/core/` (e.g. `lib/core/canvas/`), never a feature
  reaching sideways into another feature's painter. The app package does **not** use `lib/src/`. See
  `project-structure-and-packages` for the canonical tree.
- **When multi-package (workspace):** the same primitives belong in a foundation UI package that
  features depend on downward, exported via that package's `lib/src/` + one barrel; the same
  downward-only rule applies. `project-structure-and-packages` owns the package convention.
