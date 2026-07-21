# The dependency gate and transitive audit

A dependency is a permanent liability. The gate below is what a new package must survive before it earns a line in `pubspec.yaml`. The audit is how you check the part of the tree a human eye cannot see.

## The refuse-outright list

Refuse a package if it — or **anything in its transitive tree** — does any of these. "Refused" means not added, not "added and disabled".

| Trait | Why it is refused |
|---|---|
| Opens a network path (`http`, `dio`, sockets, gRPC, `web_socket_channel`) | If the product promise is offline-first or no-network, an unchosen network client changes what the app *is*. Even inert code widens the attack and privacy surface. |
| Reports crashes or usage (Crashlytics, Sentry, any analytics) | Telemetry against a no-telemetry policy. The on-device, user-exportable log is the honest field signal. |
| Drags in a telemetry/analytics *core* transitively | A crash SDK's core can register data categories that worsen the app-store privacy label even if you never call it. The label must stay true down to the last transitive package. |
| Ads / attribution SDK (`google_mobile_ads`, `appsflyer`, `adjust`) | Network + persistent identifiers. |
| Collects device identifiers (`device_info_plus`, `package_info_plus`) for an unshipped feature | Identifiers you do not need are liability you do not need. Allow only with a named, shipped use. |
| Requires an `--enable-experiment` flag to build | An abandoned repo that needs an experiment stops building on the next stable SDK. |

These patterns are policy defaults. Encode *your* project's policy in the `BANNED` list at the top of `scripts/audit_deps.py`; a no-network product bans network clients, a normal product does not.

## The weigh-and-usually-refuse list

- **Bus-factor-1 and not behind an interface.** A single maintainer is a single point of failure. Acceptable *only* if the app depends on it through an interface it can vendor behind (see `vendoring-behind-an-interface.md`).
- **A few hundred lines of first-party Dart.** If you could write and own it in an afternoon, a dependency is a worse deal than the code.
- **Exists only to save typing.** Extension-method sugar, tiny wrappers — the transitive and upgrade cost outlives the convenience.

## Record the licence

Record every new dependency's licence in the PR. A permissive licence (MIT, BSD, Apache-2.0) is a **precondition** for the vendoring escape hatch — redistributing source under those requires retaining the notice, which is cheap. A copyleft dependency (GPL/AGPL) removes vendoring as an option permanently and may impose obligations on your whole binary; treat it as a hard stop unless legal review says otherwise.

## pub.dev popularity is the wrong metric

Popularity score is irrelevant to whether a package will still resolve and build in three years. What matters:

- **Maintainer count** — one is a risk, zero is a countdown.
- **Last publish date** — staleness against the current SDK is the real threat.
- **Open-issue shape** — build failures against recent Flutter releases sitting unanswered are the signal that matters, not the raw count.
- **Licence** — as above.

## Auditing the tree, not the pubspec

A direct read of `pubspec.yaml` cannot see the second hop, which is exactly where a banned SDK arrives (a UI package that quietly pulls a telemetry core, a "utils" package that pulls an http client). Before adding anything:

```sh
dart pub add --dry-run <package>       # resolve nothing, just preview the graph delta
dart pub deps --json > /tmp/deps.json
scripts/audit-deps.sh                   # or: python3 scripts/audit_deps.py /tmp/deps.json
```

The audit script:

- walks the **full resolved set**, not the direct list;
- matches each package name against the policy `BANNED` patterns;
- marks each hit `direct` or `TRANSITIVE`;
- separates **APK-shipping** deps (reachable from `dependencies:`) from **build/test-only** deps (reachable only from `dev_dependencies:`). A banned package reachable *only* through dev tooling — e.g. a codegen tool that runs a local watch-mode HTTP server — never reaches the binary and is **not a shipping defect**. A gate that fails on an unavoidable dev dependency gets switched off, which is worse than no gate.

Exit 1 = a banned package ships. Refuse it or find an alternative. To see who pulls a package in: `dart pub deps | grep -B4 <name>`.

### The ALLOW escape hatch

Sometimes a banned pattern reaches the tree through a package you have deliberately chosen (e.g. a platform-interface package that links an http client the app can never actually reach because there is no network permission / no call site). Add that exact name to the `ALLOW` set at the top of `audit_deps.py` **with a written justification beside it** explaining why the reachable-but-inert dependency is acceptable and what the real, enforced gate is. An unjustified allow entry is a hole.

## Upgrade discipline

- `dart pub outdated` on your own cadence. No Dependabot (never supported pub), no Renovate (raises PRs a solo repo has no workflow for).
- Never blind-upgrade a native plugin the app's core capability depends on.
- **Green CI is not evidence of a native capability.** A headless emulator ships no voice engine, no real sensor, no camera feed; `integration_test` can assert a platform-channel call was *issued*, not that the OS did anything with it. After any bump to a capability-critical plugin or the SDK, run a manual pass on real hardware.
- After any upgrade touching a codegen package (`drift`/`drift_dev`, `freezed`, `json_serializable`), regenerate and commit — stale generated code is caught by CI, not the analyzer.
