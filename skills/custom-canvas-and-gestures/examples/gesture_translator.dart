// Demonstrates the gesture-as-pure-translator pattern: a RawGestureDetector with one recognizer per
// verb, an axis-locked drag implemented as a clamp (bounds snapshot at drag-start, never per-frame
// collision detection), localPosition mapped through the shared transform, and a typed immutable
// command emitted to a ViewModel on commit only (a return-to-origin drag emits nothing). The live
// drag preview is the only setState; domain state changes go through the command. Generic domain:
// dragging an Item along a track. Conceptually compiles against flutter.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

// The one shared transform (see scene_painter.dart for the full version).
class CanvasTransform {
  const CanvasTransform({required this.scale, required this.origin});
  final double scale;
  final Offset origin;
  Offset toLogical(Offset canvasPx) => (canvasPx - origin) / scale;
}

// A typed, immutable command — the intent, not a mutation.
@immutable
class MoveItem {
  const MoveItem({required this.itemId, required this.cells});
  final int itemId;
  final int cells; // signed number of cells moved; always != 0 when emitted
}

class ItemTrackView extends StatefulWidget {
  const ItemTrackView({
    required this.transform,
    required this.itemIdAt,
    required this.freeRangePx,
    required this.onMove,
    super.key,
  });

  final CanvasTransform transform;
  final int? Function(Offset logical) itemIdAt; // hit-test: item under a logical point, or null
  final ({double min, double max}) Function(int itemId) freeRangePx; // clamp bounds excl. this item
  final void Function(MoveItem command) onMove; // → ViewModel command (one per committed move)

  @override
  State<ItemTrackView> createState() => _ItemTrackViewState();
}

class _ItemTrackViewState extends State<ItemTrackView> {
  int? _itemId; // captured on drag-start
  double _minPx = 0, _maxPx = 0, _livePx = 0; // clamp bounds + live preview offset

  void _onStart(DragStartDetails d) {
    final logical = widget.transform.toLogical(d.localPosition); // never globalPosition
    final id = widget.itemIdAt(logical);
    if (id == null) return; // empty grab: nothing happens
    // Clamp is a BOUND computed once at drag-start — never per-frame collision detection.
    final range = widget.freeRangePx(id);
    setState(() {
      _itemId = id;
      _minPx = range.min;
      _maxPx = range.max;
      _livePx = 0;
    });
  }

  void _onUpdate(DragUpdateDetails d) {
    if (_itemId == null) return;
    setState(() {
      // Project onto the track axis (horizontal here); clamp so overlap is impossible.
      _livePx = (_livePx + d.delta.dx).clamp(_minPx, _maxPx);
    });
  }

  void _onEnd(DragEndDetails _) {
    final id = _itemId;
    setState(() => _itemId = null);
    if (id == null) return;
    final cells = (_livePx / widget.transform.scale).round(); // snap to nearest cell
    if (cells == 0) return; // returned to origin = no command (zero-cost)
    widget.onMove(MoveItem(itemId: id, cells: cells)); // emit ONE typed command on commit
  }

  @override
  Widget build(BuildContext context) {
    // One recognizer for the drag verb; a separate verb (e.g. tap-to-select) would be its own entry
    // and the arena would arbitrate. HitTestBehavior.opaque makes the whole rect live.
    return RawGestureDetector(
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
      child: CustomPaint(
        // The painter reads _livePx as a transient DRAG PREVIEW only; committed state lives in the VM.
        painter: _TrackPainter(liveDragPx: _livePx, draggingId: _itemId),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _TrackPainter extends CustomPainter {
  _TrackPainter({required this.liveDragPx, required this.draggingId});
  final double liveDragPx;
  final int? draggingId;

  @override
  void paint(Canvas canvas, Size size) {
    // Draw the track and items; offset the dragged item by liveDragPx. Geometry omitted for brevity.
  }

  @override
  bool shouldRepaint(_TrackPainter old) =>
      old.liveDragPx != liveDragPx || old.draggingId != draggingId; // never => true
}
