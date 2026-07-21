// Demonstrates the View / Painter / Scene split: an immutable Scene value type feeding a dumb
// CustomPainter whose shouldRepaint is one value compare, a shared affine transform read by both
// paint() and the hit-tester, zero-allocation paint() with Paint fields, a controller-as-repaint
// animation path kept separate from shouldRepaint, ExcludeSemantics + a sibling Semantics node
// speaking display values, and RepaintBoundary isolation. Generic domain: a sparkline of Account
// balances. Conceptually compiles against flutter + flutter_riverpod.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── The ONE transform: shared by pixels AND pointers; toLogical is the exact inverse of toCanvas. ──
class CanvasTransform {
  const CanvasTransform({required this.scale, required this.origin});
  final double scale; // logical unit -> px
  final Offset origin; // top-left of the drawn rect within the canvas, in px

  Offset toCanvas(Offset logical) => origin + logical * scale;
  Offset toLogical(Offset canvasPx) => (canvasPx - origin) / scale;

  factory CanvasTransform.fit(Size size, Size logicalBounds) {
    final scale = math.min(
      size.width / logicalBounds.width,
      size.height / logicalBounds.height,
    );
    final drawn = logicalBounds * scale;
    return CanvasTransform(
      scale: scale,
      origin: Offset(
        (size.width - drawn.width) / 2,
        (size.height - drawn.height) / 2,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CanvasTransform && other.scale == scale && other.origin == origin;
  @override
  int get hashCode => Object.hash(scale, origin);
}

// ── Domain state owned by the ViewModel: canonical values only, no display concerns. ──
@immutable
class SparklineState {
  const SparklineState({required this.points, required this.selected});

  final List<Offset> points; // logical space, already downsampled + unit-converted upstream
  final int? selected; // index of the highlighted point, or null

  @override
  bool operator ==(Object other) =>
      other is SparklineState &&
      identical(other.points, points) && // new list only on real change
      other.selected == selected;
  @override
  int get hashCode => Object.hash(points.length, selected);
}

// ── The Scene: the painter's ENTIRE input, an immutable value type (drives shouldRepaint). ──
@immutable
class SparklineScene {
  const SparklineScene({
    required this.points,
    required this.transform,
    required this.selected,
    required this.color,
  });

  final List<Offset> points; // logical space — the painter maps to pixels via transform (rule 3)
  final CanvasTransform transform;
  final int? selected; // index of the highlighted point, or null
  final Color color; // theme-resolved upstream in the View — canonical in, display out (rule 9)

  @override
  bool operator ==(Object other) =>
      other is SparklineScene &&
      identical(other.points, points) && // new list only on real change
      other.transform == transform &&
      other.selected == selected &&
      other.color == color;
  @override
  int get hashCode => Object.hash(points.length, transform, selected, color);
}

// ── The dumb Painter: draws the Scene, compares scenes; no Notifier / BuildContext / rules. ──
class SparklinePainter extends CustomPainter {
  SparklinePainter(this.scene, {required Listenable repaint}) : super(repaint: repaint);
  final SparklineScene scene;

  // Paints are FIELDS — allocate nothing inside paint(); colour is mutated per element, not baked in.
  final Paint _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;
  final Paint _dot = Paint()..style = PaintingStyle.fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (scene.points.length < 2) return; // empty state handled by the View, not here
    final t = scene.transform; // the ONE shared transform, read here AND by the hit-tester (rule 3)
    _line.color = scene.color; // theme value arrives on the Scene — mutate, don't allocate
    final first = t.toCanvas(scene.points.first);
    final path = Path()..moveTo(first.dx, first.dy);
    for (final p in scene.points.skip(1)) {
      final c = t.toCanvas(p); // logical -> canvas px, the same mapping the hit-tester inverts
      path.lineTo(c.dx, c.dy);
    }
    canvas.drawPath(path, _line);
    final sel = scene.selected;
    if (sel != null && sel >= 0 && sel < scene.points.length) {
      _dot.color = scene.color;
      canvas.drawCircle(t.toCanvas(scene.points[sel]), 4.5, _dot); // redundant, non-colour highlight cue
    }
  }

  @override
  bool shouldRepaint(SparklinePainter old) => old.scene != scene; // one value compare
}

// ── The hit-tester: reads the SAME transform; never re-derives scale. ──
int? nearestPointIndex(Offset canvasPx, SparklineScene scene) {
  if (scene.points.isEmpty) return null;
  final logical = scene.transform.toLogical(canvasPx);
  var best = 0;
  var bestDx = (scene.points.first.dx - logical.dx).abs();
  for (var i = 1; i < scene.points.length; i++) {
    final dx = (scene.points[i].dx - logical.dx).abs();
    if (dx < bestDx) {
      bestDx = dx;
      best = i;
    }
  }
  return best;
}

// ── The ViewModel is a Riverpod Notifier named <Feature>Notifier: owns canonical state; the painter never mutates it. ──
class SparklineNotifier extends Notifier<SparklineState> {
  @override
  SparklineState build() => const SparklineState(
        points: [Offset(0, 8), Offset(1, 4), Offset(2, 6), Offset(3, 1)],
        selected: null,
      );

  void select(int index) =>
      state = SparklineState(points: state.points, selected: index);
}

final sparklineNotifierProvider =
    NotifierProvider<SparklineNotifier, SparklineState>(SparklineNotifier.new);

// A no-op repaint source stands in for an AnimationController (the animation path).
final tickProvider = Provider<Listenable>((ref) => const AlwaysStoppedAnimation(0));

// ── The View: watches the ViewModel, isolates repaints, translates the gesture into a command. ──
class SparklineView extends ConsumerWidget {
  const SparklineView({required this.semanticsLabel, super.key});
  final String semanticsLabel; // the ANSWER in display values, formatted upstream

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(sparklineNotifierProvider);
    final vm = ref.read(sparklineNotifierProvider.notifier);
    final lineColor = Theme.of(context).colorScheme.primary; // theme-resolved once, passed down

    return Semantics(
      label: semanticsLabel, // speaks the value, not the shape
      child: ExcludeSemantics(
        child: RepaintBoundary(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Build the ONE transform for this layout; the View owns it, painter + hit-tester read it.
              final transform = CanvasTransform.fit(constraints.biggest, const Size(3, 8));
              final fitted = SparklineScene(
                points: data.points, // stay in logical space — the painter maps via the transform
                transform: transform,
                selected: data.selected,
                color: lineColor,
              );
              return GestureDetector(
                behavior: HitTestBehavior.opaque, // whole rect is live over gaps
                onTapUp: (d) {
                  final i = nearestPointIndex(d.localPosition, fitted); // never globalPosition
                  if (i != null) vm.select(i); // typed command; no mutation here
                },
                child: CustomPaint(
                  painter: SparklinePainter(fitted, repaint: ref.watch(tickProvider)),
                  isComplex: true,
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
