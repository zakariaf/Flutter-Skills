---
name: ci-pipeline-and-gates
description: Enforces a lean GitHub Actions Flutter CI where every gate maps to one named release-blocking contract — pinned runner + subosito/flutter-action@v2 toolchain, dart format --set-exit-if-changed, flutter analyze --fatal-infos, build_runner and drift schema freshness (git diff --exit-code), flutter test --test-randomize-ordering-seed random, static import/banned-string greps that catch what runtime can't, coverage-as-report-never-a-gate with the upward-lie fixed, verify-never-bless goldens (no --update-goldens in CI), and an honest statement of what CI cannot prove (audio, real fonts, on-device behaviour). Use when editing .github/workflows/*.yml, adding or removing a job or step, wiring a codegen/schema/format/analyze/coverage gate, writing a grep-based policy test or gate script under test/policy or tool/, pinning action versions, or claiming CI proves something it can't.
---

# CI Pipeline & Gates

A CI gate is not a decorative green check — it converts one release-blocking contract into a check a build either passes or fails, *without trusting a human*. Keep the pipeline lean: one workflow file for most single-package apps, every job pinned, every gate traceable to a named contract, and an honest note wherever CI cannot prove the thing that actually matters.

Read the reference for the task at hand:

- `references/workflow-skeleton.md` — the copy-paste single-file `ci.yml`: pinned runner + toolchain, freshness gates, format/analyze, randomized tests, host-sqlite, coverage-strip, and the release-build job.
- `references/policy-grep-gate.md` — the grep-based invariant gate: the three-criteria bar, strip-comments-first, anchor-to-structure, accumulate-and-fail-once, write-the-reason-for-a-stranger.

Run `scripts/ci-gates.sh` and `scripts/banned-strings.sh` before a PR to reproduce the static gates locally.

## Non-negotiable rules

1. **Every gate maps to exactly one named contract — name it.** A check that serves no stated contract is not a gate: make it advisory and say so, or don't add it. Never invent a merge-blocker with nothing behind it. This keeps the pipeline auditable and stops gate-sprawl.
2. **Pin the runner AND the toolchain on every job.** `runs-on: ubuntu-24.04` (never `-latest` — image drift moves lcov/toolchain versions with no diff to review) and `subosito/flutter-action@v2` with an explicit `flutter-version` or `flutter-version-file`, `channel: stable`. A floating SDK silently re-renders goldens and perturbs determinism. Bump the version only in a dedicated PR.
3. **Mark unverified action versions inline; never invent a major.** A wrong major silently fails or silently changes behaviour. Write `# VERIFY:` next to a version you haven't confirmed rather than guessing `@v7`.
4. **Format and analyze are hard gates.** `dart format --output=none --set-exit-if-changed .` and `flutter analyze --fatal-infos`. `--fatal-infos` is load-bearing: an info left unfixed is a warning that gets ignored next. See `lint-and-style-config`.
5. **Codegen and schema are freshness gates, not build steps.** Run the generator, then `git diff --exit-code` the outputs; a nonzero diff fails with a message telling the author to regenerate and commit. This is the entire mitigation for committing generated code, and the one gate that catches "changed the schema, forgot to migrate". See `run-codegen`, `run-migration`.
6. **Randomize test ordering; provision native deps the test host needs.** `flutter test --test-randomize-ordering-seed random` is free detection of inter-test state leakage. On Linux, `flutter test` runs in a plain Dart VM where `sqlite3_flutter_libs` does nothing — install host `sqlite3` before a suite that opens a real DB, or it fails for a reason that looks like a broken repo.
7. **Static greps catch what runtime can't — held to the three-criteria bar.** A grep-based gate is legitimate only when the invariant is *textually decidable*, *silent when broken*, and *one line to break* (`references/policy-grep-gate.md`). It proves properties of the *source graph* a passing test never can (an import that isn't reached at runtime, a manifest attribute). Two out of three criteria means code review, not a grep.
8. **Coverage is a published report, never a gate.** No percentage threshold, no paid service. A covered line that asserts nothing is worthless. First fix the upward lie: `flutter test --coverage` omits files no test imports, so an untested file scores zero *denominator* lines, not 0% — one tested file can report ~100%. Include untested files, then strip generated code from `lcov.info`. See `testing-strategy`.
9. **Gates verify, they never bless or mutate the repo.** No `--update-goldens`, no `dart format --fix`, no committing regenerated code from CI — a gate that fixes the thing it checks asserts nothing. Regeneration is a local, human-reviewed act. Goldens run on the pinned runner and CI only compares. See `widget-golden-and-a11y-testing`.
10. **A red gate blocks; be honest about the limits.** Never `continue-on-error: true` on a gate, never merge on a skipped gate, never `// ignore:` a static finding. And state plainly what CI *cannot* prove — audio output, real-font rendering, true on-device behaviour — so the manual on-device pass is treated as a load-bearing release artifact, not a chore.

## The single workflow (single-package default)

One file, `.github/workflows/ci.yml`, is enough for most apps. Pin everything; keep the fast feedback in one job.

```yaml
name: ci
on:
  push: { branches: [main] }
  pull_request:
concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
permissions:
  contents: read
jobs:
  verify:
    runs-on: ubuntu-24.04        # pinned, not -latest — rule 2
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v4          # VERIFY: confirm current major
      - uses: subosito/flutter-action@v2   # v2 is current; there is no v3
        with:
          channel: stable
          flutter-version: '3.29.0'        # pin, or flutter-version-file: .fvmrc
          cache: true
      - run: flutter pub get
      - run: dart format --output=none --set-exit-if-changed .
      - run: flutter analyze --fatal-infos
      - run: flutter test --test-randomize-ordering-seed random --reporter expanded
```

The full skeleton — freshness gates, host-sqlite, coverage strip, and the release-build job — is in `references/workflow-skeleton.md`.

## Freshness gates: run the generator, diff the output

This is why committing `*.g.dart` / `*.freezed.dart` / `*.drift.dart` is safe, and how you catch a schema change with no migration.

```yaml
      - name: Generated code is up to date
        run: |
          dart run build_runner build --delete-conflicting-outputs
          if ! git diff --exit-code -- '*.g.dart' '*.freezed.dart' '*.drift.dart'; then
            echo "::error::Generated code is stale. Run build_runner and commit the result."
            exit 1
          fi
      - name: Schema dumps are up to date
        run: |
          dart run drift_dev schema dump lib/data/app_database.dart drift_schemas/
          if ! git diff --exit-code -- drift_schemas/; then
            echo "::error::drift_schemas/ is stale — you changed the schema without"
            echo "::error::bumping schemaVersion and dumping. Shipping this means NO"
            echo "::error::MIGRATION RUNS and existing rows fail to load."
            exit 1
          fi
```

Check which suffix your codegen actually emits (`.drift.dart` modern vs `.g.dart` legacy part-file) before editing a pattern — don't guess. Never weaken a freshness gate to a warning or run it only on tags.

## Static gates: grep the source graph, fail once

Some contracts are invisible to every test — a banned import that isn't reached at runtime, a config attribute. Grep them. Strip comments first (a rule's own explanation contains its needle), anchor to a *structure* (an import URI, an XML element), accumulate every offender, and fail once with the full list and a reason a stranger would understand.

```dart
// test/policy/banned_imports_test.dart — match the import URI, not the file.
import 'dart:io';
import 'package:test/test.dart';

void main() {
  test('lib/ imports nothing that can reach the network or phone home', () {
    const banned = <String>[
      'package:http/', 'package:dio/',
      'package:firebase_core/', 'package:sentry_flutter/',
    ];
    final importUri =
        RegExp(r'''^\s*import\s+['"]([^'"]+)['"]''', multiLine: true);
    final lineComment = RegExp(r'//[^\n]*');

    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('.g.dart')) continue;
      final code = f.readAsStringSync().replaceAll(lineComment, '');
      for (final m in importUri.allMatches(code)) {
        final uri = m.group(1)!;
        if (banned.any(uri.startsWith)) offenders.add('${f.path}: $uri');
      }
    }
    expect(offenders, isEmpty,
        reason: 'These imports break the no-network promise.\n${offenders.join('\n')}');
  });
}
```

The criteria and pitfalls for authoring these are in `references/policy-grep-gate.md`; `examples/policy_grep_test.dart` is a complete file. The same technique as a shell gate lives in `scripts/banned-strings.sh` for a pre-PR check outside the Dart suite.

## Coverage: measure, publish, do not gate

Fix the upward lie *before* quoting any number, then strip generated code.

```yaml
      # REQUIRED first: include untested files so the denominator is honest —
      # a generated test that imports every lib/ file (see workflow-skeleton.md),
      # otherwise one tested file can report ~100%. Collect coverage in the same
      # randomized run; do not run the suite twice.
      - run: flutter test --coverage --test-randomize-ordering-seed random
      - name: Strip generated code from coverage
        run: |
          lcov --remove coverage/lcov.info \
            'lib/**/*.g.dart' 'lib/**/*.freezed.dart' 'lib/**/*.drift.dart' \
            -o coverage/lcov.info --ignore-errors unused   # lcov 2.x errors on unused patterns
      # Publish for transparency. Do NOT add a min-coverage threshold.
```

Instead of a global threshold, hold a *handful of named files* whose bug is unrecoverable (migrations, a money/units core, a repository write path) at their floor by reading the diff — not by counting lines for a metric already known to lie. See `testing-strategy` for the file-level-floor rationale.

## Goldens in CI: verify, never bless

If you run goldens in CI, run them on the pinned runner and only *compare*. CI must never `--update-goldens` — that makes the gate assert nothing. Cross-OS/font drift is real; goldens made on one host fail on another, so either pin the runner and accept it as authoritative, or keep goldens out of CI and rely on layout-invariant widget tests plus the on-device pass. See `widget-golden-and-a11y-testing` for the two-lane golden strategy.

## When multi-package (workspace)

Only if the repo is a real Dart pub workspace / Melos monorepo — not a single-package app:

- Resolve once at the workspace root (`dart pub get` at root pulls all members); run codegen at the root before analyze (see `run-codegen`).
- Scope banned-import graph checks per package boundary (pure-Dart core imports no `package:flutter`); this is the one place the static gate reads a *resolved* dependency graph rather than source text.
- Keep the pinned `flutter-version` in one `env:` entry referenced by every job so a bump is one edit.

Do not present any of this as required for a small app — it is overhead a single package does not need.

## Anti-patterns

- **`ubuntu-latest` / floating SDK.** Image and toolchain drift move under the workflow with no diff to review, turning a green build into a lie.
- **Inventing an action major.** `@v7` you didn't verify silently fails or changes behaviour; mark `# VERIFY:` and confirm instead.
- **Auto-blessing in CI.** `--update-goldens`, `dart format` writing fixes, committing regenerated code — the gate then asserts nothing.
- **A coverage-percentage gate.** Rewards asserting-nothing tests; and the raw number lies upward until you include untested files.
- **A whole-file `contains` grep.** Hits the rule's own comment and string literals — strip comments and anchor to a structure, or it cries wolf and gets deleted.
- **`expect` inside the offender loop.** Reports offender #1 and hides the rest; accumulate and fail once.
- **`continue-on-error: true` on a gate**, merging on a skipped gate, or `// ignore:` on a static finding — a suppressed gate is exactly the leak it exists to catch.
- **A schema change with no freshness gate.** Ships with no migration; existing data silently fails to load.
- **Claiming green CI proves audio / real-font rendering / on-device behaviour.** It cannot; name the limit and keep the manual pass.
- **Grepping over taste** (banning `default:` on a sealed type, an overflow modifier) — false positives get the directory deleted; that's code review, not a gate.

## Definition of done

- [ ] Every job pins `runs-on: ubuntu-24.04` (or an explicit image) and `subosito/flutter-action@v2` with an explicit `flutter-version`/`flutter-version-file` and `channel: stable`; unverified action versions carry `# VERIFY:`.
- [ ] `dart format --set-exit-if-changed` and `flutter analyze --fatal-infos` run and block.
- [ ] Codegen and (if used) schema freshness run the generator then `git diff --exit-code`, failing with an actionable message.
- [ ] Tests run with `--test-randomize-ordering-seed random`; any native host dep (e.g. `sqlite3`) is installed before the suite that needs it.
- [ ] Each gate maps to one named contract; no unnamed merge-blocker; advisory checks say they're advisory.
- [ ] Static greps (if any) are comment-stripped, structure-anchored, accumulate-and-fail-once, with a stranger-readable reason.
- [ ] Coverage is generated with the upward-lie fixed and generated files stripped, published as a report — no percentage gate.
- [ ] No gate is `continue-on-error`, uses `--update-goldens`, or mutates the repo.
- [ ] The workflow states honestly what CI cannot prove; the manual on-device pass is named as a release artifact.

## Related skills

- `run-codegen` — the deterministic `build_runner` pass whose output the freshness gate diffs.
- `run-migration` — the schema-snapshot ritual the schema-freshness gate protects.
- `lint-and-style-config` — the `analysis_options.yaml` the analyze gate runs, and the `--fatal-infos` promotion.
- `testing-strategy` — the file-level coverage floors and fakes-over-mocks doctrine behind the coverage rule.
- `widget-golden-and-a11y-testing` — the two-lane golden strategy and why CI only verifies, never blesses.
- `codegen-and-toolchain` — SDK pinning, per-package `build.yaml`, and analyzer/coverage excludes referenced by the gates.
- `dependency-hygiene` — the committed lockfile and version-pinned lint include the gates assume.
- `design-review-workflow` — the once-per-app manual QA sweep that covers what CI cannot prove.
- `run-goldens-rebaseline` — the local, human-reviewed blessing ritual CI must never perform.
- `release-and-store-shipping` — what happens after the gates are green: the signed artifact, archived symbols, store declarations, and staged rollout.

## References

- subosito/flutter-action — Flutter environment for GitHub Actions. https://github.com/subosito/flutter-action
- Flutter — build and release an Android app. https://docs.flutter.dev/deployment/android
- Flutter API — `matchesGoldenFile` (goldens are OS/font/version-sensitive; `--update-goldens`). https://api.flutter.dev/flutter/flutter_test/matchesGoldenFile.html
- Dart — `dart test` runner flags (`--test-randomize-ordering-seed`). https://dart.dev/tools/dart-test
- Code With Andrea — Flutter test coverage (`lcov.info`, stripping generated files, the untested-file lie). https://codewithandrea.com/articles/flutter-test-coverage/
- Dart — pub workspaces (monorepo). https://dart.dev/tools/pub/workspaces
- GitHub Actions — using concurrency, permissions, and pinned runners. https://docs.github.com/actions
