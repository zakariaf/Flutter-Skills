# The SDK version record and the silent-lint-disable trap

Two things move together on any SDK bump and one of them fails silently. Do both in the same commit as the `flutter upgrade`.

## Pin the record, not the tool

`environment: sdk:` in `pubspec.yaml` stays a **normal range** so `pub` can solve. That range is not a record of what was tested — it is a solvability constraint. Record the exact tested Flutter version separately, in a small committed file that CI and a stranger both read.

The common choice is a repo-root `.fvmrc` (JSON):

```json
{ "flutter": "3.27.1" }
```

- It is **JSON** — read with `jq -r '.flutter'`. The `flutter: 3.27.1` YAML form that gets copied around is the shape of a `pubspec.yaml` `environment:` block (`yq eval '.environment.flutter'`), and is wrong in `.fvmrc`.
- Channel names (`stable`, `beta`, `master`) are valid values there too — it is not exact-versions-only.
- CI reads it: `subosito/flutter-action` accepts `flutter-version-file: .fvmrc`.

**Installing a version-manager tool is optional and usually unnecessary for a solo repo** — the *file* earns its place because CI and a stranger read it; the tool solves switching between many projects. Bump the string by hand, in the same commit as the upgrade. (Any equivalent committed record — a `.tool-versions`, a documented CI input — is fine; the principle is: a real range in the pubspec, an exact recorded string elsewhere.)

## The coupled edit that fails silently

The resolved Dart/Flutter version decides which version of your lint ruleset package (`very_good_analysis`, or any versioned ruleset) resolves. If your `analysis_options.yaml` pins a **version-stamped include filename**, that filename must exist inside the *resolved* package:

```yaml
# analysis_options.yaml
include: package:very_good_analysis/analysis_options.6.0.0.yaml
```

Each `very_good_analysis` release ships a differently-named file (`analysis_options.6.0.0.yaml`, `analysis_options.7.0.0.yaml`, …). If the SDK bump lands you on a *different* version of the package than the filename names, the analyzer does not throw. It emits a single diagnostic:

```
warning • include_file_not_found
```

Default `dart analyze` / `flutter analyze` treat warnings as fatal, so this one turns standard CI **red** — the common case is caught, not missed. The genuinely silent case is narrow: a pipeline that runs analyze with warnings made non-fatal (`--no-fatal-warnings`) or that suppresses this diagnostic. And even then it is not "zero rules" — the analyzer's own built-in lints keep running; what stops applying is only the rules your included ruleset *added or promoted*. On a project where that strict ruleset is the safety net, a pipeline that reports green while silently running only the built-ins is the trap to guard against.

### The fix: verify the include after every SDK bump

In the same commit as the `.fvmrc` bump:

```sh
# 1. update the SDK record, then resolve
flutter pub get

# 2. confirm the pinned include file actually exists in the resolved package
ls ~/.pub-cache/hosted/pub.dev/very_good_analysis-*/lib/
```

If the file your `include:` names is not in that listing, either update the include filename to one that exists in the resolved version, or pin the package version so the two agree. `scripts/audit-deps.sh` performs this check when it can locate the resolved ruleset package.

### Avoiding the trap entirely

Some rulesets ship an unversioned `analysis_options.yaml` alongside the stamped ones; including that (`include: package:very_good_analysis/analysis_options.yaml`) tracks whatever version resolves and cannot 404 — at the cost of not knowing exactly which rules you got. Prefer the stamped include *with* the post-bump verification above; it is the honest, reproducible choice. See `lint-and-style-config` for the full ruleset setup.
