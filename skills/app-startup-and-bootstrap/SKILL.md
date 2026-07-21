---
name: app-startup-and-bootstrap
description: Enforces a fixed main() cold-launch order — crash-log sink + FlutterError.onError + PlatformDispatcher.onError installed BEFORE any code that can throw, settings/theme read before runApp so the first frame paints correct, real infra constructed in a composition-root bootstrap() and injected via ProviderScope overrideWithValue over throwing placeholder providers, non-blocking warm-up deferred to addPostFrameCallback, exactly two error handlers with NO runZonedGuarded, ProviderException unwrapped before logging, and a WidgetsBindingObserver that flushes durable state on background/resume. Use when editing lib/main.dart, main_<flavor>.dart, bootstrap.dart or app.dart, reordering anything in main(), adding a splash/onboarding/permission gate, restoring theme before first paint, wiring a DB or service into ProviderScope, handling app-lifecycle background/resume flushes, or chasing cold-start latency, ANRs, or first-frame jank.
---

# App startup and bootstrap

`main()` has one job: install a crash net, read the little state the first frame needs, wire real dependencies into the tree, and hand off to `runApp` — fast, ordered, and unable to hide a failure. Everything expensive happens after the first frame or off the launch path entirely.

## Non-negotiable rules

1. **Error handlers go first, before anything that can throw.** A crash-log sink, `FlutterError.onError`, and `PlatformDispatcher.instance.onError` are installed immediately after `WidgetsFlutterBinding.ensureInitialized()`. The step most likely to throw is opening the DB; installing handlers after it inverts the whole point.
2. **Exactly two error handlers — no zone.** `FlutterError.onError` (build/layout/paint errors) and `PlatformDispatcher.instance.onError` (uncaught async errors) cover every path. **Never add `runZonedGuarded`.** The "you need all three" advice is crash-SDK advice (Sentry wraps its init in a zone); with no such SDK a zone buys nothing and costs a documented zone-mismatch footgun. Flutter's own fix for that warning is to remove zones.
3. **`PlatformDispatcher.onError` returns `true` unconditionally.** Returning `false` routes to the embedder fallback, where the process may exit or hang. Get debug-console visibility from `debugPrint` under `kDebugMode`, not from `return kReleaseMode`.
4. **Never let an error handler throw.** Wrap its body in a bare `try/catch (_)` and keep the comment explaining why the discarded error is deliberate — otherwise someone "fixes" it into infinite recursion inside the handler.
5. **Read settings/theme before `runApp`.** Palette, text-scale policy, locale, and any first-paint choice are read synchronously (a handful of rows is sub-10ms) so frame one paints correct. A flash of the wrong theme is a visible defect, not a cosmetic one.
6. **Construct real infra in a composition-root `bootstrap()`, inject via overrides.** Feature code depends on **throwing placeholder providers**; `bootstrap()` builds the real DB/services and `overrideWithValue`s them in the root `ProviderScope`. A forgotten wiring fails loudly at startup, never returns null. This is also the test seam.
7. **Defer warm-up to `addPostFrameCallback`; never await it in `main()`.** Any plugin/engine warm-up (audio, TTS, first network handshake) runs its cost synchronously on the main thread and produces ANRs on the cold-start path. Fire it best-effort after the first usable frame.
8. **Do not block the first frame.** The only launch-path `await` is the one unavoidable blocker (opening the DB). Show the UI shell immediately rather than a blank window while a migration runs.
9. **Unwrap `ProviderException` before logging.** Riverpod 3 rethrows provider failures wrapped; logging the wrapper hides the real cause and makes every entry read `ProviderException`.
10. **Tune Riverpod retry for the app's failure model.** Riverpod 3 retries failing providers by default (~38s of exponential backoff). For a provider whose only failure is a local bug (corrupt DB, missing file), set `retry: (count, error) => null` so it fails immediately and loudly instead of spinning behind a spinner.
11. **Flush durable state on background via one lifecycle observer.** Register a single `WidgetsBindingObserver` and, in `didChangeAppLifecycleState`, flush pending writes when the app reaches `inactive`/`paused` — the OS can kill a backgrounded app with no further callback — and re-read time-sensitive state on `resumed`. This is bootstrap's mirror image: `bootstrap()` restores state on cold launch, the observer persists it before the process can die. Read services in the callback via `ref.read` (never `watch`).

## The sequence

```dart
// lib/main.dart — the whole launch path in one readable function (~40 lines).
Future<void> main() async {
  // Same function body as runApp(): no zone, so no zone-mismatch warning.
  WidgetsFlutterBinding.ensureInitialized();

  final CrashLog log = await CrashLog.open(); // FIRST: a crash before this is invisible forever.
  installErrorHandlers(log);

  final deps = await bootstrap(); // the one blocker: open DB, read settings, build services.

  runApp(
    ProviderScope(
      // Local-only failures are real bugs — fail fast, don't retry for ~38s.
      retry: (count, error) => null,
      overrides: [
        appDatabaseProvider.overrideWithValue(deps.db),
        settingsRepositoryProvider.overrideWithValue(deps.settings),
        notificationGatewayProvider.overrideWithValue(deps.notifications),
      ],
      child: const App(), // flavor-blind, DI-blind widget tree.
    ),
  );
}
```

```
WidgetsFlutterBinding.ensureInitialized()
  → CrashLog.open()                       first; nothing above may throw unseen
  → FlutterError.onError = …              cheap, synchronous
  → PlatformDispatcher.onError = …
  → bootstrap(): open DB (+migration), read settings, build services   ← only blocker
  → runApp(ProviderScope(overrides: …, child: App()))
──────────────────────────────────────── FIRST FRAME (UI visible, usable)
  → addPostFrameCallback: unawaited(service.warmUp())                   ← never blocks
```

## The two error handlers

```dart
void installErrorHandlers(CrashLog log) {
  // Errors inside Flutter's build/layout/paint callbacks.
  FlutterError.onError = (FlutterErrorDetails details) {
    try {
      FlutterError.presentError(details);
      log.record(details.exceptionAsString(), details.stack);
    } catch (_) {
      // Never let the error handler throw — do not "fix" this into recursion.
    }
  };

  // Uncaught async errors outside the framework's callbacks.
  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    try {
      log.record(unwrapProviderException(error).toString(), stack); // rule 9
      if (kDebugMode) debugPrint('$error\n$stack');
    } catch (_) {
      // Never let the error handler throw — do not "fix" this into recursion.
    }
    return true; // ALWAYS true (rule 3).
  };
}
```

The crash sink itself is synchronous (an entry must survive a hard kill, including a crash on frame one), size-bounded, and incapable of throwing. Those bare `catch (_)` guards deliberately violate *"don't discard errors"* (rule 4 wins here); the comment is load-bearing.

## The composition root

```dart
// lib/bootstrap.dart — the ONE place concrete implementations are named.
// Feature code sees only the throwing placeholder providers below.
class AppDeps {
  const AppDeps(this.db, this.settings, this.notifications);
  final AppDatabase db;
  final SettingsRepository settings;
  final NotificationGateway notifications;
}

Future<AppDeps> bootstrap() async {
  final db = await openAppDatabase(); // plain top-level factory — no Riverpod, isolate-reusable.
  final settings = DriftSettingsRepository(db);
  await settings.load(); // small read; needed before first paint.
  return AppDeps(db, settings, LiveNotificationGateway());
}
```

```dart
// lib/providers.dart — placeholders throw until bootstrap() overrides them.
final appDatabaseProvider =
    Provider<AppDatabase>((ref) => throw UnimplementedError('override in bootstrap()'));
final settingsRepositoryProvider =
    Provider<SettingsRepository>((ref) => throw UnimplementedError('override in bootstrap()'));
final notificationGatewayProvider =
    Provider<NotificationGateway>((ref) => throw UnimplementedError('override in bootstrap()'));
```

The widget tree (`App`) imports no concrete implementation and reads no flavor flag. Multiple entrypoints (`main_dev.dart`, `main_prod.dart`, a per-store flavor) share one `App` and one placeholder-provider list; only the overrides in `bootstrap()` differ, so the mains stay diff-able line-for-line. Tests reuse the identical seam by overriding the same providers with fakes or an in-memory DB — no live `main()` runs.

## Deferred warm-up

```dart
// In App's (or the first screen's) initState — NOT in main().
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(ref.read(someServiceProvider).warmUp()); // best-effort; UI already usable
  });
}
```

Warm-up policy and its failure policy are opposites by design: a failed warm-up costs a little latency on first use and may stay silent; the real operation it warms must fail **loudly** when it fails. Do not collapse the two.

## App lifecycle: flush on background

```dart
// The SAME State that owns deferred warm-up also owns the lifecycle observer.
class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        unawaited(ref.read(settingsRepositoryProvider).flush()); // may never resume
      case AppLifecycleState.resumed:
        ref.read(clockSensitiveProvider.notifier).refresh(); // re-read time-sensitive state
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }
}
```

One observer, registered once, removed in `dispose`. Do not scatter `didChangeAppLifecycleState` across feature widgets — features expose a `flush()` on their repository/notifier and the root observer calls it. Anything time-sensitive re-reads through `clockProvider` (see `service-boundary-and-native`), never `DateTime.now()`.

## The one blocker: opening the DB

Reading a dozen settings rows is trivial and safe to `await`. The genuine risk is a **schema migration** on the first launch after an update — unbounded work between the user and the app. The rule is not "make migration fast"; it is **paint the UI shell immediately instead of a blank window**, and take a pre-migration snapshot so a bad migration is recoverable. See `run-migration` for the migration ritual and `persistence-drift` for the connection setup.

## Anti-patterns

- **`runZonedGuarded` wrapping `runApp`** — buys a zone-mismatch warning and nothing else without a crash SDK; the two handlers already cover every path.
- **`await service.warmUp()` in `main()`** — synchronous binder/IPC cost on the main thread → ANR on cold start.
- **Reading theme/locale after `runApp`** — guarantees a first frame in the wrong theme, then a visible flip.
- **`get_it` / `injectable` / `MultiProvider` as a second DI container** — the `ProviderScope` overrides already are the DI; a parallel container is a second source of truth.
- **Returning `false` from `PlatformDispatcher.onError`** — hands control to the embedder fallback that may kill or hang the process.
- **A splash screen, onboarding carousel, or launch-time modal on the critical path** — every one delays the first usable frame; gate them behind an explicit product decision, never add them by reflex.
- **Logging the raw caught object in Riverpod 3** — records `ProviderException`, not the cause.
- **Micro-optimising cold start** — zygote fork, `Application.onCreate`, and VM snapshot load dominate and are the platform's, not measurable from Dart; the only lever you own is "don't block the first frame."

## Definition of done

- [ ] Crash sink + both error handlers installed before any throwing code.
- [ ] Exactly two error handlers; no `runZonedGuarded` anywhere.
- [ ] `PlatformDispatcher.onError` returns `true` and cannot itself throw.
- [ ] Settings/theme read before `runApp`; first frame paints correct.
- [ ] Real infra built in `bootstrap()` and injected via `ProviderScope` `overrideWithValue`; feature code sees only throwing placeholder providers.
- [ ] The widget tree is DI-blind and flavor-blind; extra entrypoints differ only in overrides.
- [ ] Warm-up deferred to `addPostFrameCallback` and `unawaited`.
- [ ] `ProviderException` unwrapped before logging; retry policy chosen deliberately.
- [ ] One root `WidgetsBindingObserver` flushes durable state on `inactive`/`paused` and re-reads on `resumed`; registered in `initState`, removed in `dispose`.
- [ ] `main()` stays short and does nothing an added line can't justify against these rules.

## Related skills

- This skill OWNS installing and ordering the global error handlers; see `error-handling-typed-results` only for the `Result`/`Failure` taxonomy the handlers route into (and isolate re-wrapping).
- See `async-safety` for the `unawaited`/Future-drop discipline the warm-up and background-flush calls rely on.
- See `state-management-riverpod` for the placeholder-provider + `overrideWithValue` DI pattern in depth.
- See `flutter-architecture` and `project-structure-and-packages` for where `bootstrap()` sits in the layer graph.
- See `navigation-and-routing` for the `go_router` config that `App`'s `MaterialApp.router` wires.
- See `run-migration` and `persistence-drift` for the DB open/migration path that `bootstrap()` awaits.
- See `service-boundary-and-native` for wiring each side effect as an injectable throwing-until-overridden interface, and for the `clockProvider` time seam the resume handler re-reads.
- See `design-system-structure` for restoring the theme before first paint.

## References

- Flutter — Handling errors: https://docs.flutter.dev/testing/errors
- Flutter — App startup / performance best practices: https://docs.flutter.dev/perf/best-practices
- API — `PlatformDispatcher.onError`: https://api.flutter.dev/flutter/dart-ui/PlatformDispatcher/onError.html
- API — `SchedulerBinding.addPostFrameCallback`: https://api.flutter.dev/flutter/scheduler/SchedulerBinding/addPostFrameCallback.html
- Riverpod — Provider overrides & scope: https://riverpod.dev/docs/concepts/scopes

## Provider / ChangeNotifier appendix

The same ordering holds on the official Flutter `provider` + `ChangeNotifier` stack; only the DI wiring at the root changes.

- **Composition root.** Build real infra in `bootstrap()` exactly as above, then inject through a `MultiProvider` at the tree root instead of `ProviderScope` overrides:

```dart
runApp(
  MultiProvider(
    providers: [
      Provider<AppDatabase>.value(value: deps.db),
      ChangeNotifierProvider<SettingsController>(
        create: (_) => SettingsController(deps.settings)..load(),
      ),
      Provider<NotificationGateway>.value(value: deps.notifications),
    ],
    child: const App(),
  ),
);
```

- **No throwing placeholders.** `provider` throws `ProviderNotFoundException` on a missing lookup, so a forgotten wiring already fails loudly — you don't hand-roll the placeholder.
- **Error handlers, ordering, deferred warm-up, no-zone rule, and `return true`** are identical — they are framework-agnostic and belong to `main()`, not to the DI library.
- **Warm-up** fires from `addPostFrameCallback` and reads the service via `context.read<T>()` (never `watch` in a one-shot callback).
- **Retry.** There is no built-in provider retry to disable; a `ChangeNotifier` surfaces load failure through its own state (e.g. an `AsyncStatus.error`) that the UI renders — keep it loud rather than silently retrying.
