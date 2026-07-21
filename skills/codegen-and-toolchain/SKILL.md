---
name: codegen-and-toolchain
description: >-
  Enforces a deterministic build_runner codegen discipline: run one pinned
  `dart run build_runner build --delete-conflicting-outputs` pass BEFORE
  `flutter analyze` (never after), fence every builder with `generate_for:`
  globs in a per-package `build.yaml`, make one deliberate commit-vs-gitignore
  decision for `*.g.dart`/`*.freezed.dart`/`*.drift.dart` and back it with the
  matching CI gate (freshness diff if committed, codegen-first if gitignored),
  mirror the generated-file globs into the analyzer AND coverage excludes, pin
  the SDK, and never hand-edit generated output. Use when editing build.yaml,
  analysis_options.yaml, pubspec.yaml, .gitignore, .gitattributes, or CI
  workflows; wiring drift_dev/freezed/json_serializable/riverpod_generator/
  gen-l10n/mockito codegen; fixing "missing part file", "undefined class _$Foo",
  or "conflicting outputs" errors; deciding whether to commit generated code; or
  scoping builders so one edit does not regenerate everything.
---

# Codegen and toolchain

One deterministic codegen pass is the source of truth for every generated file;
run it first, scope it tightly, and decide once whether its output lives in git.
Applies whenever a project uses `build_runner` or `gen-l10n`.

Read the reference for the task at hand:
- `references/codegen-scoping.md` — the generator inventory, `generate_for:`
  scoping tables, error-to-fix recovery map.
- `references/commit-vs-gitignore.md` — the two committed/gitignored strategies,
  their tradeoffs, and the exact CI gate each one requires.
- `references/toolchain-and-workspace.md` — SDK pinning, analyzer/coverage
  excludes, and the multi-package workspace layering (fenced, opt-in).

Run `scripts/regen.sh` (codegen → format → analyze) before a PR, and
`scripts/check-codegen-hygiene.sh` to verify excludes and commit-policy parity.

## Non-negotiable rules

1. **Codegen runs FIRST, before `flutter analyze`.** Generated files may be
   absent on a fresh clone or stale after editing an annotation. Analyzing that
   tree emits misleading "missing part file" and "undefined class `_$Foo`"
   errors. Regenerate, then analyze — never chase the symptom at the call site.
2. **Always pass `--delete-conflicting-outputs`.** Without it `build_runner`
   refuses to overwrite an output from a renamed/deleted source and fails with a
   wall of "conflicting outputs" text. That is not a bug to investigate.
3. **Never hand-edit a generated file.** The next build silently reverts it and
   takes your edit with it. Change the annotated source and rerun codegen.
4. **Scope every builder with `generate_for:` in a per-package `build.yaml`.**
   A change in one directory must not regenerate the whole tree. Point each glob
   at the narrowest directory that owns the annotation.
5. **Decide commit-vs-gitignore ONCE, back it with the matching CI gate.**
   Gitignored → CI regenerates first, before analyze. Committed → CI regenerates
   then runs `git diff --exit-code` as a freshness gate. Either is valid; a
   policy without its gate is not (see `references/commit-vs-gitignore.md`).
6. **Mirror generated-file globs into the analyzer AND coverage excludes.**
   A glob that lints machine output wastes review; a glob missing from lcov
   inflates coverage. Exclude the *emitted* suffix — verify it, do not guess.
7. **Pin the SDK; local must equal CI.** The CI Flutter/Dart version must match
   the pinned local version (`.fvmrc` under FVM, or the tool the repo standardizes
   on). A drift here reproduces "works on my machine" format/codegen churn.
8. **`watch` is a local edit-loop tool only.** CI and the pre-analyze step always
   use the one-shot `build` command.

## The canonical command

Run from the repository root:

```bash
dart run build_runner build --delete-conflicting-outputs
```

This regenerates every builder — `drift_dev`, `freezed`, `json_serializable`,
`riverpod_generator`, `mockito` — in one pass. `gen-l10n` runs through the
Flutter tool but is treated identically (regenerated first, same commit policy):

```bash
flutter gen-l10n   # if not auto-triggered by `flutter pub get` via l10n.yaml
```

Fresh clone / after pull / after editing any annotation, the fixed order is:

```
build_runner build --delete-conflicting-outputs   →   format   →   analyze   →   test
```

Never reorder codegen after analyze. During an active edit session only, a
watcher rebuilds affected outputs on save:

```bash
dart run build_runner watch --delete-conflicting-outputs
```

## Scoping builders with build.yaml

Give every codegen-carrying package (or the single app package) its own
`build.yaml`, and fence each builder's `generate_for:` at the narrowest directory
that owns its annotation. An unscoped root config fans out to every annotation in
the tree, so editing one `Task` model regenerates unrelated `Order` and `Account`
outputs. Copy `examples/build.yaml`; `references/codegen-scoping.md` has the full
generator-to-suffix table and per-builder globs.

## Commit vs gitignore: pick one, wire its gate

Both strategies are legitimate; they trade different risks (see rule 5). Gitignore
keeps the tree clean but needs a working toolchain to build. Committing survives a
broken future toolchain and makes schema diffs reviewable, but needs a
`.gitattributes` diff-collapse (`examples/gitattributes.example`) AND a mandatory
freshness gate — regenerate, then
`git diff --exit-code -- '*.g.dart' '*.freezed.dart' '*.drift.dart'`. A policy
without its gate is not a policy. Both strategies, their tradeoffs, and the exact
gate each requires: `references/commit-vs-gitignore.md`.

## Analyzer and coverage excludes

Committed OR gitignored, every *emitted* generated suffix must be excluded from
BOTH the analyzer and the lcov coverage filter — verify the suffix the config
actually emits first, do not guess. A missed analyzer glob wastes review on
machine output; a missed (or mis-anchored) lcov glob inflates coverage with
untested code. A migration-test baseline dir that holds generated era-correct data
classes needs the analyzer exclude too — an autofix inside an exported schema
snapshot would corrupt migration verification (see `run-migration`). The canonical
exclude blocks and the correctly anchored lcov patterns live in
`references/toolchain-and-workspace.md`.

## When multi-package (workspace)

Only for a repo that has genuinely outgrown one package. A single-app project
needs none of this.

- Link members with a native Dart pub workspace: `resolution: workspace` in every
  member pubspec plus a `workspace:` list at the root, producing ONE root
  `pubspec.lock`. Never add a per-package lockfile.
- If you layer Melos on top, use it for *script orchestration only*
  (`melos run gen/format/analyze/test`), never for path linking — pub does the
  linking. Filter the `gen` script to packages that depend on `build_runner`.
- Run `build_runner` once at the workspace root so every member regenerates in
  the same pass; running inside one package dir leaves the others stale.

## Anti-patterns

- **Analyzing before regenerating** — every downstream error is a phantom; fix
  the order, not the code.
- **Omitting `--delete-conflicting-outputs`** — turns a routine rename into a
  build wall.
- **Hand-editing `.g.dart`/`.drift.dart` to silence an error** — reverted on the
  next build; the real fix is in the annotated source.
- **Committing generated code with no freshness gate** — output silently drifts
  from source and reviewers trust a lie.
- **One unscoped root `build.yaml`** — every trivial edit regenerates the whole
  tree and slows every build.
- **Coverage/analyzer glob that matches the wrong suffix** — fails silently in
  the analyzer, loudly in lcov 2.x, and quietly inflates coverage.
- **CI Flutter version ≠ pinned local version** — reproducible format/codegen
  churn nobody can explain.
- **A generated migration test left with empty data lists** — passes vacuously
  (`[] == []`) while proving nothing; fill it or delete it (see `run-migration`).

## Definition of done

- [ ] `dart run build_runner build --delete-conflicting-outputs` succeeds from a
      clean tree, then `flutter analyze` is clean.
- [ ] Every codegen-carrying package has a `build.yaml` with scoped
      `generate_for:` globs.
- [ ] The commit-vs-gitignore decision is made and its CI gate exists (freshness
      diff, or codegen-first).
- [ ] The emitted generated suffixes are excluded from BOTH `analysis_options.yaml`
      and the lcov coverage filter.
- [ ] SDK is pinned and the CI toolchain version matches it.
- [ ] No generated file is hand-edited; no `watch` in CI.

## Related skills

- See `run-codegen` for the operational, low-freedom "run this exact command"
  loop and its troubleshooting table.
- See `run-migration` for the Drift schema-snapshot and migration-test ritual the
  codegen pass produces.
- See `persistence-drift` for the Drift/DAO data layer these generators feed.
- See `lint-and-style-config` for the analyzer ruleset and the excludes mirrored
  here.
- See `ci-pipeline-and-gates` for where codegen and the freshness gate sit in the
  pipeline.
- See `dependency-hygiene` for the lockfile and SDK-pinning mechanics.

## References

- build_runner: https://dart.dev/tools/build_runner
- Drift codegen & build config: https://drift.simonbinder.eu/docs/advanced-features/builder_options/
- freezed: https://pub.dev/packages/freezed
- json_serializable: https://pub.dev/packages/json_serializable
- riverpod codegen: https://riverpod.dev/docs/concepts/about_code_generation
- Flutter gen-l10n: https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization
- Dart pub workspaces: https://dart.dev/tools/pub/workspaces
