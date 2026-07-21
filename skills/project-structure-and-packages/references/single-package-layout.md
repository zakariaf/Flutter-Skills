# The default single-package layout

Most apps are one Flutter package. This is not a compromise you outgrow quickly — a one-screen-to-several-screen app with an on-device data layer, a handful of services, and no shared-library consumers has nothing to gain from packages and a real cost to pay for them (extra manifests, extra `pubspec.lock` reasoning, slower `pub get`, indirection on every jump-to-definition). Extract a package only when `references/workspace-and-packages.md` says a body of logic has earned it.

## Feature-first inside `lib/features/`, over a shared foundation

The tension is real, so name it precisely:

- **Feature folders serve exactly one surface**, so `lib/features/` splits by feature. An `OrdersScreen` and its `OrdersNotifier` belong to the orders surface and nowhere else. The screen, its ViewModel, its widgets, and any feature-local models sit together under `lib/features/orders/`.
- **Foundation folders serve every feature**, so they split by *technical role* at the top level. `OrderRepository`, `AppDatabase`, the `Money` value type, and a pure `pricing` calculator are not "the orders feature" — every surface reads and writes the same data graph and the same primitives. They live in `core/` and `data/`, never inside a feature.

The mental model: *the entity graph is the data layer*. When six tables join into one displayable object, "the orders feature" and "the customers feature" cannot own separate data folders without a shared join folder — so the data graph stays in `lib/data/` and features read it. **A feature folder never imports another feature folder**: two features share code by lifting it down to `core`/`data`/`services`, or they meet only via a route (see `navigation-and-routing`).

## The full tree

```
├── analysis_options.yaml     # lint safety net; silent-failure lints promoted to error
├── build.yaml                # codegen scoping, if using build_runner
├── pubspec.yaml
├── pubspec.lock              # COMMITTED — an app pins its world; a fresh clone must build
├── lib/
│   ├── main.dart             # thin entry: runs bootstrap(). Nothing else.
│   ├── bootstrap.dart        # composition root: build infra, override placeholder providers,
│   │                         #   install the global error net, runApp (see app-startup-and-bootstrap)
│   ├── app.dart              # MaterialApp.router, theme wiring, the ProviderScope child
│   ├── core/                 # PURE foundation — NO Flutter, NO dart:io, NO wall clock
│   │   ├── result.dart                 # Result<T, F extends Failure> + Failure taxonomy (see error-handling-typed-results)
│   │   ├── clock.dart                  # the Clock seam: package:clock, injected via clockProvider — never DateTime.now()
│   │   ├── money.dart                  # a value object (see value-objects-money-and-units)
│   │   └── pricing.dart                # a pure calculator
│   ├── data/                 # shared data layer — every feature reads it
│   │   ├── database/
│   │   │   ├── app_database.dart        # schema + migrations
│   │   │   ├── app_database.g.dart       # generated (commit decision: codegen-and-toolchain)
│   │   │   ├── tables.dart
│   │   │   └── connection.dart           # file-system concern: where the DB lives
│   │   ├── order_repository.dart         # the ONLY door to order data
│   │   ├── settings_repository.dart
│   │   └── seed/
│   │       └── starter_data.dart         # first-launch content as const Dart, not a JSON asset
│   ├── services/             # injectable side-effect ports + live impls
│   │   ├── share_service.dart            # a [Concern]Service interface — a capability you define
│   │   ├── notification_gateway.dart     # a [Concern]Gateway — a thin wrapper over a specific plugin
│   │   └── native/
│   │       └── payment_channel.dart      # EVERY MethodChannel construction lives here
│   ├── routing/              # the single go_router config (see navigation-and-routing)
│   │   ├── app_router.dart
│   │   └── routes.dart                   # typed routes + guards
│   ├── theme/                # ThemeExtension token sets, ColorScheme (see design-system-structure)
│   ├── l10n/                 # generated AppLocalizations + ARB (see i18n-rtl-l10n)
│   └── features/             # BY FEATURE — one folder per surface
│       ├── orders/
│       │   ├── presentation/
│       │   │   ├── orders_screen.dart
│       │   │   ├── orders_notifier.dart  # the ViewModel: a Riverpod Notifier
│       │   │   ├── order_providers.dart  # providers scoped to this surface
│       │   │   └── widgets/
│       │   │       └── order_tile.dart
│       │   ├── application/              # OPTIONAL: use-cases, only when logic spans repositories
│       │   └── domain/                   # OPTIONAL: feature-local models
│       └── settings/
│           └── presentation/
│               └── settings_screen.dart
├── test/                     # mirrors lib/ 1:1
│   ├── data/ ...
│   ├── features/ ...
│   ├── support/              # shared fakes + pumpApp harness
│   └── policy/               # cross-cutting: "no widget clamps text scale", manifest checks
└── integration_test/         # only what unit/widget tests cannot reach
```

A feature's own `data/` folder is usually ABSENT — features read the shared repositories in `lib/data/`. Add a feature-local `domain/` or `application/` folder only when the feature genuinely owns models or use-cases that no other surface touches.

## Placement rules, restated as a lookup table

| The class... | goes in | because it owns |
|---|---|---|
| talks to SQLite / the ORM | `lib/data/` | persistence failure |
| constructs a `MethodChannel` | `lib/services/native/` | the platform boundary |
| wraps a side effect you define the interface for | `lib/services/` (a `Service`) | an external seam |
| wraps a specific plugin/SDK | `lib/services/` (a `Gateway`) | that plugin boundary |
| is a pure value type / calculator / the Clock seam | `lib/core/` | a domain shape / primitive |
| is a model only one feature uses | `lib/features/<f>/domain/` | that surface's vocabulary |
| renders or drives one screen | `lib/features/<feature>/presentation/` | that surface |

Naming of the `Service` vs `Gateway` distinction is owned by `naming-conventions`; the injectable-port pattern by `service-boundary-and-native`.

## What gets an interface (and what does not)

**Abstract exactly what cannot run in a plain `flutter test` / `dart test`.** That is the platform seams — a `ShareService`, a `NotificationGateway`, a native channel — because a fake is the only way to exercise the code that calls them. Do **not** put an interface in front of a repository you can test against a real in-memory database: a `Map`-backed fake happily accepts a row the real `PRIMARY KEY`/`CHECK` constraints would reject and never runs a migration, so it tests nothing the real thing does. Test the repository against `NativeDatabase.memory()` (real sqlite3) and skip the interface. See `testing-strategy` and `persistence-drift`.

## Constants and tokens live next to what they constrain

- Design tokens (colours, spacing, radii) live in `lib/theme/` and are the *only* place raw values appear — enforce it, don't promise it (see `design-system-structure` and `scripts/check_structure.sh`).
- A default id or a timeout lives beside the provider or on the private static of the service that reads it. There is no `lib/constants.dart` catch-all.
- Do not bake a domain limit into a hardcoded `const` or a `CHECK` if it is genuinely configurable — a "rows must be < 4" baked into a primary key turns a future requirement change into a schema migration.

## Deliberately absent — do not add these to a small app

| Absent | Why |
|---|---|
| `lib/src/` | A package convention. An app has no external importers. |
| Barrel files (`data.dart`, `ui.dart`) | Measurable analyzer cost + circular-import risk, near-zero benefit at app scale. |
| `lib/utils/` / `lib/helpers/` / `lib/common/` / `lib/misc/` / grab-bag `lib/shared/` | Junk drawers. Every candidate belongs beside its owner or in `core/`. |
| a feature `data/` folder | Features read the shared repositories in `lib/data/`; add one only for a genuinely feature-local store. |
| `use_cases/` in every feature | If every use-case wraps exactly one repository call, it is ceremony. Add `application/` only when a use-case genuinely orchestrates several repositories. |
| `packages/` + Melos | Nothing to multiply until logic earns a package. |
| `main_dev.dart` / `main_staging.dart` | Add only with a real second environment (network, auth, flavors). |
| A `Result<T, F>` type "just in case" | Adopt it when there are multiple error boundaries worth a typed vocabulary (see `error-handling-typed-results`), not reflexively. |

Every row here is a *default to omit*, not a ban — each becomes correct at a size this table's app has not reached. The discipline is adding them when the pain is real, not in anticipation. (`core/` is NOT on this list: it is a first-class layer, present from the start.)

## Generated code

Committing `.g.dart` is a legitimate choice for an app: a fresh `git clone && flutter run` works with no `build_runner` round-trip, and for an ORM the generated code *is* the schema, so a migration diff shows the real delta. Mark them `*.g.dart linguist-generated=true` in `.gitattributes` and guard staleness with one CI step — `dart run build_runner build --delete-conflicting-outputs && git diff --exit-code`. The gitignore-instead choice is equally valid; the decision and its trade-offs live in `codegen-and-toolchain`.
