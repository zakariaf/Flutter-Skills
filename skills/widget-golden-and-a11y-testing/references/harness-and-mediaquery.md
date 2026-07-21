# The harness and MediaQuery layering

One harness file at `test/support/harness.dart`. Tests import it and nothing else
of their own. Everything below lives in that file; see `examples/harness.dart` for
the complete, compiling version.

## Device presets are logical size + DPR, not physical pixels

`tester.view.physicalSize` is in **physical** pixels. `Size(320, 640)` at the
default DPR of 3.0 yields a `107 x 213` **logical** surface — not a phone. Always
store the logical size and DPR separately and multiply:

```dart
void useDevice(Device d) {
  view.devicePixelRatio = d.dpr;
  view.physicalSize = d.logicalSize * d.dpr;
  addTearDown(view.reset);
}
```

Name presets by their **measured** size (`compact_320`, `small_360`,
`medium_412`), not a marketing model — the number is the fact, the model name
rots. Three presets spanning the tightest and a mid phone are enough for a matrix;
add a tablet width only if the app ships a distinct wide layout.

`tester.binding.window` is deprecated — never touch it. `tester.view` is current
and is the only one that pairs with `reset()`.

## The four load-bearing lines

| Line | Why it must stay |
|---|---|
| `addTearDown(view.reset)` | A leaked view size poisons every later test in the file — and that failure lands in a file nobody edited. Prefer `reset()` over the `resetPhysicalSize` / `resetDevicePixelRatio` pair: one call, nothing forgotten. |
| `MediaQuery` **above** `MaterialApp` | `pumpWidget` wraps the tree in a `View`, which inserts `MediaQuery.fromView`. `MaterialApp` inserts none of its own, so this `MediaQuery` is the nearest ancestor and wins. Placed *below* `MaterialApp` it is shadowed and the axes do nothing. |
| `Builder` + `MediaQuery.of(context).copyWith` | A bare `MediaQueryData()` zeroes the view-derived `size` and `padding` that `useDevice` just pinned — the test then measures a 0x0 screen and passes green. `copyWith` keeps the pinned geometry and changes only the axes you name. |
| `overrideWithValue` / `overrideWith` | `overrideValue` does not exist. Use `overrideWithValue(x)` for a value, `overrideWith((ref) => ...)` for a builder. |

## `pump()` vs `pumpAndSettle()`

`pumpAndSettle` exists only to wait out animations. If your feature has no
running animation, it has nothing to wait for — and it carries a 10-minute default
timeout, truncates its stack trace when it fires, and **hangs forever** on an
infinite splash/shimmer/spinner. So:

- `pump()` — advance one frame after a synchronous state change.
- `pump(Duration)` — advance a specific timer/debounce. `pump()` alone does **not**
  advance the fake clock; a `Timer`, `Future.delayed`, or debounce still needs an
  explicit duration or `fakeAsync`.
- `pumpAndSettle()` — only when a real, finite animation must complete, and never
  near an indefinite indicator.

## Driving MediaQuery flags

Expose a named parameter only for an axis some test actually drives — every
parameter is a promise.

| Flag | Verdict |
|---|---|
| `textScaler` | First-class. `TextScaler.linear(2.0)` is a deliberate over-approximation (Android 14+ scales large text less), so it stresses labels harder than a device — conservative, not device-faithful. |
| `boldText` | First-class axis, not an afterthought. It widens advance widths and overflows content that passes unbolded at the same scale — but only with a real proportional font loaded (`loadAppFonts()`); under the default Ahem test font every glyph is a weight-independent em-square, so the flag is inert. Always pair with scale, in a matrix that loads real fonts. |
| `accessibleNavigation` | `true` means Switch Access / VoiceOver is on. Drive it for the advisory-guideline tripwire. |
| `highContrast` | `AccessibilityFeatures.highContrast` is iOS-only and permanently false on Android. If the app has an in-app high-contrast setting, test it by overriding that setting's provider — not by faking this flag. |
| `disableAnimations` | Only meaningful if the app reads it to shorten/skip animations; otherwise it asserts nothing. |
| `invertColors` | The platform inverts at composite, below the widget tree. Nothing in a widget test observes the result. Skip it. |

## Seams throw until overridden

Wire every side-effecting dependency (repository, clock, notification gateway,
native channel) as a provider that throws `UnimplementedError` until overridden.
An un-overridden seam then fails **loudly** in a test rather than quietly
constructing a live service. `pumpApp` takes an `overrides` list so each test
supplies exactly the fakes it needs. For the default data fixture, override the
data provider with a fixed value; reach for a real in-memory database only in a
test that asserts a write reads back (see `persistence-drift` and
`testing-strategy`).

```dart
await tester.pumpApp(overrides: <Override>[
  itemsProvider.overrideWith((ref) => Stream<List<Item>>.value(kTestItems)),
]);
```

## Finders that survive refactors

| Purpose | Finder | Why |
|---|---|---|
| Behaviour (tap, activate) | `find.bySemanticsLabel('Archive')` | Names behaviour, not tree structure. Survives layout refactors and can be written before the widget. |
| Geometry (position, size) | `find.byKey(const ValueKey('item_3'))` | A stable identity is the primary key of a cell. Assert on it by name. |
| Anything | **Never `find.byType`** for app widgets | Couples the test to the class hierarchy; renaming a private widget reds the suite for no reason. (`find.byType` on framework types like `RenderParagraph` via `renderObject<>()` is fine.) |

## Asserting the effect, not the call

When a tap should cause a side effect, assert on **what** was produced, not merely
that a method was called. A fake that records into a list is a spy as well as a
fake; assert the recorded value. Swapping two strings or ids is a plausible-looking
regression no type checker catches — the effect assertion is the reason the test
exists.

```dart
testWidgets('activating an item enqueues that item, not its label', (tester) async {
  final queue = FakeActionQueue();
  await tester.pumpApp(overrides: [
    actionQueueProvider.overrideWithValue(queue),
  ]);
  await tester.tap(find.bySemanticsLabel('Archive'));
  await tester.pump();
  expect(queue.enqueued, <String>['item_archive']); // the id, not the visible text
});
```
