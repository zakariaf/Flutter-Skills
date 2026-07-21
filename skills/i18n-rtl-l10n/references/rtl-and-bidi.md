# RTL — directional geometry, bidi isolation, mirroring, charts

RTL is a **layout discipline, not a translation task.** Most RTL bugs are hardcoded left/right
geometry that compiles fine and silently breaks. The fix is to author every layout with logical
`start`/`end` properties so it mirrors **by construction** when `Directionality` flips — which happens
automatically the moment the resolved locale is RTL. No per-widget conditionals.

## The allow / ban table

| Concern | USE (correct) | BANNED (grep rejects) |
| --- | --- | --- |
| Padding / margin | `EdgeInsetsDirectional.only(start:, end:)` | `EdgeInsets.only(left:, right:)` |
| Alignment | `AlignmentDirectional.centerStart` / `.centerEnd` | `Alignment.centerLeft` / `.centerRight` |
| Stack positioning | `PositionedDirectional(start:, end:)` | `Positioned(left:, right:)` |
| Text alignment | `TextAlign.start` / `.end` | `TextAlign.left` / `.right` |
| Row/Column main axis | `MainAxisAlignment.start` / `.end` | (don't hardcode child order for direction) |
| Directional icons | `Icons.adaptive.arrow_back`, `Icons.adaptive.arrow_forward` | `Icons.arrow_back`, `Icons.arrow_forward` |
| Border radius | `BorderRadiusDirectional.only(topStart:, …)` | `BorderRadius.only(topLeft:, …)` |

## Direction is a locale consequence

Never wrap the app root in `Directionality(TextDirection.rtl)` to "turn on RTL" — it hides
physical-side bugs (they *happen* to look right) and breaks the moment an LTR island is needed. RTL
comes from `GlobalWidgetsLocalizations` + the resolved locale. Drive the active locale from state
(e.g. a Riverpod `localeProvider` backed by a manual `Notifier`, never a legacy `StateProvider`) so a
Settings screen can pin one; changing it rebuilds `MaterialApp`,
re-flips `Directionality`, and re-runs every `AppLocalizations` lookup — live, no restart. Directional-only
geometry is what makes the live switch correct without touching feature code.

When logic genuinely needs the direction, read `Directionality.of(context)` — never assume
`TextDirection.rtl`. The only manual `Directionality` islands are: a forced-LTR wrapper around a
script-neutral token (a version string, a code, a fixed math expression), a locale-invariant
CustomPainter subtree, and a Settings language preview.

## Icons: mirror the directional, never the absolute

- **Mirror** (direction implied): back/next, chevrons, trend arrows, progress carets. Prefer
  `Icons.adaptive.*`; if absent, flip manually (below).
- **Never mirror** (fixed real-world meaning): clock, checkmark, compass, media play/pause/skip, logos.
  Mirroring everything is as wrong as mirroring nothing.

For a custom directional glyph not in `Icons.adaptive`:

```dart
Transform(
  alignment: Alignment.center,
  transform: Matrix4.rotationY(
    Directionality.of(context) == TextDirection.rtl ? math.pi : 0),
  child: const Icon(Icons.trending_up),
);
```

## Bidi isolation — strong-LTR technical strings inside RTL

Account/order/reference numbers, phone, email, URL, product/part codes, prices, and units visually
scramble inside an RTL paragraph unless isolated (a code's letters and digits swap ends). Isolate
characters live **only at the view layer** — store, search, and export the raw ASCII string; strip
isolates at the boundary.

```dart
const _lri = '⁦'; // U+2066 LEFT-TO-RIGHT ISOLATE
const _rli = '⁧'; // U+2067 RIGHT-TO-LEFT ISOLATE
const _fsi = '⁨'; // U+2068 FIRST STRONG ISOLATE
const _pdi = '⁩'; // U+2069 POP DIRECTIONAL ISOLATE

String isolate(String s)    => '$_fsi$s$_pdi'; // unknown direction
String isolateLtr(String s) => '$_lri$s$_pdi'; // known LTR (codes, numbers, equations)
String isolateRtl(String s) => '$_rli$s$_pdi'; // known RTL

// Inline in an RTL sentence — the isolated run is an ARB placeholder:
Text(l10n.accountRefLine(isolateLtr(account.reference)));
// Standalone field — set direction explicitly instead of wrapping:
Text(code, textDirection: TextDirection.ltr, textAlign: TextAlign.end);
TextField(controller: codeCtrl, textDirection: TextDirection.ltr);
```

- **Prefer known-direction (`isolateLtr`/`isolateRtl`) over FSI** — first-strong detection mis-guesses
  when a run opens with the "wrong" script or leading punctuation.
- Also isolate mixed value+unit runs like `50 km/h` and parenthesized numbers.
- Never use legacy `LRE`/`RLE`/`LRO`/`RLO` embeddings — use the isolate controls (UAX #9).
- Assert in tests that stored values are stripped of `U+2066`–`U+2069`.

## A fixed expression must not flip

A left-to-right expression like `6 × 4` flipped to `4 × 6` is a *wrong* expression, not just ugly.
Pin it LTR (a `Directionality(TextDirection.ltr)` island or `isolateLtr`) AND isolate it; a per-locale
golden of the expression under an RTL locale asserts operand order.

## CustomPainter — do NOT auto-mirror; mirror explicitly

A painter that owns a fixed coordinate grid (a diagram, a chart plot) is pinned
`TextDirection.ltr` on **only that subtree** so ambient RTL cannot silently flip it; chrome around it
still mirrors via logical insets. Map pointers through the painter's own transform on `localPosition`
(`TapDownDetails.localPosition`, `DragUpdateDetails.localPosition`) — never invert `dx` for RTL.

For charts specifically: chart chrome (axes, labels, legend) mirrors and the **time axis inverts** for
RTL, but the **plotted data itself is never flipped** — a rising trend must still look rising.

- Read `Directionality.of(context)` in the painter and reverse the X mapping for the time axis in RTL;
  keep the value-to-Y mapping unchanged.
- Place the value axis on the correct side (start/end, not fixed left).
- Feed the painter the same `numberFormatFor(locale)` so axis/tooltip labels use native digits; isolate
  numeric tick labels.
- Golden-test each chart across locale × direction × numeral. See `custom-canvas-and-gestures`.

## Testing (RTL slice)

- Golden with **real fonts loaded** — the default test host renders no Arabic/Persian glyphs, so
  goldens are otherwise blank or non-deterministic. Never `Ahem` for the numeral/shaping lane.
- Make `textScaler` 1.5–2× and give RTL overflow explicit golden dimensions — tall Persian/Arabic
  glyphs overflow fixed-height rows.
- A cheap Ahem lane catches mirroring geometry; a narrow real-font lane catches shaping and digit
  blocks. See `widget-golden-and-a11y-testing`.
- Manual device QA: letter joining/diacritics; codes/phone read LTR inside RTL cards; nav icons mirror;
  charts mirror chrome + invert time axis but keep data; live locale switch re-mirrors without restart.
