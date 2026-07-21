#!/usr/bin/env bash
# Heuristic hygiene scan for CustomPainter / canvas / gesture code.
# Usage: scripts/check_painter_hygiene.sh [TARGET_DIR]   (default: lib/)
# Exits non-zero on a hard violation; WARN lines never fail the build (eyeball them).
set -euo pipefail

TARGET="${1:-lib}"
if [ ! -d "$TARGET" ]; then
  echo "note — target dir '$TARGET' not found; nothing to scan"
  exit 0
fi

darts=$(find "$TARGET" -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' 2>/dev/null || true)
if [ -z "$darts" ]; then
  echo "note — no .dart files under '$TARGET'"
  exit 0
fi

status=0

# Files that declare a CustomPainter — the scope for the hard painter rules.
painters=$(grep -lE 'extends CustomPainter' $darts 2>/dev/null || true)

if [ -n "$painters" ]; then
  echo "== scanning CustomPainter subclasses =="

  # 1. shouldRepaint(...) => true / returns true — repaints every frame. Hard fail.
  hits=$(grep -HnE 'shouldRepaint\([^)]*\)\s*(=>\s*true|\{[^}]*return\s+true)' $painters 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "FAIL — shouldRepaint returns true (repaints every frame):"; echo "$hits"; status=1
  else echo "ok — no shouldRepaint => true"; fi

  # 2. Hard-coded directional constructs inside a painter — RTL bug. Hard fail.
  # Only the actually-directional forms; bare .left/.right are omitted because they cannot be
  # distinguished by grep from legitimate Rect.left/bounds.right geometry reads.
  hits=$(grep -HnE 'Alignment\.(centerRight|centerLeft|topRight|topLeft|bottomRight|bottomLeft)|EdgeInsets\.only\((left|right):' $painters 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "FAIL — hard-coded directional Alignment/EdgeInsets in a painter (use Directionality / *Directional):"; echo "$hits"; status=1
  else echo "ok — no hard-coded directional Alignment/EdgeInsets in painters"; fi

  # 3. Path.contains inside a painter/hit path — polygon math in the hot path. Hard fail.
  hits=$(grep -HnE '\.contains\(' $painters 2>/dev/null | grep -iE 'path|region' || true)
  if [ -n "$hits" ]; then
    echo "FAIL — Path.contains in painter/hit code (index a rasterized ID buffer instead):"; echo "$hits"; status=1
  else echo "ok — no Path.contains in painters"; fi
fi

# 4. globalPosition in gesture handlers — should be localPosition through the shared transform. Hard fail.
gestures=$(grep -lE 'GestureDetector|RawGestureDetector|onTapUp|onTapDown|onPanUpdate|DragUpdateDetails' $darts 2>/dev/null || true)
if [ -n "$gestures" ]; then
  hits=$(grep -HnE '\.globalPosition' $gestures 2>/dev/null || true)
  if [ -n "$hits" ]; then
    echo "FAIL — globalPosition in a gesture handler (use localPosition + transform.toLogical):"; echo "$hits"; status=1
  else echo "ok — no globalPosition in gesture handlers"; fi
fi

# 5. Third-party squircle packages — first-party RoundedSuperellipse exists. Hard fail.
hits=$(grep -HnE "import .*(figma_squircle|smooth_corner)" $darts 2>/dev/null || true)
if [ -n "$hits" ]; then
  echo "FAIL — third-party squircle package (use RoundedSuperellipseBorder / ClipRSuperellipse):"; echo "$hits"; status=1
else echo "ok — no third-party squircle packages"; fi

# 6. WARN: CustomPaint without a RepaintBoundary in the same file.
for f in $(grep -lE 'CustomPaint\(' $darts 2>/dev/null || true); do
  grep -q 'RepaintBoundary' "$f" || echo "WARN — CustomPaint without RepaintBoundary in $f"
done

# 7. WARN: CustomPaint without Semantics/ExcludeSemantics in the same file.
for f in $(grep -lE 'CustomPaint\(' $darts 2>/dev/null || true); do
  grep -qE 'ExcludeSemantics|Semantics\(|semanticsBuilder' "$f" || echo "WARN — CustomPaint without Semantics/ExcludeSemantics in $f"
done

# 8. WARN: constrained TextPainter.layout() near a width-fit probe — the silent-fit gotcha.
for f in $(grep -lE 'TextPainter\(' $darts 2>/dev/null || true); do
  grep -qE 'layout\(\s*(maxWidth|minWidth)' "$f" && echo "WARN — constrained TextPainter.layout() in $f (unconstrained for a measured fit)"
done

if [ "$status" -eq 0 ]; then echo "PASS — no hard violations (review any WARN above)"; else echo "FOUND hard violations above"; fi
exit "$status"
