# Toolchain pinning, excludes, and the multi-package workspace

## SDK pinning — local must equal CI

The single most common source of unexplained format/codegen churn is a local SDK
that differs from CI.

- Pin the Flutter/Dart version the project builds with. Under FVM this is `.fvmrc`;
  otherwise the version your CI action requests is the contract.
- Run tooling through the pin (`fvm flutter ...`, `fvm dart ...`) so a local run
  matches the pipeline byte-for-byte.
- The CI action's requested version MUST equal the pinned version. A drift here
  reproduces "works on my machine" — a formatter or generator that emits
  different bytes on a different patch release.
- Commit the lockfiles an *app* owns: `pubspec.lock` (always for an app),
  `Podfile.lock`, `Gemfile.lock`, `.ruby-version`, plus the pin file. See
  `dependency-hygiene`.

## Analyzer and coverage excludes (both strategies)

Generated files must be excluded from every tool that walks the tree, whether or
not they are committed.

```yaml
# analysis_options.yaml
analyzer:
  exclude:
    - "**/*.g.dart"
    - "**/*.freezed.dart"
    - "**/*.drift.dart"
    - "**/*.mocks.dart"
    - "**/generated_plugin_registrant.dart"
    # a migration-test baseline dir, if the suite generates era data classes:
    - "test/**/generated/**"
```

The generated-migration-baseline exclude matters most: an analyzer autofix inside
an exported schema snapshot would corrupt the migration-test baseline. It is safe
to exclude *because* migration correctness is enforced by the schema tests, not by
lints.

Coverage: strip the same suffixes before reading any number, or coverage inflates
with untested machine output.

```bash
lcov --remove coverage/lcov.info \
  '*.g.dart' '*.freezed.dart' '*.drift.dart' \
  -o coverage/lcov.info \
  --ignore-errors unused   # lcov 2.x errors on a pattern matching nothing
```

Use suffix-anchored, unanchored patterns (`'*.g.dart'`, not `'lib/**/*.g.dart'`):
lcov's `*` spans `/`, so an anchored `lib/**/*.g.dart` requires at least one path
segment after `lib/` and silently misses a top-level `lib/foo.g.dart` — the exact
coverage inflation this strips out. The unanchored form matches the same file set
as the analyzer's `**/*.g.dart` globs at any nesting depth. Keep the analyzer
excludes and the lcov patterns in sync — a suffix in one but not the other is a
silent gap.

## When multi-package (workspace) — opt-in only

A single-package app needs none of this. Reach for a workspace only when a concern
is genuinely cross-cutting and reused across app targets.

### Two mechanisms, one job each

| Concern | Owner | Notes |
| --- | --- | --- |
| Local path linking of members | **pub workspace** | `resolution: workspace` on every member + a `workspace:` list at the root. Pub produces ONE shared `pubspec.lock`. |
| Script running (`gen`/`format`/`analyze`/`test`) | **Melos** (optional) | `melos run <script>` fans a command across filtered packages. |
| Change-based CI selection | **Melos** (optional) | `--since` / packageFilters keep PR CI fast. |

Never use `melos bootstrap` for path linking when using `resolution: workspace` —
mixing the two produces duplicate/inconsistent resolution. Pub links; Melos only
orchestrates scripts.

### Root workspace pubspec

```yaml
# /pubspec.yaml
name: my_app_workspace
environment:
  sdk: ^3.6.0
workspace:
  - apps/my_app
  - packages/core
  - packages/data
```

### Scoping codegen in a workspace

- Run `build_runner build --delete-conflicting-outputs` once at the workspace
  root so every member regenerates in the same pass. Running inside one package
  dir leaves the others stale.
- If orchestrating with Melos, filter the `gen` script to packages that depend on
  `build_runner`:

```yaml
# melos.yaml
scripts:
  gen:
    exec: dart run build_runner build --delete-conflicting-outputs
    packageFilters: { dependsOn: ["build_runner"] }
```

### Workspace resolution-failure edge cases

| Symptom | Cause | Fix |
| --- | --- | --- |
| Member's changes not seen; stale package resolved | member missing `resolution: workspace` | add it, re-run `dart pub get` at root |
| `version solving failed` | member SDK constraint incompatible with root | align `environment.sdk` across members |
| Two lockfiles appear | a `dart pub get` ran inside a package dir, or a stray per-package lockfile was committed | delete the per-package lockfile; only the root `pubspec.lock` is tracked |
| Codegen stale across packages | ran `build_runner` inside one package only | run at the root |
