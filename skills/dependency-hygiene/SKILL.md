---
name: dependency-hygiene
description: Enforces pubspec/lock discipline — caret ranges in pubspec.yaml with a committed pubspec.lock as the only pin, a separately-recorded SDK version string, a version-pinned very_good_analysis include (whose missing file fails default analyze, or silently drops the ruleset where warnings are non-fatal), transitive-tree auditing before adding a package, a dependency gate that refuses network/telemetry/crash/ads/heavy-transitive deps by policy, and vendoring any bus-factor-1 native plugin behind an interface into third_party/. Use when running dart pub add/get/upgrade/outdated/deps, editing pubspec.yaml or pubspec.lock, bumping the Flutter/Dart SDK, choosing or rejecting a new dependency, removing a package, or auditing what a dependency drags in.
---

# Dependency hygiene

Every dependency is a permanent liability someone else may have to service. Optimise for *resolves and builds years from now*, not for *latest*. This skill governs pubspec/lock mechanics, the gate a new package must pass, and the escape hatch when a critical package rots.

Read the reference for the task at hand:
- `references/dependency-gate-and-audit.md` — the refuse/accept gate, transitive auditing, licence recording, upgrade discipline.
- `references/sdk-pin-and-lint-include.md` — recording the SDK version and the silent-lint-disable trap on any SDK bump.
- `references/vendoring-behind-an-interface.md` — vendoring a bus-factor-1 native plugin into `third_party/` without touching `lib/`.

Run `scripts/audit-deps.sh` before a PR that changes `pubspec.yaml`.

## Non-negotiable rules

1. **Caret ranges in `pubspec.yaml`, exact pins only in `pubspec.lock`.** `drift: ^2.31.0`, never `drift: 2.31.0`. The lock pins; ranges only keep resolution solvable. Exact pins in a pubspec manufacture unsolvable conflicts on the next SDK bump and buy nothing the lock is not already delivering.
2. **Commit `pubspec.lock`.** This is an application, not a package — the asymmetry that flips the rule. The default Dart `.gitignore` template lists `pubspec.lock`; delete that line. The committed lock is the only thing that makes a stranger's `git clone` resolve the exact versions that were tested on a real device.
3. **A `pubspec.yaml` diff without its `pubspec.lock` delta is incomplete.** Run `flutter pub get` and stage the lock in the same commit — add, upgrade, and remove alike.
4. **Record the SDK version separately from the tool.** Keep `environment: sdk:` a real range so `pub` can solve; pin the exact tested Flutter version in a committed record CI reads (see reference). The record is what a stranger and CI read; do not confuse a version-manager tool with the file.
5. **The lint include filename is coupled to the resolved SDK.** A version-pinned `include:` that names a file absent from the *resolved* linter package emits `include_file_not_found` — fatal to default `dart analyze`/`flutter analyze`, so standard CI catches it. It only goes silent-and-green where warnings are made non-fatal, and even then it is your ruleset's added/promoted rules that stop applying, not the analyzer's built-ins. Verify it after any SDK bump (see reference).
6. **Audit the transitive tree before adding, not the pubspec.** The second hop is exactly where a banned SDK arrives. Run `scripts/audit-deps.sh` (or `dart pub deps --json` + the audit script) before committing a new dependency.
7. **Refuse by policy anything that opens a network path, reports crashes/usage, drags in a telemetry core, or collects device identifiers for an unshipped feature** — directly *or transitively*. Green CI is not evidence a native capability works. See the gate reference.
8. **Grep `lib/` after removing a dependency.** A package deleted from `pubspec.yaml` but still transitively resolvable keeps compiling today and breaks on the clone that matters. The analyzer catches an unresolved import, not one that resolves by accident.
9. **Wrap a bus-factor-1 native plugin behind an interface *now*, vendor *later*.** The interface is cheap insurance; pre-emptive vendoring is a maintenance burden against a break that has not happened. See the vendoring reference.

## Ranges in pubspec, pins in the lock

| Do | Never |
|---|---|
| Caret range: `drift: ^2.31.0` | Exact pin: `drift: 2.31.0` |
| `environment: sdk: ^3.6.0` — a real range | An exact `sdk:` version |
| Commit `pubspec.lock` | Gitignore `pubspec.lock` |

The lock is authoritative. Ranges keep the solver able to move on an SDK upgrade; the lock keeps everyone on the versions that were actually verified.

## The gate every new dependency must pass

Refuse a package if it — or **anything in its transitive tree** — does any of:

- **Opens a network path** you did not choose (`http`, `dio`, sockets, gRPC) when the product promise is no-network or offline-first.
- **Reports crashes or usage** (Crashlytics, Sentry, any analytics or attribution SDK) against a no-telemetry policy.
- **Drags in a telemetry/analytics core** transitively — a crash SDK's core can worsen the store privacy label even when you never call it.
- **Collects device identifiers** for a feature you do not ship.
- **Requires an `--enable-experiment` flag** — an abandoned repo that needs an experiment to build stops building.

Also weigh, and usually refuse: any bus-factor-1 package *not* behind an interface; anything whose function is a few hundred lines of first-party Dart; anything that only exists to save typing. Record the licence — a permissive one (MIT, BSD, Apache-2.0) is a precondition for the vendoring escape hatch; a copyleft dependency removes that option. Full checklist in `references/dependency-gate-and-audit.md`.

## Auditing the transitive tree

```sh
dart pub add --dry-run <package>     # see what would resolve, resolve nothing
dart pub deps --json > /tmp/deps.json
scripts/audit-deps.sh                 # walks the resolved set, flags banned patterns
```

The audit walks the full resolved graph, matches each name against a policy pattern list, marks every hit `direct` or `TRANSITIVE`, and separates APK-shipping deps from build/test-only ones (a banned package reachable *only* from `dev_dependencies` never reaches the binary and is not a shipping defect). Exit 1 means refuse the dependency or find one that does not pull those in. To learn who introduced a package: `dart pub deps | grep -B4 <name>`.

Edit the `BANNED`/`ALLOW` lists at the top of `scripts/audit_deps.py` to match *your* policy; every `ALLOW` entry needs a written justification beside it.

## Upgrading

Run `dart pub outdated` on your own schedule; there is no bot. **Dependabot has never supported pub; Renovate raises PRs a solo repo has no workflow for.** Keep their one useful idea by hand: never blind-upgrade a native plugin your app's core capability depends on.

**Green CI is not evidence of a native capability.** No CI job on a headless emulator can prove the app plays audio, reads a sensor, or talks to a platform channel end-to-end — `integration_test` can assert a channel call was *issued*, nothing more. After any bump to a capability-critical native plugin or the SDK itself, run a manual pass on a real device. After any upgrade touching a codegen package (`drift`, `freezed`, `json_serializable`), regenerate and commit — stale generated code is caught by CI, not the analyzer (see `run-codegen`).

## Vendoring a bus-factor-1 plugin

A single-maintainer native plugin whose failure means the app cannot build is the one dependency worth pre-planning for. The mitigation is a thin interface, authored on day one, so vendoring never touches `lib/`:

```dart
// A port the app depends on; the plugin lives behind it. The `Gateway` suffix
// marks a thin wrapper over a SPECIFIC plugin (here flutter_secure_storage) —
// `naming-conventions` owns that Service-vs-Gateway distinction.
abstract interface class SecureStorageGateway {
  Future<void> write(String key, String value);
  Future<String?> read(String key);
}
```

Only when the plugin actually breaks — stops building against a Flutter release, or ships a regression upstream will not fix — clone it at the last-good tag into `third_party/<plugin>/`, point the pubspec at `path:`, record the SHA and every changed line in a `VENDORED.md`, confirm the licence permits redistribution, and **patch, don't refactor**. Full procedure and triggers in `references/vendoring-behind-an-interface.md`. See `examples/vendored_plugin_behind_interface.dart`.

## Removing a dependency

Delete the pubspec entry, run `flutter pub get`, commit the `pubspec.lock` delta in the same commit — then `grep -r "package:<name>" lib/`. A transitively-resolvable import compiles today and breaks the clone that matters.

## When multi-package (workspace)

In a Dart pub workspace / monorepo, each package keeps its own `pubspec.yaml` with ranges, but the **workspace resolves one shared lock at the root** — audit and commit that root lock. Run the audit against the whole workspace's resolved tree, not one package's. A single package's pubspec cannot show what a sibling drags into the shared resolution. See `codegen-and-toolchain` for workspace toolchain mechanics.

## Anti-patterns

- **Exact pin in `pubspec.yaml`.** Turns the next SDK upgrade into an unsolvable-conflict debugging session; the lock already pins.
- **Gitignoring `pubspec.lock` in an app.** A fresh clone resolves whatever `pub` feels like today, not what was tested.
- **Editing pubspec without committing the lock delta.** The next machine resolves a different graph.
- **Reading `pubspec.yaml` to decide if a dep is safe.** The banned SDK is on the second hop, invisible there.
- **Trusting green CI for a native capability.** The emulator has no voice engine / real sensor; green proves the Dart compiled, not that the feature works.
- **Pre-emptively vendoring a healthy plugin.** You take on the maintenance burden before any break; the interface is the cheap insurance, not the fork.
- **Vendoring by refactoring.** Every line you touch in `third_party/` is a line you own forever — patch the break and stop.
- **Adding a bus-factor-1 package with no interface.** When it rots you have no seam to vendor behind.

## Definition of done

- [ ] New/changed deps use caret ranges; no exact pins in any `pubspec.yaml`.
- [ ] `pubspec.lock` delta is staged in the same commit as the `pubspec.yaml` change.
- [ ] `scripts/audit-deps.sh` exits 0 (or every hit has a justified `ALLOW` entry).
- [ ] On an SDK bump: the version record is updated and the pinned lint `include:` file is confirmed present in the resolved package (`references/sdk-pin-and-lint-include.md`).
- [ ] Licence recorded for any new dependency; permissive if it is a vendoring candidate.
- [ ] Capability-critical native plugin sits behind an interface; a real-device pass was run after its bump.
- [ ] After a removal: `grep -r "package:<name>" lib/` is empty.

## Related skills

- `codegen-and-toolchain` — workspace linking, SDK pinning at the toolchain level, generated-code commit-vs-gitignore.
- `run-codegen` — the deterministic `build_runner` pass to run after upgrading a codegen package.
- `lint-and-style-config` — the strict `analysis_options.yaml` the version-pinned `include:` feeds.
- `service-boundary-and-native` — the injectable-interface-per-side-effect pattern the vendoring seam relies on.
- `naming-conventions` — owns the `Service`-vs-`Gateway` boundary-suffix rule; a plugin wrapper like `SecureStorageGateway` takes the `Gateway` suffix.
- `ci-pipeline-and-gates` — wiring the audit and lock-freshness checks into CI.

## References

- Dart — Package dependencies & version constraints: https://dart.dev/tools/pub/dependencies
- Dart — `pubspec.lock` and glossary: https://dart.dev/tools/pub/glossary#lockfile
- Dart — `dart pub deps`: https://dart.dev/tools/pub/cmd/pub-deps
- Dart — `dart pub outdated`: https://dart.dev/tools/pub/cmd/pub-outdated
- Dart — Pub workspaces: https://dart.dev/tools/pub/workspaces
- Flutter — Adding plugin packages / path dependencies: https://docs.flutter.dev/packages-and-plugins/using-packages
