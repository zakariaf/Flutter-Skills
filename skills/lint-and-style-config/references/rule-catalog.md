# Rule catalog — what is promoted, and why

Every promotion below turns an info-level squiggle into a build-failing error.
The unifying test: **does this bug class produce silence** — an operation that
appears to succeed while doing nothing, an error that evaporates, a defect no
telemetry will ever report? If yes, it is an error, not a style preference.
Treat a downgrade request the way you would treat downgrading a memory-safety
check.

## Promote-to-error bug classes

| Rule | Bug class | Why silence |
|---|---|---|
| `unawaited_futures` | Dropped Future in an async body | The awaited work never completes; its errors go with it. |
| `discarded_futures` | Future-returning call in a **sync** body | Same, in code that looks synchronous. |
| `empty_catches` | `catch (_) {}` | Failure is invisible at that layer. |
| `avoid_catches_without_on_clauses` | bare `catch (e)` | Swallows every failure, including ones you must not handle here. |
| `only_throw_errors` | throwing non-`Error`/`Exception` (e.g. a `String`) | Breaks typed catch and stack semantics. |
| `throw_in_finally` | throw inside `finally` | Silently **replaces** the real exception with a bystander, destroying evidence. |
| `use_build_context_synchronously` | `context` used after an `await` | The widget may be disposed; `context` is a handle into a dead tree. |
| `cancel_subscriptions` | leaked `StreamSubscription` | Fires callbacks on disposed state. |
| `close_sinks` | leaked `StreamController`/sink | Same leak, sending side. VGA ships this at `ignore`; it is re-promoted. |
| `avoid_dynamic_calls` | method call on `dynamic` | Platform channels hand back `Map<Object?, Object?>`; unguarded calls throw at runtime, on device. |
| `always_declare_return_types` | inferred return on a member | Hides an accidental `dynamic`/`Future` in a public seam. |
| `cast_nullable_to_non_nullable` | `x as T` where `x` is `T?` | Throws at runtime instead of at the type boundary. |
| `exhaustive_cases` | non-exhaustive switch over an enum / static-const set | A new case falls through to nothing. (Sealed classes are covered by the compiler, not this lint — see config-mechanics.md.) |
| `avoid_print` | `print()` in shipped `lib/` | stdout reaches nobody in production; route through a logger/report seam. |
| `avoid_slow_async_io` | `File`/sync IO near the render path | Jank and dropped frames. |

## Deliberately NOT errors

| Rule | Level | Reason |
|---|---|---|
| `deprecated_member_use` | `warning` | An SDK/plugin upgrade must never block an urgent hotfix. Deprecations are noise on the wrong day. |
| `deprecated_member_use_from_same_package` | `warning` | Same. |
| `invalid_annotation_target` | `ignore` | Pure noise from `freezed` / `json_serializable` annotation placement. |
| `lines_longer_than_80_chars` | `ignore` | Fires only on what the formatter cannot split (long string literals, URLs in comments) — pure noise. |

## The one genuinely contested rule: `public_member_api_docs`

- **Shipped default: `error`**, to match the `dartdoc-conventions` skill. On a
  package that other packages depend on, `///` on the public surface is a
  contract, and a missing doc is a real gap.
- **App with no external consumers:** downgrading to `ignore` is defensible.
  Requiring a doc on every private-app widget buys little and trains the reader
  to scroll past lints — costly when lints are a primary safety net. If you
  downgrade, still document the **seams** (repositories, services, migration
  steps) by taste, and enforce that in review, not by lint.

State which choice you made in a comment; do not leave it ambiguous.

## Complexity limits (enforced by review or `dcm`, not by the analyzer)

The core analyzer does not measure these; treat an overrun as a signal to look,
not an auto-reject. Enforce with `dcm`/`dart_code_metrics` or in review.

| Unit | Limit | Action when exceeded |
|---|---|---|
| Method / function body | ~30 lines | extract a private method or collaborator |
| Widget `build()` | ~80 lines | extract child **widget classes**, never `_buildX()` helpers |
| File | ~300 lines | split by responsibility |
| Class public API | ~10 public members | the class does too much — split |
| Positional parameters | 3 | use named params; beyond ~4 total pass a value object |
| Nesting depth (if/for/closures) | 3 | early-return / extract |
| Cyclomatic complexity / method | ~10 | break the branch logic up |

A `_buildBanner()` helper rebuilds with its parent and can never be `const`; a
`const Banner(...)` widget class is skipped on rebuild. Extract classes, not
methods — this is a performance rule, not cosmetics. See `widget-composition`
and `flutter-performance`.
