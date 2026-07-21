---
name: run-codegen
description: >-
  Runs the deterministic build_runner codegen pass (drift_dev, freezed,
  json_serializable, riverpod_generator) as one pinned command with
  --delete-conflicting-outputs, always before flutter analyze, never
  hand-editing or force-committing generated *.g.dart / *.freezed.dart /
  *.drift.dart output, watch only in local dev. Use when regenerating codegen,
  fixing "missing part file" / "conflicting outputs" / undefined
  generated-class analyzer errors, after editing a drift table or DAO, a
  freezed value object, a riverpod Notifier or provider, or a json_serializable
  model, or after a fresh git clone, branch switch, or pull.
disable-model-invocation: true
---

# Run codegen (build_runner)

A deterministic, low-freedom runbook: regenerate all annotation-driven code in
one pass, then analyze. Run the pinned command exactly as written — do not
modify it, add flags, or hand-edit generated files. Applies whenever a source
file carries a codegen annotation (`@freezed`, `@JsonSerializable`,
`@riverpod`, `@DriftDatabase`, a drift table) and its `*.g.dart` /
`*.freezed.dart` / `*.drift.dart` part is missing or stale.

## Non-negotiable rules

1. **Run codegen BEFORE `flutter analyze`.** A fresh clone, branch switch, or
   freshly edited annotated file has no generated part on disk. Analyzing that
   tree produces misleading "missing part file" and undefined-class errors that
   describe the missing output, not a real code defect — regenerate, then
   analyze.
2. **Use the pinned command verbatim, always with `--delete-conflicting-outputs`.**
   Without it, build_runner refuses to overwrite an output it did not write this
   run and fails with a wall of "conflicting outputs" text. That is a stale-file
   collision, not a bug — do not go hunting for one.
3. **Never hand-edit a generated file.** The next build silently reverts it and
   takes your edit with it. Change the annotated source — the drift table, the
   freezed class, the Notifier, the ARB — and rerun.
4. **Never `git add -f` a generated file.** Whether generated code is committed
   or gitignored is one decision owned by `codegen-and-toolchain`; whichever the
   repo chose, never force-add an artifact past the ignore rules or commit one
   the current source would not reproduce.
5. **`watch` is a local-dev convenience, never CI or a pre-commit hook.** CI and
   the pre-analyze step always use the one-shot `build`.
6. **Fix hand-written source first.** The generator reads a resolved AST; it
   cannot generate from source that does not analyze. An unrelated error
   anywhere in `lib/` can block generation of a table or provider — clear those
   before blaming codegen.

## The canonical command

Run from the package root (single-package app) or the workspace root
(multi-package repo):

```bash
dart run build_runner build --delete-conflicting-outputs
```

This is the first step in every CI lane and on every fresh clone, before format
and analyze.

## Standard sequence on a fresh clone, pull, or branch switch

1. `flutter pub get` (resolve dependencies).
2. `dart run build_runner build --delete-conflicting-outputs` (regenerate).
3. Only then `flutter analyze`.

Skipping step 2 is the single most common cause of a red analyzer on a clone
whose code is actually fine.

## Dev iteration (optional watch)

For an active edit loop on annotated sources, run the watcher instead of a
one-shot build; it rebuilds affected outputs on save:

```bash
dart run build_runner watch --delete-conflicting-outputs
```

Stop the watcher before running the one-shot `build` — two concurrent
build_runner processes over the same tree race on outputs.

## When multi-package (workspace)

build_runner runs per-package: one invocation regenerates the current package
plus its path-dependency packages, not automatically every sibling in the
workspace. So running the single command **at the workspace root** covers the
root package and its path dependencies in one pass, but a coordinator-style root
that does not itself depend on every member will not regenerate those siblings.
For full multi-package regeneration, use the repo-level fan-out wrapper (e.g.
`melos run gen`) that runs the command over every workspace member; prefer it
when the workspace is bootstrapped. To deliberately scope one package during
development, run the same command from that package's directory. Builder scoping
(which files each builder reads) lives in each package's `build.yaml`, owned by
`codegen-and-toolchain`.

## When codegen and the analyzer disagree

The analyzer reads files on disk; build_runner writes them. A disagreement
almost always means the disk is behind, not that the code is wrong.

| Symptom | Do this |
|---|---|
| Analyzer flags an undefined class/getter that codegen should produce | Rerun the pinned build, then restart the analysis server. Do not "fix" the call site. |
| Errors reported *inside* a `*.g.dart` / `*.freezed.dart` / `*.drift.dart` file | The file is stale or the analyzer excludes are wrong. Regenerate first; never hand-edit generated output. |
| build_runner fails with analyzer errors in hand-written source | Fix the hand-written source — the generator cannot resolve an unanalyzable AST. |
| "Conflicting outputs" wall of text | Re-run with `--delete-conflicting-outputs`; it clears stale outputs from renamed/deleted sources. |

## Anti-patterns

- **Running `flutter analyze` before codegen on a fresh tree** — you chase
  phantom missing-part errors that regeneration erases.
- **Dropping `--delete-conflicting-outputs`** — the first rename or deletion
  fails the whole run on a stale-output collision.
- **Editing a `.g.dart` / `.freezed.dart` / `.drift.dart` by hand** — the next
  build reverts it; the fix belongs in the annotated source.
- **`git add -f` on a gitignored generated file** — bypasses the repo's
  committed-vs-gitignored decision and ships a possibly-stale artifact.
- **`build_runner watch` in CI or a pre-commit hook** — non-deterministic;
  CI must use the one-shot `build`.

## Definition of done

- [ ] The pinned `dart run build_runner build --delete-conflicting-outputs` ran
      at the package/workspace root without "conflicting outputs" errors.
- [ ] It ran **before** `flutter analyze`, which is now green.
- [ ] No generated file was hand-edited or force-added.
- [ ] No `build_runner watch` process is wired into CI or hooks.

## Related skills

- See `codegen-and-toolchain` for the knowledge behind this runbook:
  `build.yaml` builder scoping, the commit-vs-gitignore-generated-code decision,
  SDK pinning, and analyzer/coverage excludes for generated files.
- See `run-migration` for the drift schema-snapshot and migration ritual that
  wraps `drift_dev make-migrations` around this codegen pass.
- See `ci-pipeline-and-gates` for the CI freshness gate that reruns this command
  and diffs the tree.
- See `lint-and-style-config` for the analyzer excludes that keep generated
  files out of lint scope.

## References

- build_runner: https://pub.dev/packages/build_runner
- Dart tools — build_runner usage: https://dart.dev/tools/build_runner
- drift codegen: https://drift.simonbinder.eu/docs/getting-started/
- freezed: https://pub.dev/packages/freezed
- riverpod_generator: https://pub.dev/packages/riverpod_generator
