---
name: flutter-performance
description: Enforces Flutter runtime performance — const subtrees, minimal rebuild scope via ref.watch(select), lazy ListView/GridView builders and slivers, sized image decode (cacheWidth/ResizeImage), heavy work off the UI isolate via compute/Isolate, surgical RepaintBoundary, dispose everything, and measurement in profile mode on a floor device. Use when optimizing UI, diagnosing jank or dropped frames, tuning long lists or images, reviewing rebuild/repaint scope, or when the task mentions const, select, ListView.builder, cacheWidth, compute, RepaintBoundary, AnimatedBuilder, DevTools, raster thread, or 60/120fps.
---

# Flutter Performance

Hold a steady 60 fps (<=16 ms/frame; <=8 ms on 120 Hz) on a floor device (low-end Android / older iPhone). Performance is a property you **measure in profile mode**, not one you assert. It comes from rebuilding less, painting cheaply, and keeping both the UI thread and the raster thread free.

## Non-negotiable rules

1. **`const` everything legal.** A `const` subtree is skipped on rebuild — the framework short-circuits it by identity. Keep `prefer_const_constructors` on as an error; a non-const literal that could be const is a lint failure, not a preference.
2. **Shrink the rebuild scope to the smallest changing widget.** Never `ref.watch(provider)` for a whole state object when one field changed — watch `provider.select((s) => s.field)`. A HUD counter tick must never rebuild a heavy sibling. Rebuild scope is the single biggest lever on build-thread cost.
3. **Lazy everything long.** `ListView.builder` / `GridView.builder` / slivers for variable or unbounded content. `ListView(children: items.map(...).toList())` builds every off-screen row up front — refuse it for anything not tiny and fixed.
4. **No expensive work in `build()`.** No `jsonDecode`, sort, regex, `DateTime` math, file/network, or large allocation — `build()` may run every frame. Compute in the Notifier/ViewModel once and cache the result in immutable state.
5. **Heavy CPU off the UI isolate.** Parse large payloads, process images, crunch numbers in `compute()` or a spawned `Isolate`. Blocking the UI thread is guaranteed jank; the raster thread cannot save you.
6. **Size image decode to the display slot.** `cacheWidth`/`cacheHeight` or `ResizeImage`, correct asset resolutions, `precacheImage` for above-the-fold art. Decoding a 4000 px source into a 100 px box spikes memory and OOMs cheap phones.
7. **Prefer the cheapest widget that does the job.** `ColoredBox`/`DecoratedBox` over `Container`, `SizedBox` for spacing, `FadeTransition`/`AnimatedOpacity` over the `Opacity` widget in hot paths. Avoid `ClipPath`/`saveLayer` inside scrolling lists — they force an offscreen buffer on the raster thread.
8. **`RepaintBoundary` around costly, independently-repainting subtrees** (an animation, a chart, a live indicator) so its repaint does not re-raster its neighbours. Do not sprinkle boundaries everywhere — each is a compositor layer that costs memory.
9. **Pass expensive children through `child:`.** `AnimatedBuilder`/`ValueListenableBuilder`/`StreamBuilder` rebuild only the `builder`; hand the unchanging subtree in via `child:` so it is built once, not per frame.
10. **Dispose to avoid leaks.** `AnimationController`s, gesture recognizers, stream subscriptions, timers, `TextEditingController`s, caches — released in `dispose()` (widgets) or `ref.onDispose` (providers). `autoDispose` scoped session state so it does not survive the screen.
11. **Measure in PROFILE mode on a real floor device with DevTools.** Debug timings are meaningless (JIT, asserts). Watch the **raster thread** as well as the UI thread — `saveLayer`/blur/clip cost shows there, not in Dart. Never ship a frame-budget number that was asserted, not measured.

## Narrow the rebuild scope

Watch the single field that changes, not the whole state object:

```dart
// Rebuilds only when the count changes, not on every OrderState mutation.
class OrderBadge extends ConsumerWidget {
  const OrderBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(orderProvider.select((s) => s.items.length));
    return Text('$count');
  }
}
```

`.select` runs the selector every publish but rebuilds only when the selected value's `==` changes, so its input must be an immutable value with real equality. See `state-management-riverpod` for the watch/read/listen split and `family` + `autoDispose`.

## Keep expensive children out of the animation loop

```dart
// The card is built once; only the transform recomputes each tick.
AnimatedBuilder(
  animation: _controller,
  child: const ProductCard(),
  builder: (_, child) =>
      Transform.scale(scale: _controller.value, child: child),
);
```

## Lazy lists and sized images

```dart
// Lazy — only visible rows are built.
ListView.builder(
  itemCount: items.length,
  itemBuilder: (context, i) => ItemTile(item: items[i]),
);

// Decode to the slot, not the source resolution.
Image.asset('assets/hero.png', cacheWidth: 240);
```

## Heavy work off the UI isolate

```dart
// parseItems is a top-level or static function (isolate entry-point rules).
final items = await compute(parseItems, jsonString);
```

## Custom painting

For a `CustomPainter`, the discipline is zero-allocation `paint()`, a `shouldRepaint` that is one value comparison over an immutable scene value, and a `repaint:` `Listenable` (the `AnimationController`) instead of `setState` in a ticker. That treatment lives in `custom-canvas-and-gestures`; the one performance-critical rule to carry here: **never allocate `Paint`/`Path`/`Gradient` inside `paint()`** — hold them as painter fields and mutate cheap properties.

## Profiling workflow

1. `flutter run --profile` on a physical floor device.
2. DevTools -> Performance; record while reproducing the jank.
3. For each over-budget frame, check whether the time is in **Build**, **Layout**, or **Raster**.
   - Build-heavy -> narrow rebuild scope with `.select`, add `const`, move work out of `build()`.
   - Raster-heavy -> reduce `Opacity`/clips/`saveLayer`, add a `RepaintBoundary`, simplify shaders.
4. Use "Track widget rebuilds" to find widgets rebuilding too often.
5. Fix one bottleneck, re-measure. Never optimize without a before/after measurement.

## Anti-patterns

- **Judging performance in debug mode** — JIT and asserts make timings fiction. Profile mode, real device, always.
- **Premature optimization with no profile data** — adds complexity, hides nothing; measure first.
- **`setState()` high in the tree** rebuilding a whole screen for a tiny change — scope the state down.
- **`ref.watch(provider)` for a whole object in a leaf** when one field changed — use `.select`.
- **`ListView(children: [...].toList())` for long/unbounded content** — builds every off-screen row.
- **`jsonDecode`/sort/`DateTime` math/regex in `build()`** — it may run every frame; precompute in the ViewModel.
- **`Opacity` widget for fades in scrolling lists** — forces `saveLayer`; use `FadeTransition` or fade via color.
- **Decoding full-resolution images** into small widgets — memory spikes and OOM on cheap phones.
- **Parsing large payloads / heavy loops on the UI isolate** — frozen frames; use `compute`.
- **`RepaintBoundary` on everything** — layer-memory bloat; use it surgically around independently-repainting subtrees.
- **`AnimatedBuilder`/`StreamBuilder` rebuilding an expensive child** instead of passing it via `child:`.
- **Rebuilding on every keystroke without debounce**, or unbounded caches/listeners that leak.
- **Allocating `Paint`/`Path` inside `paint()`** — per-frame garbage; hold them as fields.

## Definition of done

- [ ] `const` applied everywhere legal; `prefer_const_constructors` clean.
- [ ] Rebuilds scoped with `.select`; a tick in one widget never rebuilds a heavy sibling.
- [ ] Long/variable lists are lazy (`.builder`/slivers).
- [ ] No I/O, parsing, or heavy compute in `build()`; big work runs via `compute`/`Isolate`.
- [ ] Images sized to display (`cacheWidth`/`ResizeImage`); above-the-fold precached.
- [ ] Cheapest suitable widgets/effects chosen; `RepaintBoundary` used surgically; expensive children passed via `child:`.
- [ ] Any `CustomPainter` allocates nothing in `paint()`; `shouldRepaint` is one value compare.
- [ ] Controllers, recognizers, subscriptions, timers disposed; scoped session state `autoDispose`d; no leaks.
- [ ] Measured in profile mode on a floor device via DevTools — UI **and** raster threads under budget; no frames over 16 ms; claim backed by a recording.

## Related skills

- `state-management-riverpod` — the watch/read/listen split, `.select`, `family` + `autoDispose`, immutable state that makes `.select` correct.
- `widget-composition` — small `const` Widget classes over `_buildX` methods, dispose discipline, cheapest-widget choices.
- `custom-canvas-and-gestures` — zero-allocation `paint()`, `shouldRepaint` as one value compare, `repaint:` `Listenable`.
- `testing-strategy` — clock-injected pure core so heavy compute is testable off the UI isolate.

## References

- [Flutter — Performance best practices](https://docs.flutter.dev/perf/best-practices)
- [Flutter — Performance profiling / UI performance](https://docs.flutter.dev/perf/ui-performance)
- [Flutter — Concurrency and isolates / compute](https://docs.flutter.dev/perf/isolates)
- [Flutter — Impeller rendering engine](https://docs.flutter.dev/perf/impeller)
- [Flutter API — RepaintBoundary](https://api.flutter.dev/flutter/widgets/RepaintBoundary-class.html)
- [Flutter API — ResizeImage / cacheWidth](https://api.flutter.dev/flutter/painting/ResizeImage-class.html)
- [Riverpod — using select to filter rebuilds](https://riverpod.dev/docs/concepts/reading#using-select-to-filter-rebuilds)
