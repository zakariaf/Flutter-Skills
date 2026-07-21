# Reference — the single-file workflow skeleton

A complete `.github/workflows/ci.yml` for a single-package Flutter app. One `verify`
job carries the fast feedback; a separate `build-android` job proves the release
artifact compiles. Everything is pinned. Copy, fill the `TODO`s, delete steps you
don't need — do not add steps that serve no named contract.

```yaml
name: ci

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  verify:
    runs-on: ubuntu-24.04        # pinned, not -latest: lcov 2.x + image drift are real
    timeout-minutes: 20
    steps:
      # VERIFY before first run: action majors drift. Confirm the current major
      # for actions/checkout and any setup-* action rather than guessing.
      # subosito/flutter-action is v2 (there is no v3).
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: '3.29.0'   # pin exactly, OR:
          # flutter-version-file: .fvmrc   # JSON: { "flutter": "3.29.0" }
          cache: true
          pub-cache: true

      - run: flutter --version
      - run: flutter pub get

      # --- Freshness gates: the whole mitigation for committing generated code. ---
      - name: Generated code is up to date
        run: |
          dart run build_runner build --delete-conflicting-outputs
          if ! git diff --exit-code -- '*.g.dart' '*.freezed.dart' '*.drift.dart'; then
            echo "::error::Generated code is stale. Run build_runner and commit the result."
            exit 1
          fi

      # Only if you use Drift with committed schema dumps:
      - name: Schema dumps are up to date
        run: |
          dart run drift_dev schema dump lib/data/app_database.dart drift_schemas/
          if ! git diff --exit-code -- drift_schemas/; then
            echo "::error::drift_schemas/ is stale — schema changed without a"
            echo "::error::schemaVersion bump + dump. Shipping this runs NO migration."
            exit 1
          fi

      # --- Static analysis ---
      - run: dart format --output=none --set-exit-if-changed .
      - run: flutter analyze --fatal-infos

      # --- Native host deps the plain-Dart-VM test host needs ---
      # flutter test runs in a Dart VM where sqlite3_flutter_libs does NOTHING;
      # a real-DB suite fails on Linux without the host library.
      - run: sudo apt-get update -qq && sudo apt-get install -y -qq libsqlite3-dev

      # --- Tests + coverage: ONE run — randomize order AND collect coverage.
      # Running the suite a second time just for --coverage doubles CI time for
      # no gain; --coverage records the same randomized run.
      #
      # But make the denominator honest FIRST. `flutter test --coverage` OMITS
      # files no test imports, so an untested file contributes zero DENOMINATOR
      # lines (not 0%) and a single tested file can report ~100%. This step is
      # REQUIRED, not optional — the skeleton lies upward without it. It generates
      # a reference test that imports every lib/ file (dependency-free) so those
      # files land in the denominator:
      - name: Include untested files so the coverage denominator is honest
        run: |
          pkg=$(grep -E '^name:' pubspec.yaml | head -1 | awk '{print $2}')
          {
            echo "// GENERATED for coverage — imports every lib/ file so untested"
            echo "// files count in the denominator. CI-only; never committed."
            echo "// ignore_for_file: unused_import, directives_ordering"
            find lib -name '*.dart' \
              ! -name '*.g.dart' ! -name '*.freezed.dart' ! -name '*.drift.dart' \
              | sed -E "s#^lib/#import 'package:$pkg/#; s#\$#';#"
            echo "void main() {}"
          } > test/zzz_coverage_all_files_test.dart

      - name: Test with coverage (randomized order surfaces state leakage)
        run: flutter test --coverage --test-randomize-ordering-seed random --reporter expanded

      # --- Coverage: report, never a gate ---
      - name: Strip generated code from coverage
        run: |
          lcov --remove coverage/lcov.info \
            'lib/**/*.g.dart' 'lib/**/*.freezed.dart' 'lib/**/*.drift.dart' \
            -o coverage/lcov.info --ignore-errors unused
      # - uses: <coverage uploader>   # TODO: transparency only — do NOT add a % gate

  build-android:
    needs: verify
    runs-on: ubuntu-24.04
    timeout-minutes: 20
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4      # VERIFY current major
        with:
          distribution: temurin
          java-version: '17'
          cache: gradle
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
          flutter-version: '3.29.0'      # keep == verify job's pin
          cache: true
      - run: flutter pub get

      # Unsigned: CI proves it compiles. Signed releases are built and uploaded
      # by a human, or by a separate release workflow whose keystore lives ONLY
      # in encrypted secrets. No signing secret in this job = nothing to leak.
      - run: flutter build appbundle --release

      - uses: actions/upload-artifact@v4  # VERIFY current major
        with:
          name: app-release-unsigned-aab
          path: build/app/outputs/bundle/release/app-release.aab
          retention-days: 14
```

## Rules the YAML encodes

| Line | Why it must not be undone |
|---|---|
| `ubuntu-24.04`, not `-latest` | Image drift moves lcov and toolchain versions under the workflow with no diff to review. |
| `flutter-version` / `flutter-version-file` pinned | A floating SDK re-renders goldens and can perturb any determinism snapshot. Bump only in a dedicated PR. |
| `# VERIFY:` on action majors | A wrong major silently fails or changes behaviour; never invent one. |
| freshness gate = generate + `git diff --exit-code` | The only safe way to commit generated code; the schema gate catches "changed schema, no migration". |
| `libsqlite3-dev` before the DB suite | `flutter test` uses a plain Dart VM; without the host lib the DB tests fail for a reason that looks like a broken repo. |
| `--test-randomize-ordering-seed random` | Free detection of inter-test state leakage — matters most when a suite shares one in-memory DB. |
| `--fatal-infos` | The analyzer is a primary feedback loop; an unfixed info becomes an ignored warning. |
| unsigned CI build | CI proves compilation; signing belongs to a secrets-scoped release path or a human. |

## What this skeleton deliberately omits

- **Golden jobs by default.** Cross-OS/font drift makes them fragile; if you add one, pin the runner and never `--update-goldens` in CI. See `widget-golden-and-a11y-testing`.
- **Emulator / `integration_test` CI.** 15-minute runs, VM-service timeouts, green-locally/red-in-CI flake. Add only for a specific journey you've decided is worth it.
- **A release/publish pipeline.** For a small app, build and sign on a machine you control or in a separate secrets-scoped workflow triggered by an immutable `v*.*.*` tag — never a moving ref.
- **Branch protection / CODEOWNERS / templates.** Add them when there is a team to coordinate; on a solo repo they are prepayment.

## What CI cannot prove — state it in the workflow

Green CI proves the code compiles, is formatted, analyzes clean, passes tests, and
that generated code matches source. It proves nothing about:

- **Audio output.** No supported hook captures PCM from platform TTS/audio APIs; a test can assert a channel call was issued, never that sound came out.
- **Real-font rendering / layout on device.** Goldens on a CI host are not the device; the on-device pass is the fidelity proof.
- **True platform behaviour** behind a plugin (permissions, background execution, notification delivery).

The consequence is not "write more tests" — it is that the **manual on-device pass is a
load-bearing release artifact**. When a change touches a path CI structurally cannot
observe, say plainly that green CI is not evidence and the device pass is the check.
See `design-review-workflow`.
