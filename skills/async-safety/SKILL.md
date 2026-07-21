---
name: async-safety
description: Enforces no-silent-failure async discipline in Flutter/Dart — the arrow-callback Future-drop hole no lint catches (`onTap: () => vm.save(x)`), void-returning event handlers, a mounted/ref.mounted guard after EVERY await before touching BuildContext, capturing Navigator/ScaffoldMessenger before the gap, honest `unawaited()` that always ends in catchError, no empty/bare catches, `rethrow` over `throw e`, and disposing every StreamSubscription/StreamController/Timer/sink. Use when writing or reviewing async/await, wiring onTap/onPressed/onSubmitted or any VoidCallback, touching BuildContext after an await, writing initState/dispose/addPostFrameCallback, adding a Timer or Future.delayed, writing a try/catch, or seeing use_build_context_synchronously, cancel_subscriptions, close_sinks, unawaited_futures, or discarded_futures.
---

# Async safety: no failure may be silent

Async bugs are silence. A dropped `Future` swallows its error; a dead `BuildContext` throws into a void; a leaked subscription fires into a disposed widget. An app with no telemetry has exactly two feedback loops — the analyzer and the test suite — and the analyzer has one hole big enough to drive the product through. Close it structurally, not with discipline. This skill applies whenever you write `async`/`await`, wire a callback, or hold a subscription, timer, or sink.

## Non-negotiable rules

1. **A callback must never touch a `Future`.** Every `onTap`/`onPressed`/`onSubmitted`/`VoidCallback` handler returns `void`. `onTap: () => vm.save(x)` where `save` is async is caught by NO lint (see below) — the fix is shape, not vigilance.
2. **A `mounted` / `ref.mounted` guard goes after EVERY await, immediately before the next `BuildContext` use** — never once at the top, never before the await where it proves nothing. Or capture the object you need before the gap.
3. **Multiple awaits ⇒ the guard sits after the LAST one.** A guard only certifies the interval since the most recent suspension point.
4. **`unawaited(x)` is legal only if `x` provably cannot fail silently** — it ends in a `.catchError(...)` or is total. Bare `unawaited(f)` routes errors to `PlatformDispatcher.onError`, detached from the UI. That is silence with a permission slip.
5. **Every `StreamSubscription`, `StreamController`, `Timer`, and sink is released** in `dispose()` / `ref.onDispose`. Prefer not owning it: a provider gives teardown for free.
6. **Every timer/stream callback that calls `setState` guards `mounted` first.** A `Timer` holds a strong reference to its closure and fires happily after the widget is gone.
7. **No empty catch, no bare catch, no swallow.** Every `catch` has an `on` clause (except the crash logger's own write), logs with its stack, and surfaces the failure. Use `rethrow`, never `throw e` — the latter resets the stack trace.
8. **Never `assert` a platform/plugin return value.** Asserts are stripped in release: green in every test, absent on the device — the perfect silent-failure bug.
9. **Nothing unbounded runs before `runApp`.** No migration, no plugin warm-up. Show a usable first frame, then warm up in `addPostFrameCallback`, unawaited.
10. **No `runZonedGuarded`.** Two error handlers suffice — `app-startup-and-bootstrap` owns installing them, their pre-`runApp` ordering, the `PlatformDispatcher.onError` `return true` rule, and never letting a handler throw. Don't restate that machinery here.

## The hole no lint catches

Verified with `discarded_futures`, `unawaited_futures`, and `unused_result` all at `error`:

| Callback shape | Diagnostics |
|---|---|
| `onTap: () => vm.save(note)` | **none — all three miss it** |
| `onTap: () { vm.save(note); }` | `discarded_futures` |
| `onTap: () async { vm.save(note); }` | `unawaited_futures` |
| `onTap: () => vm.saveNote(note)` (void method) | clean — the fix |

The arrow closure *returns* the `Future`, so every rule considers it used; the target type is `VoidCallback`, so Dart's void-compatibility discards it. The `Future` and its error both hit the floor. This is the most idiomatic way to wire a Flutter tap, and it is precisely where silence hides.

The mitigation is **structural, never disciplinary**: give the handler method a `void` return and do the `unawaited(... .catchError(...))` inside it. A callback then never holds a `Future`, so the hole is unreachable by construction.

```dart
// A void-returning seam. Do NOT "improve" this to Future<void> — that
// reopens the arrow-callback hole. Keep this comment; without it the next
// reader tidies the void away.
void saveNote(Note note) {
  unawaited(
    _persist(note).catchError((Object e, StackTrace s) {
      _log.record('save path threw: $e', s);
      _showError('That note was not saved.');
    }),
  );
}

Future<void> _persist(Note note) async {
  final result = await _repo.save(note); // returns a typed Result, does not throw
  switch (result) {
    case Ok():
      return;
    case Err(:final failure):
      _log.record('save failed: ${failure.code}', StackTrace.current);
      _showError('That note was not saved.');
  }
}
```

## The async gap and BuildContext

`context` is a live handle into the element tree, not a value. `await` yields to the event loop; while suspended the route may pop, the dialog may close, the `State` may be disposed. On resume the handle points at a corpse. `use_build_context_synchronously` is why — promote it to `error`.

```dart
// WRONG — the Element may be defunct after the gap.
Future<void> _save() async {
  await _repo.save(note);
  Navigator.of(context).pop();
}
```

Two legitimate fixes; prefer whichever makes intent obvious.

```dart
// RIGHT — capture before the gap. The captured object does not need the tree.
Future<void> _save() async {
  final navigator = Navigator.of(context);
  await _repo.save(note);
  navigator.pop();
}

// RIGHT — guard after the gap, immediately before the context use.
Future<void> _save() async {
  await _repo.save(note);
  if (!mounted) return;
  Navigator.of(context).pop();
}
```

Two awaits mean the guard sits after the second — the second await reopens the hole the first guard closed:

```dart
// WRONG
await _repo.save(note);
if (!mounted) return;
await _repo.reindex();
Navigator.of(context).pop(); // unguarded

// RIGHT
await _repo.save(note);
await _repo.reindex();
if (!mounted) return;
Navigator.of(context).pop();
```

### Which guard, where

| Context | Guard | Note |
|---|---|---|
| `State<T>` subclass | `if (!mounted) return;` | `State.mounted` — the field the analyzer recognises |
| Riverpod `Notifier`/`AsyncNotifier` after an await | `if (!ref.mounted) return;` | Riverpod 3.x — guards `state = ...` on a disposed provider |
| Plain class / controller, no `State`, no `ref` | Take no `BuildContext` at all | Pass a captured `NavigatorState` or a `void Function(String)` callback |
| `StatelessWidget` method | Capture before the gap | There is no `mounted` to check |

The last two rows are the ones people get wrong. A bare helper has no lifecycle to interrogate, so restructure: hand it a captured object or a callback so it never holds a context across a gap. Never write `if (!mounted) return;` *before* the await and call it done — that checks the one moment never in doubt.

## unawaited, initState, and the first frame

`initState` is synchronous and cannot be `async`. Kick the future off through a named method, then guard the landing:

```dart
@override
void initState() {
  super.initState();
  // honest: the load path ends in catchError; _load guards mounted before setState.
  unawaited(_load().catchError((Object e, StackTrace s) {
    _log.record('load failed: $e', s);
    if (mounted) _showError('Could not load notes.');
  }));
}

Future<void> _load() async {
  final notes = await _repo.loadNotes(); // may throw — the catchError above owns it
  if (!mounted) return; // a disposed widget's setState throws into nothing
  setState(() => _notes = notes);
}
```

Prefer to skip the hand-held subscription entirely: expose the stream as a provider and `ref.watch` it, so teardown is automatic and there is no field to leak.

Never block the first frame on unbounded work. A 12-row read is sub-10ms and safe to await before `runApp`; a schema migration or a plugin warm-up is not — it sits between the user and a usable UI. Show the shell first, then:

```dart
WidgetsBinding.instance.addPostFrameCallback((_) {
  unawaited(_service.warmUp().catchError((Object e, StackTrace s) {
    _log.record('warm-up failed: $e', s); // best-effort; never blocks the frame
  }));
});
```

## Subscriptions, controllers, timers

Every long-lived resource is released. `cancel_subscriptions` and `close_sinks` at `error`.

```dart
class _FeedState extends State<Feed> {
  StreamSubscription<List<Item>>? _sub;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _sub = _repo.watchItems().listen(_onItems);
  }

  void _onItems(List<Item> items) {
    if (!mounted) return; // a stream event can outlive dispose()
    setState(() => _items = items);
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel()); // nothing to await, but mark the intentional drop
    _debounce?.cancel();       // Timer.cancel() returns void — no Future to mark
    super.dispose();
  }
}
```

`close_sinks` only fires when the rule is enabled under `linter: rules:` — the `analyzer: errors:` block merely re-ranks diagnostics that already exist, it cannot switch a lint on. If a never-closed controller produces no diagnostic, that rule was deleted; restore it rather than trusting a green run. For a provider-held service that owns a stream or controller, release it in `ref.onDispose`.

`Timer` and `Future.delayed` share the same rule: cancel the field in `dispose()`, and guard `mounted` in the callback. Re-arming a timer means cancel-then-restart, never "return if already running" — swallowing the event manufactures the silence this skill forbids.

## Catches

```dart
try { await _repo.save(item); } catch (_) {}                    // WRONG — unrecoverable, unknowable
try { await _repo.save(item); } catch (e) { _log.record('$e', null); } // WRONG — swallows Errors (our bugs)
try { await _repo.save(item); } on DbException { /* oh well */ } // WRONG — logged nowhere, continues as success

// RIGHT — typed, logged with its trace, surfaced to the user.
try {
  await _repo.save(item);
} on DbException catch (e, s) {
  _log.record('save failed: $e', s);
  _showError('That item was not saved.');
}
```

Catch at the few call sites that read or write the boundary, not in a blanket handler. Never catch an `Error` subclass — that means a bug in your own code; let it crash. The **one** licensed silent catch is the crash logger's own write (it runs inside the error handlers; if it throws it recurses until the app dies) — and its intent-comment is the whole safeguard.

## Anti-patterns

- **`onTap: () => asyncMethod()`** — drops the `Future` and its error, uncaught by any lint. Route through a void handler.
- **`if (!mounted) return;` before the await** — proves nothing; the hazard is *after* the suspension point.
- **One guard for two awaits** — the second await reopens the hole.
- **`unawaited(f)` with no `catchError`** on a fallible path — silences the lint, keeps the bug.
- **`assert(await plugin.call() == ok)`** — vanishes in release; total silence on the device.
- **`throw e` inside a catch** — resets the stack to the rethrow line; use `rethrow`.
- **`async` `initState`, or `.then(...)` off it with no `mounted` guard** — `setState` on a disposed widget throws.
- **`pumpAndSettle` for timers** — `pump()` does not advance a fake clock; use `pump(duration)` or `fakeAsync`.
- **`runZonedGuarded`** — a footgun without a crash SDK; two error handlers suffice.
- **Promoting a void handler method to `Future<void>`** — returns the arrow-callback hole to the codebase.

## Catalogue your silent-failure modes

For any real app, enumerate its silent-failure paths *a priori* as a closed list, tagged by testability — **D** (testable in Dart) · **I** (integration only) · **M** (manual only) · **X** (structurally untestable). This catalogue becomes the spine of the test strategy: reason against it as a closed set, and when you touch a listed mechanism, restore its mitigation. The honest value is that the highest-severity paths — a plugin reporting success while doing nothing, a resource GC'd since last launch — often land in **M**/**X**, and naming them prevents papering over a gap with a mock that proves nothing. When you discover an (n+1)th way to go silent, add it to the catalogue.

## Definition of done

- [ ] Every `await` before a `context` use has a `mounted`/`ref.mounted` guard **between** them, or the object was captured before the gap.
- [ ] Multiple awaits ⇒ the guard sits after the last one.
- [ ] No callback method that a `VoidCallback` slot invokes returns a `Future`.
- [ ] Every `unawaited(...)` ends in a `.catchError` or is provably total.
- [ ] Every `StreamSubscription`, `StreamController`, `Timer`, and sink is released in `dispose()` / `ref.onDispose`.
- [ ] Every timer/stream callback calling `setState` guards `mounted` first.
- [ ] Every `catch` is typed, logs its stack, and surfaces the failure (crash logger excepted); `rethrow`, never `throw e`.
- [ ] No `assert` wraps a platform/plugin return value.
- [ ] Nothing unbounded runs before `runApp`; no `runZonedGuarded`.

## Related skills

- See `error-handling-typed-results` for the sealed `Result`/`Failure` spine that lets `save()` return outcomes instead of throwing, and the global error net.
- See `state-management-riverpod` for `ref.mounted`, `ref.onDispose`, and stream providers that own teardown.
- See `app-startup-and-bootstrap` for the `main()` ordering, the two global error handlers, and deferred warm-up.
- See `lint-and-style-config` for promoting `use_build_context_synchronously`, `unawaited_futures`, `discarded_futures`, `cancel_subscriptions`, and `close_sinks` to `error`.
- See `testing-strategy` for the clock-injected fake-async tests that exercise timers and the silent-failure catalogue.

## References

- Async programming: <https://dart.dev/libraries/async/async-await>
- `use_build_context_synchronously`: <https://dart.dev/tools/linter-rules/use_build_context_synchronously>
- `unawaited` / `discarded_futures`: <https://dart.dev/tools/linter-rules/discarded_futures>
- `State.mounted` and `BuildContext.mounted`: <https://api.flutter.dev/flutter/widgets/State/mounted.html>
- `PlatformDispatcher.onError`: <https://api.flutter.dev/flutter/dart-ui/PlatformDispatcher/onError.html>
- Handling errors in Flutter: <https://docs.flutter.dev/testing/errors>
