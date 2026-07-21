# Layering, dependencies, and the audit-by-manifest principle

## The pubspec is the audit artifact

A reviewer proves "the domain math imports no Flutter", "no analytics SDK exists outside the app shell", and "the pricing package knows nothing about the UI" by reading manifests, never by reading source. This only works if every manifest tells the whole truth, which requires two disciplines:

1. **Declare the audit-minimal dependency set.** List exactly what a package imports — no more. An unused dependency is a review reject because it makes the manifest lie about the boundary: the package *could* now import that thing, so the guarantee is gone.
2. **A package cannot import what it does not declare.** With a single-context resolver (a Dart workspace, or a single app package), an undeclared import is a static analysis error, not a runtime surprise. The dependency list therefore *is* the enforced boundary — the graph is checked by the compiler, not by a style guide.

For a single-package app the same principle applies inward: the app's `pubspec.yaml` is still the truthful list of what the whole app may touch, and the internal `features → data → core` layering is enforced by the import-boundary script rather than by pub, because pub cannot see inside one package.

## The dependency DAG points downward, always

```
     features/<feature>  (screens, widgets, notifiers)
         │  depends on
         ▼
  services / data  (repositories, seams, native channels)
         │
         ▼
    core  (value types, sealed results, calculators, the Clock seam —
         │  in-app lib/core/, or an extracted pure-Dart package)
         ▼
```

Rules that fall out of the diagram:

- **No lower layer imports an upper one.** `core/` never imports `features/`; a pure core never imports `data/`. If you feel the pull, the type is in the wrong layer.
- **No shared code imports the composition root.** The app's `main.dart` / `bootstrap.dart` / DI wiring is the *one* place allowed to depend on everything, precisely because it computes nothing — it only assembles. A shared foundation file (`core/`, `data/`) reaching up into `bootstrap.dart` is a cycle.
- **Features never import features.** Two folders under `features/` share code by lifting it down to `core`/`data`/`services`, or they meet via a route — never by one importing the other. Two extracted engines share primitives via a common core, never directly.
- **A cycle is a design defect.** The fix is never `dependency_overrides`; it is moving the shared type down to the layer both callers already depend on.

## The compile firewall: purity by missing import

The strongest boundary is the one the compiler enforces for free. A pure-Dart package that never lists `flutter` in its dependencies *cannot* accidentally import a `Widget`, a `BuildContext`, or `dart:ui` — the import simply will not resolve. Likewise, a package that lists no I/O dependency and forbids `dart:io` cannot read a file or the wall clock.

This turns three whole classes of bug into build errors:

- **A `Double` where money belongs**, or a `Widget` leaking into the math → the UI import fails to resolve.
- **A hidden `DateTime.now()`** making a "pure" function non-deterministic → forbid it by convention and grep, and take time from `package:clock`'s `Clock` (the ambient `clock`, or a `Clock` param) instead; the function's inputs then fully determine its output. See `service-boundary-and-native` for the `clockProvider` seam.
- **A platform dependency sneaking into testable logic** → it cannot compile against a Foundation/`meta`-only manifest, so the millisecond headless test tier stays intact.

The empty-of-Flutter manifest is not documentation of purity — it *is* the purity, mechanically checked. This is the single biggest reason to extract a pure-Dart package at all: not to reuse the code elsewhere, but to make the firewall real.

## Placement by failure

When you cannot decide where a class goes, ask **which failure it owns** — the answer names the layer:

| The class fails when... | it owns | so it lives in |
|---|---|---|
| SQLite rejects a write | persistence | `data/` |
| a platform channel returns an error | the native boundary | `services/native/` |
| an external service is unreachable | a side-effect seam | `services/` |
| an invariant on a value is violated | a domain shape | `core/` (or a feature's `domain/`) |
| a pixel is misplaced | rendering | `features/<feature>/presentation/` |

A class that seems to own two failures is usually two classes. A repository that both talks to SQLite *and* formats a display string owns persistence *and* presentation — split the formatting into a `core/` value type or the view.

## Naming the core generically

If you extract a domain package, name it for **what it contains**, not for the product. `domain_core`, `money`, `scheduling` — never `myapp_core` or `acme_engine`. A brand rename is common and cheap; a package rename churns every import statement in the app and every reference in every other package. The generic name also keeps the package honestly reusable and stops brand vocabulary from leaking into the layer that should know nothing about the product.

## Keeping SDKs out of shared layers

Analytics, ads, billing, and push SDKs bind at the composition root (the app shell), never in a shared package or the domain core. Shared code holds the *interface* (`AnalyticsService`, `BillingService` as abstract classes); the concrete SDK is injected by the app. This keeps the shared layers testable, keeps heavy/network-bound transitive trees out of the pure core, and — checked by a grep gate — proves by manifest that the domain has no telemetry. See `service-boundary-and-native` and `dependency-hygiene`.
