# Config mechanics — the traps that make a strict config secretly do nothing

A green analyzer over a broken config looks exactly like a green analyzer over a
strict one. These are the failure modes that produce that illusion.

## 1. The version-pinned-include trap

```yaml
include: package:very_good_analysis/analysis_options.10.3.0.yaml
```

Pin the **version-numbered** file, not the bare `analysis_options.yaml`. A
`dart pub upgrade` must never silently change what counts as an error.

**The trap:** if that filename does not exist in the *resolved* package, you get
a single `warning • include_file_not_found` and analysis continues with **zero
rules**. A build that checks nothing is green.

Mitigations, all required:

- Bump the include filename **in the same commit** as the SDK/VGA bump.
- Verify the file exists: `ls ~/.pub-cache/hosted/pub.dev/very_good_analysis-*/lib/`
- After any bump, confirm rules are live by checking that a **known violation
  still errors** — never by observing that analysis is green.

VGA's current major requires a matching Dart SDK floor; keep the two in step.
Do not reintroduce an older VGA pin that predates your SDK.

## 2. `errors:` only RE-RANKS; `linter: rules:` ENABLES

This is the mechanic people get wrong.

- `analyzer: errors: <rule>: error` changes the **severity** of a diagnostic
  the linter **already produces**. It cannot turn on a rule that is off.
- If a rule is not enabled by your base ruleset at all, promoting it under
  `errors:` does nothing — no diagnostic exists to re-rank.

So a promotion works **only if VGA already enables the rule** (even at severity
`ignore`, like `close_sinks` — that counts as enabled, just downranked, so a
severity override to `error` resurrects it). Everything the shipped config
promotes is VGA-enabled, which is why it needs no `linter: rules:` block.

To enable a rule VGA omits entirely, you must add it under `linter: rules:`
first, then optionally promote it:

```yaml
linter:
  rules:
    some_rule_vga_omits: true   # enable
analyzer:
  errors:
    some_rule_vga_omits: error  # then re-rank
```

Verify with a real violation. Never assume a promotion took.

**Never mix forms.** `linter: rules:` accepts either a list (`- rule`) or a map
(`rule: true`), never both in one block. To **disable** a base rule, use
`analyzer: errors: <rule>: ignore` — never `- rule: false` under a list-form
`rules:`. Mixing list and map form is a YAML/config parse error, which is a
broken analyzer, which is a green build.

## 3. Sealed exhaustiveness is a COMPILE error, not a lint

`exhaustive_cases` covers only the legacy enum / static-const-instance case. A
non-exhaustive `switch` over a **sealed** class is
`non_exhaustive_switch_statement` — a compile error, no lint involved. This is
the main reason to model failure/mode types as `sealed` rather than enums:
adding a case breaks the build at every call site instead of falling through a
`default` into silence.

A non-exhaustive switch *statement* raises `non_exhaustive_switch_statement`; a
switch *expression* raises `non_exhaustive_switch_expression`. Both are
compile-time errors.

**Close the escape hatch:** do not rely on an `analyzer: errors:` override to
suppress an exhaustiveness diagnostic — the analyzer will not reliably downrank
a compile-time error, and even where `dart analyze` is coaxed green `dart
compile` still fails. Therefore **CI must build, not merely analyze** — an
analyze-only gate can go green over code that will not compile. See
`ci-pipeline-and-gates`.

## 4. Excludes must be mirrored in coverage filtering

```yaml
analyzer:
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "**/*.drift.dart"
    - "**/generated_plugin_registrant.dart"
    - "test/drift/generated/**"
```

Generated code is excluded because it is not hand-owned and regenerates on every
build; linting it produces findings nobody can act on. It is **safe** to exclude
because its correctness is proven elsewhere (drift schema tests, codegen
determinism), not by lints.

The identical globs **must** be mirrored in coverage filtering (`lcov --remove`
or your reporter's exclude list). Generated files otherwise dilute the coverage
number until it stops meaning anything. Excludes and coverage filters that drift
apart are a silent way to lie the number upward. See `testing-strategy` and
`codegen-and-toolchain`.

`test/drift/generated/**` is load-bearing: those are drift's exported schema
snapshots — historical migration-test baselines. A lint autofix or reformat
there corrupts the baseline. Never reformat, "fix", or regenerate an old
snapshot; add new ones, never edit old ones. See `run-migration`.

## 5. Riverpod plugin diagnostics

riverpod_lint 3.x runs on the first-party `analysis_server_plugin` system
(Dart 3.10+). `missing_provider_scope` and friends are reported by a plain
`flutter analyze` — **no** `custom_lint` dependency and **no** second
`dart run custom_lint` pass.

- **Never add `custom_lint`.** The legacy plugin system it depends on is
  deprecation-bound.
- With a pub version the `version:` key is **mandatory**:
  `riverpod_lint: ^3.1.3` directly followed by a nested `diagnostics:` map is a
  YAML parse error (a scalar cannot also have children).
- Plugin **warnings** are on by default; plugin **lints** are off by default and
  must be opted into under `diagnostics:`.
- Suppress a plugin diagnostic with the namespaced form:
  `// ignore: riverpod_lint/missing_provider_scope`.
- Gate CI on diagnostic **severity**, never on an issue *count*. A raw count is
  fragile against tooling changes and tells you nothing about whether the build
  is actually clean; `--fatal-infos --fatal-warnings` is the durable gate.
- `provider_dependencies` and `avoid_build_context_in_providers` are
  **riverpod_generator-only** — they never fire without the generator, so leave
  them off in a non-codegen project (see `examples/analysis_options.yaml`).

See `state-management-riverpod`.

## 6. `dart format` is the sole whitespace authority

Tall style is selected by the language version in `pubspec.yaml`, not by config.
Never hand-format, never argue with the formatter, never `// dart format off`
except around a hand-laid table with a justifying comment. CI runs
`dart format --set-exit-if-changed .`. The `formatter:` block in
`analysis_options.yaml` only tunes the formatter (e.g. `trailing_commas:
preserve`, which forces vertical splits for readable widget-tree diffs) — it
does not replace running the formatter.

## 7. Suppression discipline

An `// ignore:` on a promoted rule is a claim that a silence bug is acceptable
*here*. It is almost never true.

- Line-scoped only. Write the reason on the line above, naming the mechanism
  that makes it safe.
- **Never** `// ignore_for_file:` on a promoted safety rule — file scope means
  the next edit to that file is unprotected and nobody notices.
- **Never** on an architecture/import gate (engine purity, banned imports,
  legacy-provider ban). Silencing a correctness gate is a review blocker.
- Prefer fixing the code over silencing the lint. A suppression is the last
  resort, not the first.
