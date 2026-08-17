---
name: flutter-conventions-index
description: The repo front-door for a Flutter/Dart app — the cross-cutting house rules (feature-first layered MVVM, immutable state with a single write path, Riverpod 3.x for state + DI, typed Result/Failure errors, dumb widgets, injected side effects, complexity limits) plus a routing table that sends each task to its deep-dive skill and a recommended feature build order. Use at the start of any Flutter/Dart work, before writing or reviewing a feature, when deciding which layer or package code belongs in, when unsure which skill governs a task (architecture, state, widgets, persistence, testing, i18n, design), or when onboarding to the conventions.
---

# Flutter Conventions — Index

The front door for this Flutter/Dart app. It states the cross-cutting **house rules** every task obeys, then **routes each concern to a focused skill**. For any non-trivial task: apply the rules here, then open the specialized skill for depth. This is the only skill that names every other skill in the library.

Assumes a **single-package Flutter app** by default. Monorepo / pub-workspace guidance is fenced inside the skills that own it (`project-structure-and-packages`, `codegen-and-toolchain`) — never required for a small app.

## Non-negotiable rules

1. **Feature-first, layered, downward-only.** Group by feature (a folder), then by layer: View → ViewModel → Repository → Service/data. Lower layers never import upward; the dependency graph is a strict DAG. WHY: an acyclic downward graph is the only structural guard against a big ball of mud. *(`flutter-architecture`, `project-structure-and-packages`)*
2. **Widgets are dumb.** No business logic, data access, math, or formatting in a widget — it reads state and renders. WHY: logic in `build()` is untestable and rebuilds unpredictably. *(`widget-composition`)*
3. **One ViewModel per screen, over immutable state.** A single `Notifier`/`AsyncNotifier` owns private mutable state and exposes it as an immutable value with value equality; a transition assigns a new state, never mutates in place. WHY: immutable value + single owner makes every change diffable and testable. *(`state-management-riverpod`)*
4. **Riverpod 3.x is state + DI.** Modern `Notifier`/`AsyncNotifier`/`Future`/`Stream` providers only; providers are the DI container. No `get_it`, no `package:provider`, no legacy `StateProvider`/`StateNotifierProvider`/`ChangeNotifierProvider`. WHY: one composition model, no second DI framework to reconcile. *(`state-management-riverpod`, `app-startup-and-bootstrap`)*
5. **Single write path.** A widget or ViewModel never mutates persisted state directly; every mutation is a repository method that persists first, then republishes via a stream. WHY: one durable, observable route means state is never half-written. *(`state-management-riverpod`, `persistence-drift`)*
6. **Derive, don't store; depend on abstractions.** Compute derived values on read instead of caching a second copy; program against interfaces you inject, not concretes. WHY: a duplicated source of truth drifts out of sync; injected seams keep code testable. *(`flutter-architecture`, `service-boundary-and-native`)*
7. **Immutable models, typed errors.** Domain and UI state are `freezed`/sealed value types with `copyWith` and value equality. Pure functions are **total** — they return uncertainty, never throw. Recoverable I/O returns a sealed `Result<T, F extends Failure>`, switched exhaustively; never a swallowed `catch (_) {}`. WHY: the compiler enforces every case; failures carry a stable code, not a localized string. *(`error-handling-typed-results`, `dart3-idioms-and-coding-standards`)*
8. **Side effects behind injected interfaces.** Every platform/native effect (clock, notifications, share, analytics, storage) is a Dart interface behind a provider, overridden once at the composition root, faked in tests. Read "now" from an injected `Clock`, never `DateTime.now()`. WHY: a global side effect is a non-deterministic, untestable dependency. *(`service-boundary-and-native`, `value-objects-money-and-units`)*
9. **Async is never silent.** `await` everything or handle the `Future` explicitly; no fire-and-forget arrow callbacks. Guard `BuildContext`/`mounted` after every `await`; dispose controllers, subscriptions, timers, and sinks. WHY: a dropped `Future` swallows errors no lint catches. *(`async-safety`)*
10. **Small units, extracted widget classes.** Keep to the complexity-limit table owned by `dart3-idioms-and-coding-standards` (method ≤30, `build()` ≤80, file ≤300, positional params ≤3, logic nesting ≤3 — widget build trees may nest to ≤5 as the stated exception). Extract `const` `StatelessWidget` classes, never `_buildX()` methods; `const` everywhere legal. WHY: small const subtrees rebuild less and read faster. *(`dart3-idioms-and-coding-standards`, `widget-composition`, `flutter-performance`)*
11. **Names carry roles.** `…Screen`/`…Notifier`/`…Repository`/`…Service`/`…Failure`; Effective-Dart casing verbatim; full words with units in the name; file named after its primary declaration. WHY: a grep or a filename should reveal the layer. *(`naming-conventions`)*
12. **RTL and a11y by construction.** Use directional (`start`/`end`) geometry only, never hardcoded left/right; every user string comes from an ARB via `gen_l10n`; label and role every semantic node; never clamp the text scaler or rely on color alone. WHY: correctness properties are cheap to build in and expensive to retrofit. *(`i18n-rtl-l10n`, `accessibility-as-code`)*
13. **Test the shape of the code, not a fixed ratio.** Pure core: fast, clock-injected `package:test` + property invariants. Everything else: `flutter_test` + `mocktail`, `ProviderContainer.test()` + `overrideWith` — fake the repository/services, not the `Notifier`. One acceptance test anchors the whole app. WHY: tests follow risk; the pure core carries the invariants. *(`testing-strategy`, `widget-golden-and-a11y-testing`)*
14. **Strict lint is the floor; format is not negotiable.** `dart format` clean and `dart analyze --fatal-infos` green before every PR, on a version-pinned `very_good_analysis` include with `strict-casts`/`strict-raw-types`. WHY: a green analyzer is the cheapest correctness signal you have. *(`lint-and-style-config`, `dependency-hygiene`)*

## Route to the right skill

| When you are… | Open |
|---|---|
| Orienting, unsure which skill governs the task | `flutter-conventions-index` (this) |
| Deciding layers, features-vs-packages, the dependency DAG | `flutter-architecture` |
| Scaffolding packages, barrels, `lib/` vs `lib/src/`, workspace layout | `project-structure-and-packages` |
| Writing `main()`, error handlers, DI overrides, warm-up, app-lifecycle flush-on-background/resume | `app-startup-and-bootstrap` |
| Writing a `Notifier`/`AsyncNotifier`, `family`/`autoDispose`, the single write path | `state-management-riverpod` |
| Building or refactoring UI, writing `build()`, layout/insets | `widget-composition` |
| Configuring the app router, redirects/auth guards, deep links, nav shells, transitions, PopScope, 404 | `navigation-and-routing` |
| Building a `Form`, sync/async field validation, focus traversal, keyboard actions, input formatters | `forms-and-input` |
| Rendering loading/empty/error states, snackbars, banners, dialogs, Undo, retry | `ui-states-and-feedback` |
| Responsive breakpoints, large-screen/tablet/foldable master-detail, `NavigationRail`-vs-`BottomNavigationBar` by width | `adaptive-layout` |
| Choosing a Dart 3 construct (sealed, records, class modifiers) | `dart3-idioms-and-coding-standards` |
| Naming a class/file/variable/boolean | `naming-conventions` |
| Configuring `analysis_options.yaml`, lint severity | `lint-and-style-config` |
| Fixing jank, narrowing rebuilds, lazy lists, off-isolate work | `flutter-performance` |
| Writing `///` doc comments on the public surface | `dartdoc-conventions` |
| Writing async code, guarding `context`/`mounted`, disposal | `async-safety` |
| Modeling errors, `Result`/`Failure`, never-lose-data flows | `error-handling-typed-results` |
| Writing unit/widget tests, setting up fakes | `testing-strategy` |
| Writing golden, layout, RTL, or accessibility widget tests | `widget-golden-and-a11y-testing` |
| Adding a Drift table, DAO, or `.watch` stream | `persistence-drift` |
| Writing a forward-only schema migration | `run-migration` |
| Exporting, backing up, sharing, importing, or restoring user data | `data-export-and-restore` |
| Setting up `build_runner`, `build.yaml`, generated-code policy | `codegen-and-toolchain` |
| Running codegen before analyze | `run-codegen` |
| Writing the GitHub Actions CI pipeline and gates | `ci-pipeline-and-gates` |
| Adding ARB strings, ICU plurals, RTL geometry | `i18n-rtl-l10n` |
| Authoring `Semantics`, targets, traversal, text scaling | `accessibility-as-code` |
| Modeling money, units, dates in a pure core | `value-objects-money-and-units` |
| Building on-device reminders/notifications | `local-notifications-scheduler` |
| Writing a `CustomPainter` + gesture hit-testing | `custom-canvas-and-gestures` |
| Adding an animation, a haptic, a celebration, or a success/error moment | `motion-and-haptics` |
| Generating content from a seed or date every device must reproduce identically | `seeded-determinism-and-golden-vectors` |
| Adding ads, a rewarded earn loop, a paywall, or an entitlement gate | `ads-and-iap-monetization` |
| Wiring a native channel or platform side effect | `service-boundary-and-native` |
| Editing `pubspec`/lockfile, auditing a new dependency | `dependency-hygiene` |
| Scaffolding a whole feature module end to end | `scaffold-feature-module` |
| Structuring tokens → theme → components (no aesthetic values) | `design-system-structure` |
| Re-baselining committed golden images | `run-goldens-rebaseline` |
| Running the once-per-app design/QA review before release | `design-review-workflow` |
| Cutting a release: versioning, signing, symbols, store declarations, rollout | `release-and-store-shipping` |

## Recommended order when building a feature

1. **Model + pure functions** — immutable value types; total, clock-injected core → `dart3-idioms-and-coding-standards`, `value-objects-money-and-units`
2. **Data layer** — repository = single source of truth / single write path; Drift table + DAO if persisted → `persistence-drift`, `error-handling-typed-results`
3. **Service seams** — every side effect behind an injected interface → `service-boundary-and-native`
4. **ViewModel** — `Notifier`/`AsyncNotifier`, `family`/`autoDispose`, intent methods → `state-management-riverpod`
5. **View + widgets** — dumb `ConsumerWidget`, small `const` widget classes, forms, responsive layout, RTL-safe geometry, and the loading/empty/error states before the happy path is called done → `widget-composition`, `ui-states-and-feedback`, `forms-and-input`, `adaptive-layout`, `i18n-rtl-l10n`, `accessibility-as-code`
6. **Wire DI + routing** — providers overridden at the composition root; the feature route registers into the single `go_router` → `app-startup-and-bootstrap`, `navigation-and-routing`, `scaffold-feature-module`
7. **Docs + tests** — `///` on the public surface; core invariants + container/widget tests with fakes → `dartdoc-conventions`, `testing-strategy`, `widget-golden-and-a11y-testing`
8. **Profile, then the CI gate** — measure in profile mode; format/analyze/codegen/test green → `flutter-performance`, `codegen-and-toolchain`, `ci-pipeline-and-gates`
9. **Review, then ship** — one end-of-build design/QA pass, then the release artifact: versioning, signing, archived symbols, store declarations, staged rollout → `design-review-workflow`, `release-and-store-shipping`

Throughout: `naming-conventions` and `lint-and-style-config` keep every line honest.

## Baseline project setup

```yaml
# analysis_options.yaml
include: package:very_good_analysis/analysis_options.yaml   # pin the version in pubspec
analyzer:
  language:
    strict-casts: true
    strict-raw-types: true
```

```bash
# The PR gate (mirror in CI — see ci-pipeline-and-gates)
dart run build_runner build --delete-conflicting-outputs   # if the app uses codegen
dart format --set-exit-if-changed .
dart analyze --fatal-infos --fatal-warnings
flutter test
```

## The shape every feature repeats

```dart
// Repository = the SINGLE WRITE PATH: persist first, then observers re-emit.
class OrderRepository {
  OrderRepository(this._db, this._clock);
  final AppDatabase _db;
  final Clock _clock;

  /// The only route an order reaches storage. Returns a typed Result, never throws.
  Future<Result<void, PersistFailure>> place(OrderDraft draft) async {
    try {
      await _db.transaction(() async {
        await _db.orderDao.insert(draft.toRow(_clock.now())); // durable FIRST
      });
      return const Ok(null); // watchers over the DAO re-emit on commit
    } on DriftException catch (e, s) {
      return Err(PersistFailure.write(cause: e, stack: s));
    }
  }
}

// ViewModel = one StreamNotifier per screen; state tracks EVERY DAO emission.
// Riverpod 3.x: extend the unified base class, opt into autoDispose on the provider.
class OrderListNotifier extends StreamNotifier<List<Order>> {
  @override
  Stream<List<Order>> build() =>
      ref.watch(orderRepositoryProvider).recent(); // re-emits on every commit

  Future<void> place(OrderDraft draft) async {
    final result = await ref.read(orderRepositoryProvider).place(draft);
    switch (result) {
      case Ok():        break;            // the watched stream re-emits the new state
      case Err(:final failure): state = AsyncError(failure, StackTrace.current);
    }
  }
}

final orderListProvider =
    StreamNotifierProvider.autoDispose<OrderListNotifier, List<Order>>(
  OrderListNotifier.new,
);

// View = dumb ConsumerWidget: reads one notifier, renders, no logic.
class OrderListScreen extends ConsumerWidget {
  const OrderListScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(orderListProvider).when(
      loading: () => const _OrdersSkeleton(),
      error: (e, _) => _RetryView(onRetry: () => ref.invalidate(orderListProvider)),
      data: (orders) => _OrderListView(orders: orders),
    );
  }
}
```

## Anti-patterns

- Data access or business logic inside a widget, a god-`build()`, or `_buildXxx()` helper methods — untestable and rebuild-unfriendly.
- `setState` for app/shared state; a mutable model edited by the UI — breaks the single owner + immutable-state rule.
- `get_it`/`package:provider`/legacy `StateProvider`/`StateNotifierProvider`/`ChangeNotifierProvider` — a second DI/state framework to reconcile.
- A widget or ViewModel writing a DAO directly, or "republish then persist" — bypasses the single write path and can expose half-written state.
- `DateTime.now()` in domain code — a non-deterministic dependency; inject a `Clock`.
- A swallowed error (`catch (_) {}`), an untyped exception leaking to the UI, or a fire-and-forget `Future` — silent failure no lint catches.
- Hardcoded left/right, a raw digit string, or a user-facing literal in a widget — breaks RTL and localization by construction.
- `!`/`late`/`dynamic` to dodge honest types; blanket `// ignore`; fighting `dart format` — hides the real defect.
- Optimizing without profiling, or profiling in debug mode — measures the wrong thing.

## Definition of done

- [ ] Code sits in the correct feature/layer; the dependency graph only points downward (rules 1, 6).
- [ ] The View is dumb; one `Notifier`/`AsyncNotifier` owns immutable state; no legacy provider or extra DI container (rules 2–4).
- [ ] Every mutation goes through a repository's single write path — persist, then republish (rule 5).
- [ ] Models immutable with value equality; pure functions total; recoverable I/O is `Result` + sealed `Failure`, exhaustively switched; no swallowed errors (rule 7).
- [ ] Side effects are behind injected interfaces; "now" comes from a `Clock` (rule 8).
- [ ] Async is awaited/handled; `context`/`mounted` guarded after awaits; controllers and subscriptions disposed (rule 9).
- [ ] Units within limits; widget *classes* extracted; `const` applied; names carry role + units (rules 10–11).
- [ ] RTL-safe geometry; strings in ARB; semantics labeled; text scaler not clamped (rule 12).
- [ ] Public surface has `///` docs; core invariants + container/widget tests with fakes pass (rule 13).
- [ ] `dart format` + `dart analyze --fatal-infos` clean on a pinned lint include (rule 14).
- [ ] The right specialized skill was consulted for the depth of the task.

## Related skills

Every skill in this table is a sibling; open the one the routing table points to. Start with `flutter-architecture` for where code goes, `state-management-riverpod` for how state flows, and `error-handling-typed-results` for the `Result`/`Failure` spine.

## References

- Effective Dart — https://dart.dev/effective-dart
- Flutter architecture recommendations — https://docs.flutter.dev/app-architecture
- Riverpod — https://riverpod.dev
- very_good_analysis — https://pub.dev/packages/very_good_analysis
- Flutter internationalization — https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization
