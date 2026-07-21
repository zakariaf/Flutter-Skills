// Demonstrates measured text fitting with TextPainter: a linear-probe single-line fit and a
// brute-force multi-line fit that maximises the smallest line, both using UNCONSTRAINED layout (the
// critical gotcha), metric optical centring via TextHeightBehavior, and fontWeight-only weight
// (never also FontVariation). Generic domain: fitting a Product name to a card width. Conceptually
// compiles against flutter.

import 'package:flutter/material.dart';

/// Returns the largest font size (clamped) at which [text] fits [maxWidth] on one line.
///
/// The probe is laid out UNCONSTRAINED: a constrained layout() wraps the text and tp.width then
/// reports the constraint, silently returning the same size for every string.
double fitSingleLine(
  String text,
  TextStyle style,
  double maxWidth, {
  double min = 12,
  double max = 96,
}) {
  const probe = 100.0;
  final tp = TextPainter(
    text: TextSpan(text: text, style: style.copyWith(fontSize: probe)),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(); // NO maxWidth — glyph advances scale linearly with fontSize
  if (tp.width == 0) return max;
  return (probe * maxWidth / tp.width).clamp(min, max);
}

/// Chooses line breaks for [words] (1..maxLines lines) that maximise the SMALLEST fitted line size
/// while the block still fits [maxHeight]. Breaks only at spaces; ties break toward fewer lines.
({List<String> lines, double fontSize}) fitBlock(
  List<String> words,
  TextStyle style,
  double maxWidth,
  double maxHeight, {
  int maxLines = 4,
  double min = 12,
  double max = 96,
}) {
  var best = (lines: <String>[words.join(' ')], fontSize: min);
  var bestScore = -1.0;

  for (var n = 1; n <= maxLines && n <= words.length; n++) {
    for (final cuts in _partitions(words.length, n)) {
      final lines = _applyCuts(words, cuts);
      // The block size is bounded by the SMALLEST line (the hardest to read) and by the height.
      var minSize = max;
      for (final line in lines) {
        final s = fitSingleLine(line, style, maxWidth, min: min, max: max); // probe once per line
        if (s < minSize) minSize = s;
      }
      final blockHeight = minSize * (style.height ?? 1.0) * lines.length;
      if (blockHeight > maxHeight) continue;
      // Maximise the minimum; on a tie prefer fewer lines (already visited at smaller n).
      if (minSize > bestScore) {
        bestScore = minSize;
        best = (lines: lines, fontSize: minSize);
      }
    }
  }
  return best;
}

// Enumerate the ways to split [count] words into [parts] non-empty runs (cut indices).
Iterable<List<int>> _partitions(int count, int parts) sync* {
  if (parts == 1) {
    yield const [];
    return;
  }
  for (var cut = 1; cut < count; cut++) {
    // First run takes [0, cut); recurse on the remainder needing parts-1 runs.
    if (count - cut < parts - 1) continue;
    for (final rest in _partitions(count - cut, parts - 1)) {
      yield [cut, ...rest.map((c) => c + cut)];
    }
  }
}

List<String> _applyCuts(List<String> words, List<int> cuts) {
  final bounds = [0, ...cuts, words.length];
  return [
    for (var i = 0; i < bounds.length - 1; i++) words.sublist(bounds[i], bounds[i + 1]).join(' '),
  ];
}

/// A poster-style block that fits its phrase to the viewport, recomputed on every constraint change.
class FittedPhrase extends StatelessWidget {
  const FittedPhrase({required this.phrase, super.key});
  final String phrase;

  @override
  Widget build(BuildContext context) {
    // fontWeight ONLY — do NOT also pass FontVariation('wght', 500); the two conflict.
    const style = TextStyle(fontWeight: FontWeight.w500, height: 0.98);
    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = fitBlock(
          phrase.split(' '),
          style,
          constraints.maxWidth,
          constraints.maxHeight,
        );
        return DefaultTextHeightBehavior(
          // Metric optical centring — never a hardcoded pixel nudge (breaks at 200% scale).
          textHeightBehavior: const TextHeightBehavior(
            applyHeightToFirstAscent: false,
            applyHeightToLastDescent: false,
            leadingDistribution: TextLeadingDistribution.even,
          ),
          child: Text(
            fit.lines.join('\n'),
            textAlign: TextAlign.start, // + Directional insets upstream, so RTL mirrors
            style: style.copyWith(fontSize: fit.fontSize),
          ),
        );
      },
    );
  }
}
