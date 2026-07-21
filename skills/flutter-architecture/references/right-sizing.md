# Right-sizing — reject over-engineering, abstract only what you can't test

The counterweight to "good architecture" checklists. Almost every abstraction that reads as clean was
written for a team of ten and a network boundary. On a small app with one developer and no telemetry,
the compiler, the analyzer, and the test suite are the entire feedback loop — so **every layer that
carries no load is another place a bug hides from the only three things that can see it.**

## The one rule everything derives from

**Abstract exactly what cannot run in a test. Nothing else.** Adding an abstraction requires naming
what it makes testable that was not testable before. If the answer is "it's cleaner", the answer is no.

What qualifies:

- A **platform channel** (TTS, camera, biometrics) — cannot execute in `flutter test`.
- A **network client / remote API** — you don't want tests hitting the wire.
- A **plugin with a bus-factor-1 maintainer** you may need to vendor — the interface makes the swap a
  one-file change.

What does **not** qualify (test it concretely):

- A **repository over an in-memory database.** `NativeDatabase.memory()` is real sqlite3, not a fake —
  it runs in `flutter test`. An interface over it buys a one-line override you can already get with
  `overrideWithValue`, and a Map-backed fake is *worse*: it happily accepts rows the real `PRIMARY
  KEY`/`CHECK`/`FK` constraints reject, and never runs a migration.
- A **pure calculator / value object.** It already runs headless; wrapping it in an interface hides it.
- A **key/value settings read.** A `SettingsRepository` over it is already generous; a `SettingsService`
  on top is a layer to read past.
- A **logger.** If the logger needs a test double, the logger is too complicated to be a logger.

The shape this forces: make the untestable implementation **as thin as possible**, and put everything
testable one layer up where the tests can reach it. A plugin adapter should be a few lines; the logic
that decides *what* to call it with is a pure function you cover 100%.

## Reject as over-engineering (default to the simpler thing)

| Pattern | Reject when | Because |
| --- | --- | --- |
| **Domain layer / `*UseCase`** | logic doesn't span multiple repositories | Flutter rates it *conditional*; a use-case over one repo call is a rename. Each is a layer a reader steps through to reach the code. |
| **Separate API models + domain models** | there's no network, or the mapping is 1:1 | Mapping a type onto itself is a new place to swap two same-typed `String`s the compiler can't tell apart. |
| **Abstract repository with one impl** | the impl runs in a test | The test seam already exists (`overrideWithValue`); the interface adds indirection and a fake that lies. |
| **A DAO interface over a generated data layer** | you use Drift/an ORM | The generated API *is* the interface. |
| **The `Command` pattern (`if (_running) return;`)** | a re-tap should just repeat the action | The guard silently swallows the second intent — often the exact bug you fear. A `bool _saving` field covers double-submit. |
| **`go_router` / a routing package** | few destinations, no deep links, no web | `Navigator.push` or a state flag covers it. A router earns its keep at deep-linking + many destinations. |
| **A second code generator (e.g. freezed) over an ORM's generated classes** | the ORM already generates `==`/`copyWith` for rows | Overlapping output + a hand-written mapping layer, for nothing. Hand-write `@immutable`/`sealed` for the few types the ORM can't emit (joins, materialized shapes). |
| **"Views and ViewModels 1:1" as a law** | one screen, one developer | It's a team-coordination device (stops two devs fighting over one class), vacuous solo. |
| **`lib/src/`, barrel files, `packages/` + workspace tooling** | a single-package app with no external importers | Package conventions with measurable analyzer cost and zero benefit until there's a second consumer. |
| **Multiple flavor entrypoints (`main_dev`/`main_prod`)** | there's one environment | No environments to select. |
| **A god `AppState` / `injection.dart`** | ever | Providers are the DI; a central mutable state object is a backdoor that defeats unidirectional flow. |

## Scale architecture to app size — a continuum, not a target

Architecture is not a fixed destination you build toward; it's sized to the app **and re-sized as the
app grows.** Under-architecting (a widget touching a DB) and over-architecting (five packages for six
tables) are both defects.

| App size | Shape |
| --- | --- |
| **A few screens over local storage** | One package. `core/` + `data/` + `features/`. Concrete repositories tested against an in-memory DB. No domain layer, no interfaces except platform channels. |
| **A dozen features, some cross-cutting logic** | Still one package, but `core/` grows value objects and a few pure calculators; a couple of features earn a local `application/` use-case where logic spans repositories. |
| **Large, reusable foundations, multiple app targets, a golden-tested pure core** | A Dart pub workspace: `core`/`data`/`design_system` as packages behind barrels, a compile wall on the pure layer. See the "when multi-package" note in `module-and-layers.md`. |

## When someone proposes "proper layering"

Answer with the size and the reason, not with taste. A right-sized app is not under-architected; it is
architected to the size it is. Every layer that does not carry a load is a place a silent failure can
hide from the compiler, the analyzer, and the tests. Ask the one question: **what does this abstraction
make testable that wasn't before?** No answer, no layer.
