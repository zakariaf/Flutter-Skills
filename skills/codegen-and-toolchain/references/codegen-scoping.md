# Codegen scoping, generator inventory, and error recovery

## The generators in play

| Generator | Emits | Annotation / trigger | Typically lives in |
| --- | --- | --- | --- |
| `drift_dev` | `*.drift.dart` (modular) or `*.g.dart` (part-file) — build-config dependent | `@DriftDatabase`, `@DriftAccessor`, table classes | data layer |
| `freezed` | `*.freezed.dart` | `@freezed` immutable value/domain models | domain / models |
| `json_serializable` | `*.g.dart` | `@JsonSerializable` DTOs (backup/export/wire) | data / DTO dirs |
| `riverpod_generator` | `*.g.dart` | `@riverpod` Notifiers / providers | feature dirs |
| `gen-l10n` | localized Dart (`AppLocalizations`) | ARB files + `l10n.yaml` | l10n dir |
| `mockito` (optional) | `*.mocks.dart` | `@GenerateMocks` / `@GenerateNiceMocks` | `test/` |

`build_runner build` regenerates drift/freezed/json/riverpod/mockito in one pass.
`gen-l10n` runs via the Flutter tool but follows the same policy: regenerated
first, same commit decision, same excludes.

> Prefer `mocktail` (no codegen) over `mockito` for owned collaborators; it needs
> no `*.mocks.dart` and no build step. Reach for `mockito` only where an existing
> `@GenerateMocks` set already exists. See `testing-strategy`.

> `riverpod_generator` is OPTIONAL. Manual providers
> (`AsyncNotifierProvider(...)`/`StreamNotifierProvider(...)`, with `.autoDispose`
> /`.family` modifiers) are the default authoring style; reach for `@riverpod`
> codegen only if the team opts in. See `state-management-riverpod`. When it is
> used, it emits `*.g.dart` and follows the same commit/exclude policy.

## Which suffix does drift emit?

Depending on your build config, drift emits either `*.drift.dart` (modular
generation) or `*.g.dart` (part-file generation) — **verify which your config
produces**; don't infer it from a "modern vs legacy" rule of thumb (the default
`@DriftDatabase` setup still emits a part file). This suffix determines your
gitignore, analyzer exclude, and lcov pattern, so **check the config before
writing any glob.** A pattern that matches nothing fails silently in the analyzer
and loudly in lcov 2.x.

## Per-package builder scoping

Fence each builder to the narrowest directory that owns the annotation so one
edit does not regenerate the whole tree.

These globs use the single-app FEATURE-FIRST layout (`lib/data`, `lib/features`,
`lib/core`) owned by `project-structure-and-packages` — the app package does NOT
use `lib/src/`. Inside a pub-workspace PACKAGE, swap the roots for `lib/src/**`.

```yaml
# build.yaml
targets:
  $default:
    builders:
      drift_dev:
        generate_for:
          - "lib/data/**.dart"
        options:
          store_date_time_values_as_text: true   # example builder option
      json_serializable:
        generate_for:
          - "lib/data/**/*_dto.dart"
      freezed:
        generate_for:
          - "lib/**/*_model.dart"
          - "lib/**/*_state.dart"
          - "lib/core/**.dart"
      riverpod_generator:
        generate_for:
          - "lib/features/**/*.dart"
```

Rules of thumb:

- Every codegen-carrying package (or the single app package) gets its own
  `build.yaml`.
- A root `build.yaml` may hold shared *options*; per-package files override
  *scope*.
- `generate_for:` globs point at directories, not the whole `lib/`.
- Keep `riverpod_generator` scoped to feature dirs that declare `@riverpod` —
  and only if the team opts into codegen (see the note below).

## Gitignore list (only if you chose the gitignore strategy)

```
**/*.g.dart
**/*.freezed.dart
**/*.drift.dart
**/*.mocks.dart
# gen-l10n output (adjust to your l10n.yaml output-dir), e.g.:
lib/l10n/app_localizations*.dart
```

Mirror these same globs into `analysis_options.yaml` so the analyzer never lints
machine output.

## Error-to-fix recovery map

| Error | Real cause | Fix |
| --- | --- | --- |
| `Missing part 'foo.g.dart'` | codegen not run on a fresh/gitignored tree | run codegen first — do NOT create the file by hand |
| `Undefined class _$Foo` / `_Foo` | freezed/json output stale or absent | regenerate with `--delete-conflicting-outputs`, restart the analysis server |
| `Conflicting outputs` on build | leftover generated file from a rename | pass `--delete-conflicting-outputs` |
| Errors reported *inside* a generated file | stale file or exclude glob matches the wrong suffix | regenerate; then fix the exclude to the emitted suffix |
| `build_runner` fails with analyzer errors in hand-written source | a generator reads a resolved AST; broken source elsewhere in `lib/` blocks generation | fix the hand-written source first |
| `flutter analyze` green but `build_runner` errors | the generator runs extra semantic checks (drift column types, FK targets) the analyzer knows nothing about | trust `build_runner`; fix the flagged annotation |
| Both green, but the app misreads the DB at runtime | schema moved without a `schemaVersion` bump | see `run-migration` — check the bump first |
| Only one package regenerated | ran `build_runner` inside a package dir | run at the workspace root |
| gen-l10n output missing | `flutter gen-l10n` not run / `l10n.yaml` misconfigured | run gen-l10n; verify ARB template + output dir |
