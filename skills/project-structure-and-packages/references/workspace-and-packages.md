# Extracting a package (the multi-package / workspace path)

> Everything here applies **only after** you have decided to split. A single-package app does none of it. Do not scaffold a workspace pre-emptively.

## When a body of logic has earned a package

Extract a **pure-Dart** package when all of these hold:

- the logic is genuinely **UI-free** (no `Widget`, no `BuildContext`, no `dart:ui`);
- it is worth running in a **headless millisecond test tier** (`dart test`, no widget binding, no simulator);
- the **"imports no Flutter" guarantee is worth making a build error** (money/units math, entities, deterministic algorithms, a scheduling engine).

Do **not** extract a package for:

- code that is inherently tied to the widget tree (that stays in `lib/features/`);
- a thin wrapper that would just re-export one class;
- "future reuse" with no second consumer today — that is speculation, and a package is expensive to carry.

A Flutter package (as opposed to pure Dart) is worth extracting only for genuinely reusable *presentation* — a design-system/component library shared by multiple app shells. Below that bar, keep it in the app.

## The workspace wiring

Modern Dart uses a **pub workspace**, the first-party successor to `path:` + `dependency_overrides`. The analyzer resolves every member in one analysis context, so an undeclared or upward import is an analysis error.

Root `pubspec.yaml`:

```yaml
name: my_app_workspace_root   # no application code lives here
publish_to: none
environment:
  sdk: ^3.6.0
workspace:
  - packages/domain_core       # pure Dart
  - packages/design_system     # Flutter presentation (only if genuinely reused)
  - app                        # the thin app shell / composition root
```

- There is **one committed `pubspec.lock`**, at the root. Do not commit per-package locks.
- Every member declares `resolution: workspace` and `environment: sdk: ^3.6.0` or higher (workspaces require it on all members).
- Never wire members with `path:` + `dependency_overrides` — it defeats single-context resolution and hides version clashes the workspace exists to surface.

## The pure-core manifest is the audit evidence

```yaml
# packages/domain_core/pubspec.yaml
name: domain_core              # GENERIC name — never the brand
description: Pure-Dart domain logic — no Flutter, no I/O, clock and seed injected.
publish_to: none
resolution: workspace
environment:
  sdk: ^3.6.0                  # NO flutter: line — its absence is the purity audit
dependencies:
  meta: ^1.15.0               # the ONLY dependency
dev_dependencies:
  test: ^1.25.0               # plain `dart test`; NOT flutter_test
# Deliberately absent: flutter, dart:io, dart:ui, any clock. The grep gate proves it.
```

A Flutter package instead pins `flutter: ">=3.x.0"` in `environment` and depends on `flutter: { sdk: flutter }`; the deliberate presence/absence of that line is itself the classification.

## Barrel over `lib/src/`

A package exposes **exactly one** public library and hides everything else:

```dart
// packages/domain_core/lib/domain_core.dart — the only public entry point
library;

export 'src/money.dart' show Money, Currency;
export 'src/allocate.dart' show allocate;
export 'src/order.dart' show Order, OrderLine;
// src/rounding.dart and other internals stay package-private under lib/src/.
```

- Other packages import `package:domain_core/domain_core.dart` and get only the stable surface.
- No package may import another package's `lib/src/`. The barrel is the contract; `lib/src/` is the implementation. The import-boundary script enforces this because pub alone cannot.
- One primary type per `lib/src/` file, filename = the type in `snake_case`; a `sealed` hierarchy is the one exception (the file is the closed set).

## The dependency matrix (generic)

State the allowed edges explicitly so the manifest and reality agree:

| Package | May depend on | Must never depend on |
|---|---|---|
| `domain_core` (pure) | `meta` only | anything else — that is the entire audit |
| a second engine/module | `meta` + `domain_core` | another engine, the UI, Flutter |
| `design_system` (Flutter presentation) | `flutter` + l10n only | `data`, the domain core internals, any engine |
| shared data/service layer | `flutter`, Riverpod, ORM, `domain_core` | any concrete UI package, any analytics/ads SDK |
| `app` (composition root) | everything, plus the flavor SDKs | — it is the one node allowed to know all |

Edges point one way: `app → shared → domain_core`. No shared package imports the app; no engine imports another; presentation imports no data layer.

## The gates that keep it honest

Before pushing a new or changed manifest, all of these must be green (run identically locally and in CI — see `ci-pipeline-and-gates`):

- `dart pub get` at the root — the workspace resolves with no clash and **no `dependency_overrides`**.
- `dart analyze` clean across the whole context.
- The structure/import scripts in this skill: no cross-package `lib/src/` import, no `flutter`/`dart:io`/`dart:ui`/`DateTime.now()` inside a pure package, no junk-drawer folders.
- Any per-layer SDK bans (e.g. no analytics SDK outside the app shell) as grep gates.

## Tests still mirror source 1:1

Each package carries its own `test/` mirroring its `lib/` (or `lib/src/`) tree, run with `dart test` for pure packages and `flutter_test` for Flutter packages. "What has no test?" stays a diff of two `ls` outputs, per package. Never pull `flutter_test` into a pure package to borrow a matcher — it forfeits the fast headless tier that was the reason to extract the package.
