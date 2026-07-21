---
name: flutter-architecture
description: Enforces a right-sized feature-first layered MVVM Flutter architecture — features are folders and cross-cutting foundations become packages only when a compile wall earns it, a strict downward-only dependency DAG, dumb Views over one Notifier/AsyncNotifier ViewModel per feature, repositories as the single source of truth and single write path returning immutable domain values, abstractions only where something genuinely can't run in a test, and Riverpod 3.x as the one context-free DI+state mechanism (no get_it/injectable/package:provider container). Use when creating a Flutter feature or file, deciding folder-vs-package or where a class belongs, naming a Screen/Notifier/Repository/Service, wiring providers or a composition-root/bootstrap.dart, adding a use-case/domain layer, resisting over-engineering on a small app, or reviewing whether a change respects the layer boundaries.
---

# Flutter Architecture

Structure every Flutter app as a **layered, feature-first MVVM system, sized to the app**. You must
always answer "where does this code belong?" in one second. Based on Flutter's official *Guide to app
architecture*, with Riverpod 3.x as the one mechanism for both state and dependency injection.

Two failure modes kill an architecture: under-structure (a widget touching a database) and
over-structure (a `*UseCase` wrapping one repository call, an interface over code that already runs in
a test). This skill fights both. **Start small; add a layer only when it carries a load you can name.**

Read the reference for the task at hand:
- `references/module-and-layers.md` — the layer model, folder-vs-package continuum, the DAG, barrels, feature-folder anatomy, and the "when multi-package (workspace)" note.
- `references/right-sizing.md` — the reject-over-engineering table, "abstract only what you can't test", and how architecture scales with app size.
- `references/state-di-riverpod.md` — provider graph, keepAlive vs autoDispose, placeholder-override composition root, isolate-safe factories, `ProviderContainer` tests.

Run `scripts/check_architecture.sh` before opening a PR.

## Non-negotiable rules

1. **Answer "where does this belong?" in one second.** Group by **feature first, layer second**. No
   giant app-wide `screens/`, `models/`, or `widgets/` bucket — those smear one feature across the
   tree and force a name lookup on every edit.
2. **Two layers minimum: UI and Data. A domain/use-case layer only when logic spans multiple
   repositories** (projection, aggregation, a multi-step workflow). A `*UseCase` that forwards one
   repository call is a rename, not a boundary — Flutter's own guidance rates the domain layer
   *conditional* and says most apps don't need it.
3. **Abstract exactly what cannot run in a test — name what the abstraction makes testable.** A
   platform channel, network client, or plugin that can't execute in `flutter test` earns an
   interface + a fake. Code that already runs headless (an in-memory DB, a pure calculator, a
   repository over it) stays **concrete**. "It's cleaner" is not a load; if you can't name the seam it
   buys, don't add it.
4. **Data flows one way; never skip or reverse a hop.** Data down: `Service → Repository → ViewModel →
   View`. Events up: `View → ViewModel → Repository`. A widget calls its ViewModel only; a ViewModel
   calls repositories only. No two-way binding, no widget reaching a data source.
5. **The View is dumb.** A View does layout, `if`/`switch` on state, animation, and navigation —
   nothing else. No business logic, no formatting/number math, no `try/catch`, no data access. If a
   widget computes or fetches, it's in the wrong layer.
6. **One ViewModel per feature, over immutable state.** The ViewModel holds **private mutable state**
   and exposes **intent methods** (`load()`, `add(...)`); every transition assigns a **new immutable
   value** with value equality. No public setters, no mutable field the UI edits in place.
7. **Repositories are the single source of truth AND the single write path.** Every mutation is one
   named repository method that **persists first, then publishes** (one transaction where the store
   supports it). Never persist-after-publish — a crash in between credits state that never saved.
8. **Derive, don't store.** Counts, totals, streaks, filtered lists are **computed from the source of
   truth** (a stream/derived provider), never a second stored counter that can drift out of sync.
9. **Map at the boundary; keep domain types out of the edges.** Repositories map storage rows / JSON
   DTOs → immutable domain **value objects**. A generated Drift row or a `Map` never reaches a
   ViewModel or widget; unit math and locale formatting never happen in a widget.
10. **Inject through providers; depend on the abstraction where it earns one.** No globals, no
    singletons, no service locator reached from a widget, no `DateTime.now()` outside an injected
    `Clock`. A composition root wires the object graph once.
11. **Features are FOLDERS; foundations become PACKAGES only when a compile wall is load-bearing.**
    Default to a **single package**. A feature never imports another feature — share via a foundation
    layer or navigate by route **ID**. The dependency graph is a strict **downward-only DAG**.
12. **Errors are typed values at boundaries.** Repositories/use-cases return a sealed `Result`/`Failure`
    rather than throwing across a layer; the UI switches exhaustively. See `error-handling-typed-results`.

## The layered shape (single package, the default)

`project-structure-and-packages` OWNS the physical tree; this is the feature-first layout it defines,
shown here for the layer semantics. Features are FOLDERS under `lib/features/`; a feature's Views and
its one ViewModel live in `presentation/`.

```text
lib/
  main.dart                 # thin entrypoint → bootstrap()
  bootstrap.dart            # composition root: build infra, override placeholder providers, runApp
  app.dart                  # MaterialApp.router, theme, top-level ProviderScope children
  core/                     # PURE foundation, NO Flutter: value objects, Result/Failure, the Clock seam,
                            #   extensions, pure calculators (the sanctioned foundation, not a junk-drawer)
  data/                     # shared data layer: Drift db, DAOs, repositories, row→model mappers
  services/                 # injectable side-effect ports + live impls (services/native/ = MethodChannel)
  routing/                  # the single go_router config, typed routes, guards
  theme/  l10n/             # ThemeExtension token sets; generated AppLocalizations + ARB
  features/
    tasks/
      presentation/
        task_list_screen.dart      # View: dumb ConsumerWidget
        task_list_notifier.dart    # ViewModel: StreamNotifier over immutable state
        widgets/                   # widget CLASSES used only by this feature
      application/                 # optional: use-cases, ONLY when logic spans repositories
      domain/                      # optional: feature-local models
      # data/ usually ABSENT — features read shared repos from lib/data/
```

Rules of thumb: `core/` depends on nothing above it and stays free of `BuildContext`; `data/` has no
Flutter UI imports; a feature depends on `core`/`data`/`services`, never on a sibling feature. Add a
feature-local `domain/` + `application/` (use-cases) folder **only** when logic spans repositories.

## The feature slice (Riverpod-first "how")

A dumb View reads one ViewModel; the ViewModel holds private state and exposes intent methods.

```dart
// features/tasks/presentation/task_list_notifier.dart — the ViewModel.
//   build() returns the live repository stream; a mutation commits through the single write
//   path and the watched stream RE-EMITS. No manual `state = ...` republish.
final class TaskListNotifier extends StreamNotifier<List<Task>> {
  @override
  Stream<List<Task>> build() {
    ref.onDispose(() {/* controllers/subscriptions released here */});
    return ref.watch(taskRepositoryProvider).watchTasks();   // track every emission
  }

  Future<void> add(String title) async {    // intent method — no setter
    final id = ref.read(idGeneratorProvider)();            // injected id source — never a UI UniqueKey
    await ref.read(taskRepositoryProvider).add(Task.create(id: id, title: title));
    // No republish: the committed write makes watchTasks() re-emit and build()'s stream updates state.
  }
}

final taskListNotifierProvider =
    StreamNotifierProvider<TaskListNotifier, List<Task>>(TaskListNotifier.new);
```

The repository behind it is the single source of truth AND single write path — a `watchTasks()`
stream plus an `add()` that persists first, then the stream re-emits. Give it an `abstract interface`
only when the real impl can't run in a test (rule 3); over an in-memory DB a concrete class is fine.

```dart
// features/tasks/task_list_screen.dart — the View is dumb: read one provider, render.
final class TaskListScreen extends ConsumerWidget {
  const TaskListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tasks = ref.watch(taskListNotifierProvider);
    return tasks.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(onRetry: () => ref.invalidate(taskListNotifierProvider)),
      data: (list) => ListView(
        children: [for (final t in list) TaskTile(task: t)],   // widget CLASS, not a _buildTile()
      ),
    );
  }
}
```

Providers ARE the dependency injection. Wire deps via `ref.watch`, key per-entity state with `family`,
and use `autoDispose` for per-screen controllers. See `state-management-riverpod` for the full API
discipline (watch/read/listen split, `.select`, stale-closure hazards).

## The composition root (single write of the object graph)

Infra that constructs asynchronously (a database, dirs, a key store) is injected via **placeholder
providers that throw until overridden** in `bootstrap.dart` — the same seam tests use.

```dart
// data/providers.dart — placeholder: throws until bootstrap() overrides it (and every test overrides it).
final appDatabaseProvider =
    Provider<AppDatabase>((ref) => throw UnimplementedError('override in bootstrap()'));

// bootstrap.dart — the ONE place async infra is built and the graph is composed.
Future<void> bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await openAppDatabase();       // plain top-level factory, no BuildContext
  runApp(ProviderScope(
    overrides: [appDatabaseProvider.overrideWithValue(db)],
    child: const App(),
  ));
}
```

Keep infra (DB, repositories, clock) `keepAlive`; never `autoDispose` a singleton that can be torn
down mid-operation. See `app-startup-and-bootstrap` for main() ordering and error handlers.

## Right-sizing: folder vs package, and what to abstract

Scale the architecture to the app. The three questions, in order:

- **Does this need a new folder or a new file?** Almost always a file in an existing feature/layer.
- **Does this need a domain/use-case layer?** Only if logic spans multiple repositories. One-repo CRUD
  does not.
- **Does this need an interface?** Only if the real implementation can't run in `flutter test`, or you
  genuinely swap dev/prod impls. Name the fake it enables.
- **Does this need a separate package?** Only when a **compile-time wall is load-bearing** — divergence
  would be a correctness bug (canonical units/money math, the whole data layer, a scheduler). See the
  reject-over-engineering table in `references/right-sizing.md`.

> **When multi-package (workspace).** A large app (many teams, a pure-Dart core you golden-test, a
> reusable design system) may split foundations into packages under a Dart pub **workspace**. Then:
> each member sets `resolution: workspace` with one root `pubspec.lock`; each package exposes **one
> barrel** (`core.dart`) over a private `src/` — never import another package's `src/`; the pure-Dart
> `core` package declares no `flutter` dependency so a stray import is a compile error; the DAG stays
> acyclic (`core` → nothing internal; everything → `core`; the app shell → all). This is an option a big
> app grows into, **never a requirement for a small one** — a single package with folders is the default.

## Anti-patterns

- **A `*UseCase` / domain layer wrapping one repository call.** Pure ceremony; a rename of the
  repository method. Add the layer only when logic spans repositories.
- **An `abstract interface class` whose only content is the word "Repository", over code that runs in a
  test.** The seam buys nothing; a Map-backed fake can even accept rows the real schema rejects. Test
  the concrete class against a real in-memory store.
- **Business logic, formatting, or number/unit math in a View.** Move it to the ViewModel or `core`.
- **`http`/`sqflite`/`SharedPreferences`/a plugin called inside `build()` or `initState()`.** Data
  access belongs behind a repository, reached through a provider.
- **Persist-after-publish / optimistic write before the commit returns.** A crash in the gap credits
  state that never saved. Persist first, then the stream republishes.
- **A stored counter mirroring derivable data** (a `count` column next to the rows). It drifts. Derive
  it from the source of truth.
- **A ViewModel importing `package:flutter/material.dart` for `BuildContext`/widgets.** ViewModels are
  UI-framework-light; passing `BuildContext` into the data layer is worse.
- **`get_it`/`injectable`/`package:provider` as a second DI container alongside Riverpod, or a global
  singleton / `static` mutable store reached from a widget.** Providers are the one DI mechanism.
- **A cross-feature import** creating a cycle. Share via a foundation layer or navigate by route ID.
- **Splitting a small app into packages "to be clean".** Multiplies pubspecs and codegen for zero
  compile-time guarantee. Promote to a package only for a load-bearing wall.

## Definition of done

- [ ] New code lives under the right `features/<x>/` or `core`/`data` location; grouping is feature-first.
- [ ] The View is a dumb `ConsumerWidget` — no data access, no business logic, no formatting, no `try/catch`.
- [ ] The ViewModel is a `Notifier`/`AsyncNotifier`/`StreamNotifier` exposing immutable state + intent methods; no public setters, no `notifyListeners()` in the Riverpod path.
- [ ] Every mutation routes through one repository method that persists before publishing; the watched stream re-emits (no manual republish); derived reads are streams/derived providers, not stored counters.
- [ ] Repositories map storage rows/DTOs → immutable value objects; no Drift/DTO/`Map` type reaches a ViewModel or widget.
- [ ] Interfaces exist only where the real impl can't run in a test (or a real dev/prod swap); each earns a named fake.
- [ ] Dependencies are injected via providers from a composition root; no new globals/singletons; no `DateTime.now()` outside an injected clock.
- [ ] A domain/use-case layer was added only if logic spans repositories; the app is a single package unless a compile wall is load-bearing.
- [ ] `scripts/check_architecture.sh` passes; `dart analyze` is clean.

## Related skills

- See `state-management-riverpod` for the Notifier/AsyncNotifier API, watch/read/listen split, `family`+`autoDispose`, and stale-closure hazards.
- See `widget-composition` for the deep dive on building the dumb View (rule 5): const widget classes over `_buildX()` helpers, lean `build()`, and where the widget sits in this layer DAG.
- See `scaffold-feature-module` for the step-by-step feature folder + typed go_router registration workflow.
- See `project-structure-and-packages` for pubspec-as-audit-artifact, barrels, and one-way layering mechanics.
- See `app-startup-and-bootstrap` for main() ordering, global error handlers, and DI overrides at the root.
- See `error-handling-typed-results` for the sealed `Result`/`Failure` spine returned across boundaries.
- See `dart3-idioms-and-coding-standards` for sealed types, exhaustive switches, and immutable value types.
- See `naming-conventions` for the `Screen`/`Notifier`/`Repository`/`Service`/`Failure` role suffixes a grep can read.
- See `persistence-drift` for the DAO/repository seam and transaction-per-mutation persistence.

## References

- [Flutter — Guide to app architecture](https://docs.flutter.dev/app-architecture/guide)
- [Flutter — Architecture recommendations](https://docs.flutter.dev/app-architecture/recommendations)
- [Flutter — UI layer case study (what a dumb View may contain)](https://docs.flutter.dev/app-architecture/case-study/ui-layer)
- [Flutter — Offline-first support (local store authoritative)](https://docs.flutter.dev/app-architecture/design-patterns/offline-first)
- [Riverpod 3 documentation](https://riverpod.dev)
- [Dart — Pub workspaces (monorepo support)](https://dart.dev/tools/pub/workspaces)

## Provider / ChangeNotifier appendix

The same rules map onto the official Flutter-guide stack (`package:provider` + `ChangeNotifier`) when
a codebase uses it instead of Riverpod. Rules 1–9, 11, 12 are unchanged. Only the "how" of state + DI
differs:

- **ViewModel = `ChangeNotifier`.** It still holds **private mutable fields** and exposes intent
  methods; after a real state change it calls `notifyListeners()` **once** — never inside `build()` and
  never in a tight loop. Expose state via getters that return unmodifiable views (`List.unmodifiable`).
  Immutability still applies to the domain models the ViewModel holds (`copyWith`, value equality).
- **DI = constructor injection wired through `provider` near the root.** A `MultiProvider` at the app
  root creates services and repositories; a screen's `ChangeNotifierProvider` builds its ViewModel from
  `context.read<XRepository>()`. Depend on the **abstract** repository type so tests inject a fake.
- **Read vs listen:** `context.watch<T>()` / `Consumer` to rebuild on change; `context.read<T>()` in
  callbacks. Never pass `BuildContext` down into the data layer to read providers — pass the data.
- The bans still hold: no `get_it`/service locator reached from a widget, no global mutable state, no
  data access in a View. Everything else in this skill (layering, single write path, derive-don't-store,
  map-at-the-boundary, abstract-only-what-you-can't-test, folder-vs-package) is identical.
