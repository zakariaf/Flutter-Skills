# Module & layers — the shape, the DAG, folder-vs-package, barrels

The layer model, the feature-folder anatomy, the dependency graph, and the continuum from a
single-package app to a multi-package workspace. Grounded in Flutter's *Guide to app architecture*.

## The layer model

MVVM with an optional domain layer:

| Layer | Contents | May import |
| --- | --- | --- |
| **UI (features)** | Views (dumb widgets) + one ViewModel (`Notifier`/`AsyncNotifier`/`StreamNotifier`) per feature + feature-local widget classes, under `presentation/` | domain, data, core |
| **Domain** *(optional)* | Use-cases and pure calculators, added **only when logic spans repositories** | data (interfaces), core |
| **Data** | Repositories (single source of truth + single write path), services, database/DAOs, immutable domain models | core |
| **Core** | Value objects, `Result`/`Failure`, `Clock`, pure functions, shared dumb widgets | nothing above it |

Imports **only ever point down**. A layer never imports a layer above it. The domain layer is the one
you earn last: Flutter's reference sample ships ~2 use-cases across ~111 files.

## Feature-folder anatomy (single package)

`project-structure-and-packages` owns the physical tree; a feature's Views and its one ViewModel live
under `presentation/`.

```text
features/tasks/
  presentation/
    task_list_screen.dart    # View — ConsumerWidget, dumb
    task_list_notifier.dart  # ViewModel — StreamNotifier over immutable state
    widgets/                 # widget CLASSES used only by this feature
  # application/ + domain/   # ADDED ONLY when logic spans multiple repositories / needs local models
  # data/ usually ABSENT     # features read shared repositories from lib/data/
```

Most features are **View + ViewModel only**, reading shared repositories from `data/`. A feature that
needs a use-case (an aggregation, a multi-repo workflow) grows a local `application/` folder; a feature
with its own models grows a local `domain/` folder. Never manufacture these by default.

**Layer-first at the top, feature-first inside.** Cross-feature foundations (`core/`, `data/`) sit at
the top because they serve every feature; screens are grouped by feature so one feature is one folder.
Do **not** invert this into a global `presentation/` + `domain/` + `data/` split at the root — that
smears every feature across three trees.

**No hard depth cap — feature-first naturally nests** (`features/tasks/presentation/`). The real rule
is **no grab-bags and no unnamed nesting**: a `features/tasks/view_models/task_notifier.dart` split is
depth for its own sake, but `presentation/` / `application/` / `domain/` are named, load-bearing layers.
Directories are free; only meaningless depth is a tax.

**Name folders after the SDK's grain.** Use `core/widgets/` or `core/ui/`, never `lib/widgets/` (it
collides with the Flutter SDK). Never a `utils/`, `shared/`, or `common/` junk drawer — name the file
after what it does (`title_formatter.dart`, not `string_utils.dart`) and put cross-cutting code in
`core/`.

## The dependency DAG

```text
core  ──────────────►  (nothing internal; the floor)
data / domain  ─────►  core
features  ──────────►  domain, data, core
app shell (main/bootstrap/app)  ─►  everything
```

A feature folder **never imports another feature folder**. To reach another feature's screen, navigate
by route **ID** (`const TaskDetailRoute(taskId: id).go(context)`) — that carries no compile-time
coupling. To share data, go through `core`/`data`. A circular provider dependency throws at runtime, so
keep the graph acyclic.

## When something earns a package vs a folder

For a small-to-medium **single-package** app, the answer is almost always "a folder / a file". Extract
to a package only when a **compile-time wall is load-bearing** — a wall whose absence would let a bug
through the compiler, analyzer, and tests (the only things that notice on an app with no telemetry).

| Situation | Verdict |
| --- | --- |
| A new screen/flow (a list, a detail, an editor, an onboarding step) | **Folder** under `features/`. |
| A helper two features want to share | **File in `core/`** (if pure) or the relevant `data/` area — never a cross-feature import, never a new package. |
| Canonical unit/money math, pure calculators, `Result`/`Failure`, the `Clock` port | **`core/`** (a package only in a workspace, see below). |
| Any database table, DAO, repository, migration, backup | **`data/`**. |
| A reusable design system consumed by multiple apps | A **package** — but only once there are multiple apps. |

Rejected structural alternatives: a flat bucket of `screens/` + `models/` (no feature locality);
layer-first global folders (smears features); a package per feature (pubspec + codegen churn for zero
compile guarantee); dogmatic per-screen Clean Architecture (boilerplate tax on CRUD).

## When multi-package (workspace)

A large app grows into a **Dart pub workspace** when foundations become genuinely reusable or need a
compile wall — e.g. a pure-Dart `core` you golden-test, a full `data` layer, a design system shared
across app targets. This is an option a big app grows into, **never a requirement for a small one**.

```text
my_app/
  pubspec.yaml            # workspace: [app, packages/*]
  pubspec.lock            # ONE shared lockfile at the root — no per-package lockfiles
  app/                    # the runnable Flutter shell: features + bootstrap + routing
    pubspec.yaml          # resolution: workspace
  packages/
    core/                 # PURE Dart: value objects, Result/Failure, Clock, calculators
    data/                 # database, DAOs, repositories, models
    design_system/        # theme + directional widgets (structure, not aesthetic values)
```

Workspace rules:

- **Every member sets `resolution: workspace`;** one `pubspec.lock` at the root. A missing
  `resolution: workspace` silently breaks resolution.
- **One barrel per package.** Each package exposes a single entry point (`core.dart`) with
  `export 'src/...' show ...;`. `src/` is private by convention — **never import another package's
  `src/` path**.

```dart
// packages/core/lib/core.dart — the only entry point consumers import.
export 'src/result/result.dart' show Result, Ok, Err, Failure;
export 'src/time/clock.dart'    show Clock;
export 'src/money/money.dart'   show Money;
// src/ is private-by-convention; nothing else is exported.
```

- **`core` declares no `flutter` dependency,** so a stray Flutter import inside it is a compile error,
  not a review nit — that is the wall that keeps the pure layer pure.
- **The DAG still holds:** `core` → nothing internal; `data`/`design_system` → `core`; the app shell →
  all. Acyclic.
- **Keep the package set small and stable.** Adding a package is an architecture decision, not a
  convenience. See `project-structure-and-packages` for the full workspace mechanics.

## Naming

`HomeScreen`, `TaskListNotifier`, `TaskRepository`, `AppDatabase`. Role suffixes make a name (or a
grep) reveal the layer. See `naming-conventions` for the full scheme.
