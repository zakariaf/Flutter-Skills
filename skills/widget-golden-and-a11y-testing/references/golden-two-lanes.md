# Golden testing — the refusal, and the two honest lanes

## First decide whether you need a golden at all

Layout is proven more cheaply by computed geometry (overflow matrix + `getRect`
invariants + `getSize` tap targets), each of which fails with a **sentence** a
human can act on. A golden fails with a diff image and, worse, **cannot assert
anything** — it asserts only "these pixels equal the pixels I blessed". Bless a
screen of clipped, unreadable text once and it passes forever, green.

So a **layout** golden is a poor gate: the failure it guards against (a padding
tweak) is the cheapest bug you have, and the failure it cannot see (content that
dropped below a floor) is the expensive one. Refuse layout goldens; use geometry.

Goldens earn their keep only for what geometry **cannot** see:

1. **Glyph shaping** — script joining (Arabic/Persian), ligatures, complex scripts.
2. **Mirroring** — directional icons and leading/trailing swaps under RTL.
3. **Numeral rendering** — locale digit glyphs (e.g. Eastern-Arabic, Persian).
4. **`CustomPainter` output** — where there is no widget tree to measure (still,
   also assert its `Semantics` label/value in a plain widget test).

## Tooling: check liveness before naming a package

| package | state | verdict |
|---|---|---|
| `golden_toolkit` | discontinued at v0.15.0, no replacement | Never recommend. Tutorials still do; they are stale. |
| `alchemist` (VGV/Betterment) | maintained | Use it for `loadAppFonts` and its CI/platform lane split. Note its CI mode can obscure text with coloured blocks — that mode proves geometry, not glyphs; use the real-font lane for glyphs. |

Before naming any package from memory, confirm it is not discontinued.

## Two lanes, both call `loadAppFonts()`

`flutter test` runs in a plain Dart VM with a test font (Ahem) whose every glyph is
an identical box; bundled fonts are not loaded unless the test loads them. So a
golden either renders boxes (proving nothing about type) or loads the real font.
Split it:

| Lane | Fonts | Runs on | Proves | CI |
|---|---|---|---|---|
| **Ahem / geometry** | Ahem squares (byte-stable cross-OS) | one pinned Linux box | geometry, mirroring, overflow, box layout | every PR |
| **Real-font** | the app's bundled fonts | one pinned OS | script joining, ligatures, numeral glyphs | PR-label or nightly |

Ahem squares validate geometry but **not** shaping — broken script joining or a
wrong numeral glyph slips through the Ahem lane and is caught only by the real-font
lane. Forgetting `loadAppFonts` renders tofu boxes that differ per machine.

## Setup: one `flutter_test_config.dart` per golden root

```dart
// test/flutter_test_config.dart
import 'dart:async';
import 'package:alchemist/alchemist.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  await loadAppFonts(); // bundled fonts + Ahem
  return AlchemistConfig.runWithConfig(
    config: const AlchemistConfig(/* ci + platform lanes */),
    run: testMain,
  );
}
```

## RTL goldens pump under Directionality

Derive direction from the locale, then assert it by construction. Do not rely on
the LTR / `en_US` / 1.0 defaults.

```dart
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final locale in const [Locale('ar'), Locale('he'), Locale('fa')]) {
    testWidgets('ItemCard renders RTL for ${locale.languageCode}', (tester) async {
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.rtl,
        child: _CardHarness(locale: locale),
      ));
      await expectLater(
        find.byType(ItemCard),
        matchesGoldenFile('goldens/rtl/item_card_${locale.languageCode}.png'),
      );
    });
  }
}
```

Golden the **i18n primitives exhaustively** (numerals, separators, bidi isolation,
mirroring) and **sample** representative screens — never the full cross-product.

## Discipline

- Tag every golden `@Tags(['golden'])` so the unit and golden lanes stay separate
  (`flutter test --exclude-tags golden` vs `--tags golden`).
- Pin the Flutter version (e.g. FVM). **Generate and commit blessed files in that
  ONE environment** — never regenerate on a dev machine while CI runs a different
  OS. Font rasterization, subpixel positioning, and antialiasing differ across
  hosts and across engine revisions.
- **Block accidental `--update-goldens` in the pipeline.** A CI step that blesses
  turns the suite into a ratchet that approves whatever shipped; regeneration is a
  deliberate, reviewed, local act with a titled commit.
- Never `pumpAndSettle()` a shimmer/splash/spinner golden — use timed `pump` only.
- Reject `dynamic_color` / `ColorScheme.fromSeed` from wallpaper for anything you
  want to golden or contrast-gate: a palette computed on-device from an unseen
  image is unverifiable at build time.

## What replaces a layout golden — recap

1. The **overflow matrix** (device x scale x bold), asserting `takeException()` is
   null.
2. The **fit assertion** (`getSize` inside a `getRect` cell).
3. **`getRect` geometry invariants** (shared row top / column left).
4. The **pure-Dart contrast gate** over theme colour values.

Each names what broke. A golden hands you a picture.
