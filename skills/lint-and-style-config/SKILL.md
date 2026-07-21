---
name: lint-and-style-config
description: Enforces a strict analysis_options.yaml built on very_good_analysis with strict-casts/strict-raw-types, a fixed set of silence-producing bug classes promoted to error (unawaited_futures, discarded_futures, empty_catches, use_build_context_synchronously, cancel_subscriptions, close_sinks, avoid_dynamic_calls, exhaustive_cases, avoid_print), dart format as the sole whitespace authority, generated-file excludes mirrored to coverage, and line-scoped-only suppression discipline; teaches the version-pinned-include trap (a missing include silently disables all rules), the errors-only-re-ranks-vs-linter-enables mechanic, and the sealed-switch analyze-vs-compile gap. Use when editing analysis_options.yaml, adding or disabling a lint, writing an `// ignore:`/`// ignore_for_file:`, bumping the Dart SDK or very_good_analysis version, wiring riverpod_lint, or explaining why discarded_futures, use_build_context_synchronously, close_sinks, or missing_provider_scope fires.
---

# Lint & Style Config

Style is not taste; it is toolchain-enforced. `dart format` owns whitespace, the
analyzer owns correctness, and a small set of **silence-producing bug classes**
are promoted to build-failing errors. This skill governs the
`analysis_options.yaml` itself and the mechanics that decide whether it actually
does anything. Applies whenever you edit that file, add or silence a lint, or
bump the SDK/ruleset.

Read the reference for the task at hand:

- `references/rule-catalog.md` — every promoted rule and its bug class, the
  deliberate downgrades, the contested `public_member_api_docs` call, and the
  complexity-limit table.
- `references/config-mechanics.md` — the include-pin trap, `errors:`-re-ranks
  vs `linter:`-enables, sealed-switch analyze-vs-compile, coverage mirroring,
  the riverpod_lint plugin, and suppression discipline.

Copy `examples/analysis_options.yaml` into the package root as the starting
config. Run `scripts/verify-include-pin.sh` and `scripts/lint-gates.sh` before a
PR.

## Non-negotiable rules

1. **`dart format` is the only whitespace authority.** Never hand-format, never
   argue with it, never `// dart format off` except around a hand-laid table
   with a justifying comment. CI runs `dart format --set-exit-if-changed .`.
2. **Build on `very_good_analysis`, pinned to the version-numbered include.**
   Never the bare `analysis_options.yaml` — a `pub upgrade` must not silently
   change what counts as an error. VGA already sets `strict-casts`,
   `strict-inference`, `strict-raw-types`; do **not** restate them in a
   `language:` block (redundant config drifts and contradicts).
3. **An info is a failure.** CI runs `dart analyze --fatal-infos
   --fatal-warnings`. Unaddressed infos accumulate into noise that hides real
   issues.
4. **Promote only silence-producing bug classes to error** — dropped Futures,
   swallowed failure, dead-context-after-await, resource leaks, dynamic-boundary
   type holes, non-exhaustive enum switches, `print`. Not style preferences.
5. **A promotion under `errors:` only works if the base ruleset already enables
   the rule.** `errors:` re-ranks existing diagnostics; it cannot turn on an off
   rule. To enable a rule VGA omits, add it under `linter: rules:` first.
6. **Never mix list and map form in `linter: rules:`.** `- rule` items and
   `rule: true` entries in one block is a parse error — a broken analyzer, which
   is a green build. To disable a base rule, use `errors: <rule>: ignore`.
7. **CI must build, not merely analyze.** Sealed-switch exhaustiveness is a
   compile error, not a lint; an `errors:` override cannot be trusted to silence
   it, and any code path that reaches `dart compile` still fails there — an
   analyze-only gate can go green over code that will not build.
8. **Exclude generated code, and mirror the exact globs in coverage filtering.**
   Otherwise generated files dilute the coverage number until it is meaningless.
9. **Suppressions are line-scoped only, with a same-line/above reason.** Never
   `// ignore_for_file:` on a promoted rule; never any suppression on an
   architecture/import gate. Prefer fixing the code.
10. **Never add `custom_lint`.** riverpod_lint 3.x runs on the first-party
    plugin system; its diagnostics fire on a plain `flutter analyze`.

## The include, and the trap that silently disables everything

```yaml
include: package:very_good_analysis/analysis_options.10.3.0.yaml
```

If that filename does not exist in the *resolved* package, you get one
`warning • include_file_not_found` and analysis runs with **zero rules**. A
build that checks nothing is green.

Bump the include filename **in the same commit** as the SDK/VGA bump, verify the
file exists (`ls ~/.pub-cache/hosted/pub.dev/very_good_analysis-*/lib/`), and
after any bump confirm a **known violation still errors** — never trust green.
`scripts/verify-include-pin.sh` automates the existence check.

## Promote the silence-bugs to error

```yaml
analyzer:
  errors:
    unawaited_futures: error
    discarded_futures: error
    empty_catches: error
    avoid_catches_without_on_clauses: error
    only_throw_errors: error
    throw_in_finally: error
    use_build_context_synchronously: error
    cancel_subscriptions: error
    close_sinks: error            # VGA ships this at `ignore`; re-promoted
    avoid_dynamic_calls: error
    always_declare_return_types: error
    cast_nullable_to_non_nullable: error
    exhaustive_cases: error
    avoid_print: error
    avoid_slow_async_io: error
```

Each turns an info-level squiggle a solo dev scrolls past into a build failure.
See `references/rule-catalog.md` for the per-rule bug class and the rules held
deliberately at `warning`/`ignore` (`deprecated_member_use`,
`invalid_annotation_target`, `lines_longer_than_80_chars`).

## `errors:` re-ranks; `linter: rules:` enables

```yaml
# Promoting works ONLY because VGA already enables these rules (close_sinks even
# at severity `ignore` counts as enabled — the override resurrects it).
analyzer:
  errors:
    close_sinks: error

# To enable a rule VGA does NOT ship, add it here FIRST, then optionally promote.
linter:
  rules:
    some_rule_vga_omits: true
```

Verify with a real violation — never assume a promotion took. The shipped config
needs no `linter: rules:` block because every rule it promotes is VGA-enabled.

## Sealed exhaustiveness is a compile error, not a lint

```dart
sealed class SaveResult {}
class Saved extends SaveResult {}
class SaveFailed extends SaveResult {}

// Missing a case is `non_exhaustive_switch_statement` — a COMPILE error.
// (A switch *expression* raises `non_exhaustive_switch_expression` instead.)
String describe(SaveResult r) {
  switch (r) {
    case Saved():
      return 'saved';
    case SaveFailed():
      return 'failed';
  }
}
```

`exhaustive_cases` only covers enum / static-const sets. Model failure and mode
types as `sealed` so a new case breaks the build at every call site instead of
falling through a `default` into silence. An `errors:` override cannot be
trusted to suppress an exhaustiveness diagnostic, and even where `dart analyze`
is coaxed green `dart compile` still fails — so **CI must build**, never merely
analyze. See `dart3-idioms-and-coding-standards`.

## Excludes, mirrored to coverage

```yaml
analyzer:
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "**/*.drift.dart"
    - "**/generated_plugin_registrant.dart"
    - "test/drift/generated/**"   # drift schema snapshots — never reformat/fix
```

The identical globs must also feed coverage filtering (`lcov --remove` or your
reporter's excludes). Excludes and coverage filters that drift apart lie the
number upward. See `testing-strategy` and `codegen-and-toolchain`.

## The hole no lint catches

```dart
// WRONG — flagged by NOTHING. The arrow returns the Future (so discarded_futures
// is satisfied), but the target is VoidCallback, so Dart drops it silently.
onPressed: () => repository.save(note),

// RIGHT — a void-returning intent method the callback holds safely.
class NoteController {
  void saveNow(Note note) => unawaited(_repo.save(note).catchError(_report));
}
// onPressed: () => controller.saveNow(note),
```

The mitigation is structural, never disciplinary. A green analyzer is not proof
an operation ran; the highest-severity failures are invisible to every rule and
need a manual pass. See `examples/callback_future_hole.dart` and `async-safety`.

## Anti-patterns

- **Bare `include: package:very_good_analysis/analysis_options.yaml`** — a pub
  upgrade silently changes the ruleset; a missing pinned file silently disables
  it. Pin and verify.
- **Restating `strict-casts`/`strict-raw-types` in a `language:` block** — VGA
  sets them; the copy drifts and eventually contradicts.
- **Promoting a rule VGA does not enable** — `errors:` cannot resurrect an off
  rule, so the promotion silently does nothing.
- **Mixing `- rule` and `rule: false` in one `linter: rules:` block** — parse
  error, broken analyzer, green build.
- **Analyze-only CI** — passes over code that fails `dart compile` when a sealed
  switch is non-exhaustive.
- **Excludes not mirrored in coverage** — generated files inflate the number.
- **`// ignore_for_file:` on a promoted rule, or any suppression on an import
  gate** — the next edit is unprotected; a silenced correctness gate is a
  blocker.
- **Adding `custom_lint`** — legacy plugin system; riverpod_lint 3.x needs none.
- **Reformatting a drift schema snapshot** — corrupts the migration-test
  baseline.

## Definition of done

- [ ] `dart format --set-exit-if-changed .` clean; `dart analyze --fatal-infos
      --fatal-warnings` passes; CI **builds** (not analyze-only).
- [ ] Include is the **version-pinned** VGA file and resolves in the pub cache
      (`scripts/verify-include-pin.sh` passes).
- [ ] No redundant `language:` block; strict modes come from VGA.
- [ ] The silence-bug classes are promoted to `error`; every promoted rule is
      one VGA actually enables.
- [ ] No mixed list/map form in `linter: rules:`.
- [ ] Generated-file excludes present and **mirrored** in coverage filtering.
- [ ] Any suppression is line-scoped with a reason, none on an architecture
      gate; no `// ignore_for_file:` on a promoted rule.
- [ ] riverpod_lint configured with a `version:` key; no `custom_lint`.

## Related skills

- `dartdoc-conventions` — backs `public_member_api_docs: error` and the seams to
  document.
- `async-safety` — the Future-dropped-in-a-callback hole this config cannot see.
- `error-handling-typed-results` — the sealed `Failure`/`Result` spine that
  makes exhaustiveness a compile-time guarantee.
- `dart3-idioms-and-coding-standards` — sealed types and the exhaustive-switch
  discipline behind rule 7.
- `naming-conventions` — the role suffixes and Effective-Dart naming the analyzer
  does not enforce.
- `state-management-riverpod` — the Riverpod patterns riverpod_lint guards.
- `codegen-and-toolchain` / `run-codegen` — the generated files these excludes
  cover.
- `ci-pipeline-and-gates` — where these gates and the build-not-analyze rule run.
- `testing-strategy` — coverage mirroring and what a green analyzer cannot prove.
- `dependency-hygiene` — the version-pinned lint include as a dependency concern.

## References

- Effective Dart: [Style](https://dart.dev/effective-dart/style) ·
  [Usage](https://dart.dev/effective-dart/usage) ·
  [Documentation](https://dart.dev/effective-dart/documentation)
- [Dart linter rules](https://dart.dev/tools/linter-rules)
- [`dart format`](https://dart.dev/tools/dart-format)
- [`dart analyze` / analysis_options](https://dart.dev/tools/analysis)
- [`very_good_analysis`](https://pub.dev/packages/very_good_analysis) ·
  [`flutter_lints`](https://pub.dev/packages/flutter_lints)
- [`riverpod_lint`](https://pub.dev/packages/riverpod_lint) ·
  [Riverpod: What's new in 3.0](https://riverpod.dev/docs/whats_new)
