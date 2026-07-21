---
name: project-structure-and-packages
description: Enforces Flutter/Dart project scaffolding where the layout makes defects greppable — a single-package app by default (feature-first under lib/features/, shared foundation split by role in core/ data/ services/ routing/ theme/ l10n/, a thin main.dart that calls bootstrap(), no lib/src in the app), extracting a generically-named pure-Dart package only when a body of logic earns it (public barrel over private lib/src/ for PACKAGES only, meta-only deps as the compile firewall, resolution:workspace member, downward-only dependency DAG), with pubspec treated as the audit artifact and no utils/helpers/common/misc/grab-bag-shared junk-drawer folders. Use when creating any .dart file or directory, deciding where a repository/Notifier/MethodChannel/value-type/token belongs, authoring or fixing a pubspec.yaml, adding a workspace member, writing an import directive, mirroring a test under test/, or reviewing a diff for organisation.
---

# Project structure & packages

The layout is a feedback loop, not decoration: structure exists so that "what imports Flutter?", "what has no test?", and "does this feature reach into another?" are answerable by `grep` and `ls`, not by trust. Default to **one Flutter package** (the app), organised **feature-first** under `lib/features/` over a shared foundation. Reach for a second, pure-Dart package only when a body of logic earns the isolation. A `pubspec.yaml` is the audit artifact — a package cannot import what it does not declare, so the dependency list *is* the layer boundary.

This skill OWNS the physical directory tree (D1). Other skills reference it rather than drawing their own.

Read the reference for the task at hand:
- `references/single-package-layout.md` — the default one-package feature-first tree, the shared-foundation folders, placement-by-failure, the deliberately-absent list.
- `references/layering-and-dependencies.md` — the downward-only DAG, feature isolation, pubspec-as-audit, the compile-firewall insight.
- `references/workspace-and-packages.md` — when (and how) to extract a pure-Dart package: barrel-over-src, `resolution: workspace`, naming the core generically.

Run `scripts/check_structure.sh` and `scripts/check_import_boundaries.sh` before a PR. The purity check auto-detects only pure roots named `*_core`; a pure package with a plain generic name (`money`, `scheduling`) must be passed explicitly, e.g. `PURE_DIR=packages/money scripts/check_import_boundaries.sh`.

## Non-negotiable rules

1. **Single package by default.** A small-to-medium app is one Flutter package; its `pubspec.lock` is committed (it is an app, not a library). Do not add `packages/`, Melos, or a Dart workspace until a body of pure logic genuinely earns isolation (see `references/workspace-and-packages.md`). Multiplying packages before there is anything to multiply buys nothing and costs days.
2. **Feature-first inside `lib/features/`, over a shared foundation.** Each screen/surface is a folder under `lib/features/<feature>/` (`presentation/` + `<feature>_notifier.dart`; optional `application/`, `domain/`, rarely `data/`). The cross-cutting foundation splits by *technical role* at the top level — `core/` (pure), `data/` (repositories + DB), `services/` (side-effect ports), `routing/`, `theme/`, `l10n/` — because those files serve every feature. `main.dart` is a thin entry that calls `bootstrap()`; `bootstrap.dart` is the composition root; `app.dart` builds `MaterialApp.router`.
3. **No grab-bags, no unnamed nesting.** There is no hard depth cap — feature-first naturally nests (`features/orders/presentation/`). The rule is that every folder has a *named responsibility*: no `utils/`/`helpers/`/`common/`/`misc/`, no grab-bag `shared/`. `core/` is the SANCTIONED pure-foundation home, not a junk drawer.
4. **Place a class in the layer whose failure it owns.** Talks to the DB → `data/`. Talks to a platform channel → `services/native/`. A pure value type / calculator / the Clock seam → `core/` (or a feature's `domain/` if truly feature-local). Everything else → the feature that renders it. This is a deterministic rule, not taste.
5. **`pubspec.yaml` is the audit artifact — declare the audit-minimal dependency set.** An unused dependency is a review reject: it muddies the claim the manifest makes. The narrowest dep list keeps each layer boundary provable by reading one file.
6. **Dependencies point one way, downward only; features never import features.** `features → services/data → core`. No lower layer imports an upper one; no shared code imports the composition root. A feature folder NEVER imports another feature folder — share via `core`/`data`/`services` or navigate by route (see `navigation-and-routing`). A cycle is a design defect: the analyzer resolves the whole graph in one context, so an upward or cross-feature import is an error, not a runtime surprise.
7. **A pure-Dart core depends on `meta` only — the missing Flutter import is a compile firewall.** In-app, `lib/core/` holds only pure foundation (value objects, `Result`/`Failure`, the Clock seam, calculators) and reads no wall clock. Time comes from `package:clock`'s `Clock` (ambient `clock`, or a `Clock` param), never `DateTime.now()`, never a bespoke `ClockService` — see `service-boundary-and-native`. When such logic is extracted to a package, the empty-of-Flutter manifest makes a stray `Widget` or `DateTime.now()` a *build error*.
8. **One public barrel over a private `lib/src/` — for PACKAGES only.** A shared package exposes exactly one library `lib/<package>.dart` that exports the stable surface; everything else lives under `lib/src/`, which no other package may import. The **app package** uses neither barrels nor `lib/src/`: it has no external importers, and barrels add analyzer cost plus circular-import risk for zero benefit.
9. **No junk-drawer folders.** No `utils/`, `helpers/`, `common/`, `misc/`, or a grab-bag `shared/`. A helper either lives beside the type it serves (a same-file extension) or is a named service/value type with a real home. `core/` is explicitly NOT a junk drawer — it is the named pure-foundation layer.
10. **Tests mirror `lib/` 1:1.** `test/data/order_repository_test.dart` for `lib/data/order_repository.dart`. "What has no test?" then reduces to a diff of two `ls` outputs. Cross-cutting assertions that belong to no single file get their own folder (`test/policy/`); shared fakes go in `test/support/`.
11. **One primary declaration per file; filename = that declaration in `snake_case`.** `order_repository.dart` holds `OrderRepository`. The one exception: a `sealed` hierarchy lives in a single file, because that file *is* the closed set the compiler enforces.
12. **Package imports everywhere; never mix with relative.** `always_use_package_imports`. Mixing `package:` and relative paths lets the same member resolve two ways, producing two distinct runtime types. Package imports also survive file moves and are greppable.

## Default single-package tree

```
├── analysis_options.yaml   # the lint safety net (see lint-and-style-config)
├── pubspec.yaml            # pubspec.lock is COMMITTED — this is an app
├── lib/
│   ├── main.dart           # thin entry: runs bootstrap(). Nothing else.
│   ├── bootstrap.dart      # composition root: build infra, override providers, error net, runApp (see app-startup-and-bootstrap)
│   ├── app.dart            # MaterialApp.router, theme wiring, ProviderScope child
│   ├── core/               # PURE foundation, NO Flutter: value objects, Result/Failure, Clock seam, calculators
│   ├── data/               # shared data layer: Drift db, DAOs, repositories, row→model mappers
│   ├── services/           # injectable side-effect ports + impls; native/ quarantines MethodChannel
│   │   └── native/
│   ├── routing/            # the single go_router config, typed routes, guards (see navigation-and-routing)
│   ├── theme/              # ThemeExtension token sets, ColorScheme (see design-system-structure)
│   ├── l10n/               # generated AppLocalizations + ARB (see i18n-rtl-l10n)
│   └── features/           # BY FEATURE — one folder per surface
│       └── orders/
│           ├── presentation/
│           │   ├── orders_screen.dart
│           │   ├── orders_notifier.dart   # the ViewModel: a Riverpod Notifier (see state-management-riverpod)
│           │   └── widgets/
│           │       └── order_tile.dart
│           ├── application/               # OPTIONAL: use-cases spanning repositories
│           └── domain/                    # OPTIONAL: feature-local models
├── test/                   # mirrors lib/ 1:1
└── integration_test/       # only what unit/widget tests cannot reach
```

A feature's `data/` folder is usually ABSENT — features read the shared repositories in `lib/data/`. See `references/single-package-layout.md` for the full tree and the deliberately-absent list.

## Placement decision procedure

```dart
// Q: where does OrderRepository go?  A: it owns DB failure → lib/data/
class OrderRepository {
  OrderRepository(this._db);
  final AppDatabase _db;

  // Rows never escape this class; the UI is owed a value type, not a raw row.
  Future<List<Order>> loadAll() async {
    final rows = await _db.selectOrders();          // package:drift confined here
    return rows.map(Order.fromRow).toList();
  }
}
```

```dart
// Q: where does PaymentChannel go?  A: it constructs a MethodChannel → lib/services/native/
// One `grep -rn MethodChannel lib/` outside services/native/ is a review failure.
class PaymentChannel {
  static const _channel = MethodChannel('app/payment');
  Future<bool> canPay() async => await _channel.invokeMethod('canPay') ?? false;
}
```

- A widget or model reused by 2+ features moves DOWN to `lib/core/` (pure) or `lib/data/`, or up to a named shared-widget home — never into one feature's folder that another then imports.
- A new surface gets its own folder under `lib/features/` even for a single file — consistency beats saving a line. Register its route into `routing/` (see `scaffold-feature-module`, `navigation-and-routing`).
- Read platform/accessibility state (`MediaQuery.textScalerOf`) *in the widget at build time*, not via a helper file or a provider — `MediaQuery` is already reactive. App state via Riverpod; platform state via `BuildContext`. See `accessibility-as-code`.

## When to extract a package (multi-package / workspace)

Extract a **pure-Dart** package the moment a body of logic satisfies all of: it is genuinely UI-free, it is worth testing headlessly in milliseconds, and the "imports no Flutter" guarantee is worth making a build error. Typical: money/units math, entities, deterministic algorithms. Below that bar it stays in `lib/core/`.

```yaml
# packages/domain_core/pubspec.yaml — the manifest IS the purity audit
name: domain_core          # a GENERIC name — never the brand, so a rename never churns the core
publish_to: none
resolution: workspace       # member of the root workspace (modern successor to path:/overrides)
environment:
  sdk: ^3.6.0
dependencies:
  meta: ^1.15.0            # the ONLY dependency. No flutter, no dart:io, no dart:ui, no clock.
dev_dependencies:
  test: ^1.25.0            # plain `dart test` — NOT flutter_test
```

The root `pubspec.yaml` lists members under `workspace:`; there is **one** committed `pubspec.lock` at the root. The public barrel `lib/domain_core.dart` exports the stable surface; internals stay under `lib/src/`. Full ritual, dependency matrix, and gates in `references/workspace-and-packages.md`.

> **When multi-package (workspace) only.** Everything in this section — `packages/`, `resolution: workspace`, barrels, `lib/src/` — applies solely once you have decided to split. A single-package app does none of it.

## Anti-patterns

- **Splitting the shared foundation feature-first** (`orders/`, `settings/` each with their own DB + repositories). The entity graph is shared; keep repositories/DB in `lib/data/` and pure types in `lib/core/`. Feature-first applies inside `lib/features/`, not to the data graph.
- **One feature folder importing another feature folder.** It couples two surfaces that should meet only via `core`/`data`/`services` or a route. Lift the shared piece down, or navigate.
- **`utils/`, `helpers/`, `common/`, `misc/`, or a grab-bag `shared/`.** A junk drawer; every candidate belongs beside its owner or as a named type. (`core/` is fine — it is the named pure-foundation layer.)
- **Barrels or `lib/src/` in the single app package.** No external importer justifies them; they add analyzer cost and circular-import risk. `lib/src/` is a PACKAGE convention only.
- **Constructing a `MethodChannel` inside a widget or repository.** It cannot be faked and cannot be found in review. Quarantine it in `services/native/`.
- **Adding `flutter`, `dart:io`, or `DateTime.now()` to `lib/core/` or a pure core package.** It destroys the compile firewall and the headless test tier; inject the `Clock` (`package:clock`) and seed instead.
- **`path:` + `dependency_overrides` instead of `resolution: workspace`.** Defeats single-context resolution and hides the version clashes a workspace exists to surface.
- **Naming the core package after the brand** (`myapp_core`). A future rename churns every import. Name it for what it holds (`domain_core`, `money`).
- **A speculative dependency "for later."** An unused edge muddies the audit and is a review reject.
- **Mixing `package:` and relative imports.** Two import paths → two runtime types for one class.

## Definition of done

- [ ] Default is a single Flutter package; `pubspec.lock` committed; no `packages/`/Melos/workspace unless a pure body of logic earned it.
- [ ] Top level is the shared foundation (`core/ data/ services/ routing/ theme/ l10n/`); features live under `lib/features/<feature>/`; `main.dart` only runs `bootstrap()`.
- [ ] No feature folder imports another feature folder; sharing happens via `core`/`data`/`services` or a route.
- [ ] Every class sits in the layer whose failure it owns; `MethodChannel` only in `services/native/`; rows never escape `data/`; pure foundation and the Clock seam in `core/`.
- [ ] No `utils/`/`helpers/`/`common/`/`misc/`/grab-bag-`shared/` folder anywhere; `core/` is present as the named pure-foundation layer, not a catch-all.
- [ ] No `lib/src/` or barrel in the app package (they are PACKAGE conventions only).
- [ ] `test/` mirrors `lib/` 1:1; shared fakes in `test/support/`, cross-cutting checks in `test/policy/`.
- [ ] One primary declaration per file, filename = declaration in `snake_case` (sealed hierarchy the sole exception); `always_use_package_imports`.
- [ ] If a package was extracted: it is a `resolution: workspace` member, generically named, with one public barrel over `lib/src/`; a pure core declares `meta` only (no `flutter`/`dart:io`/`dart:ui`/clock); one root `pubspec.lock`.
- [ ] Dependency graph points downward only; no cross-package `lib/src/` import; deps are audit-minimal with no unused edge.
- [ ] `scripts/check_structure.sh` and `scripts/check_import_boundaries.sh` pass.

## Related skills

- `flutter-architecture` — the layered MVVM this folder shape realises (features-as-folders, foundations-as-packages, single write-path repositories); it keeps layer semantics and references this tree.
- `scaffold-feature-module` — the fixed anatomy of one `lib/features/<feature>/` folder (View + 1:1 `<feature>_notifier.dart` Notifier + scoped providers) and how it registers a route.
- `app-startup-and-bootstrap` — owns `main.dart`/`bootstrap.dart`, the composition root ordering, and the global error net.
- `navigation-and-routing` — owns `lib/routing/` (go_router config, typed routes, guards) that features register into.
- `naming-conventions` — the role suffixes (`Screen`/`Notifier`/`Repository`/`Service`/`Gateway`) and the file=primary-declaration rule referenced above.
- `dependency-hygiene` — pubspec/lock mechanics, caret ranges, auditing a transitive tree before adding a dep.
- `codegen-and-toolchain` — per-package `build.yaml` scoping and the commit-vs-gitignore decision for generated code.
- `lint-and-style-config` — the `analysis_options.yaml` that promotes `always_use_package_imports` and silent-failure lints to errors.
- `service-boundary-and-native` — the `services/native/` MethodChannel quarantine, the injectable Service/Gateway ports, and the `Clock`-via-`clockProvider` time seam.
- `value-objects-money-and-units` — the canonical resident of `lib/core/` or an extracted pure-Dart core.

## References

- Dart package layout: https://dart.dev/tools/pub/package-layout
- Dart & Flutter workspaces (`resolution: workspace`): https://dart.dev/tools/pub/workspaces
- Effective Dart — libraries & imports: https://dart.dev/effective-dart/usage#libraries
- pubspec format: https://dart.dev/tools/pub/pubspec
- Flutter architecture recommendations: https://docs.flutter.dev/app-architecture
