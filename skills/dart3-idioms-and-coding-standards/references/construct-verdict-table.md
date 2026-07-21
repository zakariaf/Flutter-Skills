# Construct verdict table

The feature-by-feature ruling on which Dart 3 construct a declaration earns. A feature is worth its weight when it converts a runtime silence into a compile error.

## The verdict

| Feature | Verdict | Why |
|---|---|---|
| `sealed class` + exhaustive `switch` | **Use — the backbone** | A missing branch is a compile error, not a lint. The only compiler-grade safety net for a closed set. |
| Destructuring patterns (`case Card(:final last4)`) | **Use** | Pulls the payload out at the one place it is needed, no getter chain. |
| Records for ephemeral tuples (`(int row, int col)`) | **Use — inside one layer only** | Free structural equality, no package, no codegen. |
| `final class` for concrete leaves | **Use — the default** | Closes the type against both `extends` and `implements`; a variant list is the file. |
| `abstract interface class` for seams | **Use** | Says "implement me, don't extend me" — exactly the contract a test fake needs. |
| `@immutable` + `const` ctor + `final` fields | **Use** | Four lines replace a code generator. |
| `enum` for closed sets with **no** payload | **Use sparingly** | Enums get compiler exhaustiveness too — but the moment a member needs a field, convert to `sealed`. |
| `base class` | **Skip** | Exists to force subclasses to preserve an implementation invariant across a *library boundary*. A single-package app publishes no such library; `final`/`sealed` covers every real case, and `base` propagates itself virally for nothing. |
| `extension type` | **Skip** | Explicitly an *unsafe* abstraction — the representation type is never a subtype and the underlying object stays reachable. Ceremony at every boundary for safety a small app does not need. |
| Primary constructors | **Skip** | Still behind `--enable-experiment=primary-constructors`. A repo that needs an experiment flag to build stops building the day it is abandoned. |
| Macros | **Dead** | Cancelled. `build_runner` is not going away. |
| `freezed` | **Use — for non-trivial value types** | Hand-roll trivial immutables (1–3 fields). Once `copyWith`/`==`/`hashCode`/sealed-union boilerplate dominates a domain or UI-state value type, `freezed` earns its place and is the default there; `*.freezed.dart` is a first-class generated artifact. Skip it only where a persistence generator (e.g. drift) already emits an immutable row class you can use directly — a second generator on overlapping classes plus a hand-written mapping layer buys nothing. |
| `equatable` | **Skip** | The only thing it buys is `==` + `hashCode` on a map-key type — that is `operator ==` plus `Object.hash(...)`, ~five lines. |
| `fpdart` / `dartz` (`Either`) | **Skip** | An `Either` is a generic result type by another name, with the same loss of exhaustiveness plus an unfamiliar vocabulary. Use a hand-rolled sealed type per real decision point (see `error-handling-typed-results`). |
| Any `--enable-experiment` flag | **Skip** | An abandoned repo must never need an experiment flag to build. |

## Why no generic `Result<T>` with an `Exception` arm

Do not introduce a generic sealed result whose error arm is typed `Exception` (including the one Flutter's architecture guide publishes). Matching that arm tells you *nothing about which failure occurred* — zero exhaustiveness, which is the entire property being bought. It also tends to name a variant `Error`, shadowing `dart:core.Error` in every importing file. One hand-rolled sealed type per real decision point, zero dependencies. The full Result/Failure architecture is `error-handling-typed-results`; this skill owns only the language mechanics (sealed types, exhaustive switch).

## Intermediate sealed layers are legitimate

Matching an intermediate sealed supertype (`case SyncFailure(...)`) is exhaustive on its own, and adding a new subtype under it does not break that switch. That is correct exactly when every subtype resolves identically — reach for an intermediate layer when a group of variants shares one uniform response, not to save typing.

## Sealed variants and equality

Sealed variants that are only ever switched on need no `==`/`hashCode` — switching on the type is the whole interface, and instances are never compared. Add value equality only to variants that are compared or used as keys.
