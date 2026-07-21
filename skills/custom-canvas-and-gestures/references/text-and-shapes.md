# Measured text fitting & shape/hairline technique — deep dive

The typographic and shape half of the skill: fitting type to a measured width, optical centring done
metrically, first-party squircles, and true hairlines.

## Measured text fitting with TextPainter

To size type so it fills a measured width, run a **linear probe**: lay the text out at a fixed probe
size, read `tp.width`, and scale. Glyph advances scale linearly with `fontSize`, so one layout pass
gives the answer.

```dart
double fitFontSize(String text, TextStyle style, double maxWidth,
    {double min = 12, double max = 96}) {
  const probe = 100.0;
  final tp = TextPainter(
    text: TextSpan(text: text, style: style.copyWith(fontSize: probe)),
    textDirection: TextDirection.ltr,
    maxLines: 1,
  )..layout(); // NO maxWidth argument
  return (probe * maxWidth / tp.width).clamp(min, max);
}
```

### The unconstrained-layout gotcha

Lay each candidate out **unconstrained** — never `layout(maxWidth: something)`. A constrained
`layout()` **wraps** the text, and `tp.width` then reports the *constraint*, not the natural width. The
fitter then returns the same size for every string and the feature silently disappears. This is the
single most common measured-fit bug.

### Multi-line fitting

To fit a phrase across N lines, enumerate break points (brute force is fine for short phrases —
break only at spaces, never hyphenate), and score each candidate by the **largest minimum line size
that still fits the height**. Maximise the *minimum* line, not the mean — the smallest line is what a
reader struggles with. Break ties toward fewer lines. Recompute inside `LayoutBuilder` on every
constraint change (rotation and `textScaler` both change the answer); this is one layout pass with no
assets — not worth caching.

Never replace a measured fit with `FittedBox` or an auto-shrink package where content must stay a
**uniform** size across a set — auto-shrink solves for the longest string and shrinks everything else,
destroying rhythm and overriding the user's `textScaler`. Never ellipsize content whose full text is
the product.

## Optical centring, done metrically

Display type sits optically low because most fonts' em box is top-heavy (ascent > cap height). Fix it
with metrics, never a hardcoded pixel nudge:

```dart
const TextHeightBehavior(
  applyHeightToFirstAscent: false,
  applyHeightToLastDescent: false,
  leadingDistribution: TextLeadingDistribution.even,
)
```

A `Padding(top: -6)`-style correction is wrong at every size the fitter produces and breaks outright
at 200% text scale and under an alternate accessibility font. If `DefaultTextHeightBehavior` is
installed app-wide, do not re-derive it locally — but never let it be stripped from this subtree.

## FontWeight vs FontVariation — the conflict

Set weight with `fontWeight: FontWeight.wNNN` **only**. Do **not** additionally pass
`FontVariation('wght', NNN)` on a variable font — `FontWeight` already drives the `wght` axis, and
passing both is a conflict that produces undefined weight. Pick one channel; prefer `fontWeight`.

## Prefer a CustomPainter over an image asset

For repeated vector detail (marks, ticks, a grid, a badge), a `CustomPainter` beats a bundled image:
- It stays crisp at every `devicePixelRatio` — no `@2x`/`@3x` asset set, no blur on odd DPRs.
- It recolours for free with the theme — no re-exported asset per palette.
- For many identical marks, draw them in **one** `Canvas` pass (a loop over `drawCircle`/`drawPath`)
  rather than N widgets — one layer, one raster.

## First-party squircles

Prefer the first-party rounded-superellipse family — they have an Impeller GPU fast path:
- `RoundedSuperellipseBorder` (as a `ShapeBorder` on `Material`/`Container`/`Card` shape).
- `ClipRSuperellipse` (to clip a child).
- `Canvas.drawRSuperellipse` (inside a painter).

Avoid:
- `ContinuousRectangleBorder` — **not** an iOS-grade squircle; its radius needs a ~2.35× multiplier
  to approximate one, which makes it degenerate ("TIE-fighter") earlier, and it centres its stroke
  regardless of `strokeAlign`.
- `figma_squircle` / `smooth_corner` packages — dead weight now that the shape is first-party.

For a full round use `StadiumBorder`, never `BorderRadius.circular(9999)` (a third-party sentinel).

## True hairlines and concentric radii

- **A hairline is one physical pixel:** `1.0 / MediaQuery.devicePixelRatioOf(context)` with
  `strokeAlign: BorderSide.strokeAlignInside`. `Border.all()` defaults to 1.0 **logical** px = ~3
  physical px on a 3× phone — that reads as a table border, not an engraved keyline.
- **Nested corners are concentric by construction:** an inner shape inside a padded outer shape takes
  `innerRadius = outerRadius - padding`, computed — never a second hardcoded constant, which drifts
  from the outer one and stops looking machined.
- Keep depth cues restrained and structural (tone + edge) rather than heavy skeuomorphic shadows; if
  you use a decorative blurred backdrop, never place it behind text or numerals a user must read.

## Physical-pixel snapping

For a crisp 1px line, snap the coordinate to the physical grid so it does not straddle two device
pixels and blur. Compute in physical pixels via `devicePixelRatio` and round to the nearest half-pixel
offset for the stroke centre when `strokeAlign` is centred; with `strokeAlignInside` on a rect the
edge already aligns.
