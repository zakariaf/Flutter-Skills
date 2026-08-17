---
name: release-and-store-shipping
description: >-
  Enforces the path from a green CI run to a shipped build — pubspec `version: x.y.z+N`
  as the single source of versionName/versionCode (monotonic, never reused), the release
  artifact verified on real hardware, signing and store API keys that never enter the
  repo, `--obfuscate --split-debug-info` with symbols archived per build or that
  release's crash reports are permanently unreadable, a permission set audited from the
  MERGED manifest and asserted whole, store declarations (Data Safety, nutrition labels,
  privacy manifests) provable in the repo and read back rather than trusted, size and
  cold-start budgets, and a staged rollout with a halt plan. Use when cutting or tagging
  a release, editing `android/app/build.gradle(.kts)`, `key.properties`,
  `AndroidManifest.xml`, `Info.plist` or `PrivacyInfo.xcprivacy`, bumping a version,
  uploading to Play or TestFlight, writing store-listing or privacy copy, symbolizing a
  crash, chasing size, or diagnosing an upload rejection or a blocked submission.
---

# Release and store shipping

CI proves the *code*; a release proves the *artifact*. Everything here is about the
exact bundle a stranger installs — built with R8, obfuscation, tree-shaking, and
release-mode asserts stripped, signed by a key you must never lose, declaring
things about itself to a store that will pull the app if they are untrue. This
skill starts where `ci-pipeline-and-gates` ends and where `design-review-workflow`
signs off.

**Building, signing, uploading, and tagging are side-effecting and irreversible in
part** (a published build number can never be reused; an iOS build can never be
unshipped). Never run them because a task seemed to imply a release — run them only
when the developer asks for a release by name. Reading and enforcing the *config*
rules below is always in scope.

Run `scripts/check-release-hygiene.sh` before any release build (and in CI): it is the
static half of this skill — tracked credentials, a malformed build number, debug
signing, and debug affordances, none of which need a build to catch. Run
`scripts/check-ipa-slices.sh` on the built IPA *before* spending an upload. Platform depth
lives in `references/android-play.md`, `references/ios-app-store.md`,
`references/app-store-connect-submission.md`, and
`references/privacy-permissions-and-claims.md`.

## Non-negotiable rules

1. **`pubspec.yaml`'s `version: x.y.z+N` is the only version source.** `x.y.z` →
   `versionName` / `CFBundleShortVersionString`, `N` → `versionCode` /
   `CFBundleVersion`. Override per build only with `--build-name` / `--build-number`;
   never hardcode a version in `build.gradle` or `Info.plist`. WHY: two sources
   silently diverge and the crash report then names a version that never shipped.
2. **The build number only ever goes up, and a published one is burned forever.**
   Play rejects a reused or lower `versionCode`; App Store Connect rejects a reused
   `CFBundleVersion` for the same short version. A failed upload still burns the
   number — bump, don't retry.
3. **No signing material in the repository, ever.** Keystore/`.jks`/`.p12`, the App
   Store Connect API key (`.p8`), the Play service-account JSON, and
   `android/key.properties` are gitignored and injected from a secret store. WHY: a
   key in git history is compromised permanently, and rotating an *app signing* key
   is a store-side process you do not want to discover during a release.
4. **Enroll in Play App Signing and keep the upload key separate.** With Play App
   Signing, a lost *upload* key is recoverable via support; a lost *app signing* key
   for an unenrolled app means the listing can never be updated again — a dead app.
5. **Obfuscate and split debug info, then archive the symbols with the artifact.**
   `--obfuscate --split-debug-info=<dir>` is mandatory for every uploaded build, and
   `<dir>` must be versioned per build (`symbols/<x.y.z>+<N>/`) and stored
   off-machine. WHY: symbol files are the *only* way to read that release's stack
   traces; regenerating them later produces different symbols and decodes nothing.
6. **Verify the release artifact itself, on real hardware.** Install the exact `.aab`
   (via Play internal app sharing / `bundletool`) or the exact TestFlight build —
   never a debug or profile build, never "it worked in the emulator." WHY: R8,
   resource shrinking, and obfuscation only run in release, so reflective plugins,
   missing ProGuard rules, and stripped asserts fail *first* in the artifact you ship.
7. **Assert the permission set whole, from the MERGED manifest.** Transitive plugins
   inject permissions you never wrote. Read the merged output (not your source
   manifest), strip what you do not need with `tools:node="remove"`, and keep a
   committed expected-permission list that a gate diffs against. On iOS every
   `NS*UsageDescription` present must be honest and every one you need must exist —
   a missing usage string is an App Review rejection, an unused one is a claim you
   cannot defend. See `references/privacy-permissions-and-claims.md`.
8. **Every store declaration must be provable in the repo.** Play Data Safety, App
   Store privacy nutrition labels, and `PrivacyInfo.xcprivacy` (required-reason APIs
   + third-party SDK privacy manifests) describe what the *code* does. Add a crash
   reporter, an ads SDK, or an analytics package and the declaration changes in the
   same PR. WHY: a false declaration is a takedown, not a warning.
9. **No absolute privacy claims.** Ban "nothing ever leaves your device" and
   "completely private" as listing/onboarding copy. State the mechanism instead —
   what is stored, where, what leaves, and when. WHY: one crash upload, one
   share-sheet export, or one map tile makes the absolute sentence a lie.
10. **Debug affordances must be unreachable in release.** Dev menus, fixture seeding,
    `eraseDatabaseOnSchemaChange`, log-everything sinks, and staging endpoints are
    compiled out or behind a flavor that is not the store flavor — proved by a grep
    gate, not by memory. WHY: shipped, they wipe or leak real user data.
11. **Size and cold start are measured on the release build and recorded per
    release.** `--analyze-size` for bytes, `--trace-startup` in profile for the first
    frame, on a real low-end target device. A regression past the recorded budget is
    a release blocker, not a note.
12. **Roll out in stages with a written halt criterion.** internal → closed →
    production at a staged percentage, with the crash-free-sessions threshold that
    triggers a halt decided *before* the rollout starts. WHY: Play rollouts can be
    halted; an App Store release can only be superseded by another build.
13. **One tagged commit ships.** Tag the exact commit, attach release notes, and keep
    the artifact + symbol archive with the tag. The dated design-review sign-off
    (`design-review-workflow`) is a precondition, not part of this pass.
14. **Store-side gates are account-holder-only, and store-side state is never assumed.**
    Creating the app record, the privacy questionnaire, and the Paid Applications
    Agreement have no API and block on a human — raise them on day one. An inactive Paid
    Applications Agreement makes StoreKit return **zero products**, which presents as a
    broken purchase button, not as a missing agreement. Everything that *is* API-settable
    (price, territory availability, in-app purchase state, screenshots, metadata) is read
    **back** from the store before submission — a green upload log is not server state, and
    a committed screenshot folder is not an uploaded screenshot set. WHY: every one of these
    blocks submission with a message that names a symptom rather than the setting. See
    `references/app-store-connect-submission.md`.

## The ordered release ritual

Run only when a release is explicitly requested. Do not reorder or skip.

1. **Preconditions.** Working tree clean; CI green on the release commit; the dated
   design-review sign-off exists; the changelog/release notes are written.
2. **Bump `version:` in `pubspec.yaml`** — semantic `x.y.z` for the user-visible
   change, `+N` incremented past the highest number ever uploaded. Commit alone.
3. **Build the artifact with obfuscation and versioned symbols.**
   ```bash
   flutter build appbundle --release \
     --obfuscate --split-debug-info=build/symbols/1.4.0+42
   flutter build ipa --release \
     --obfuscate --split-debug-info=build/symbols/1.4.0+42 \
     --export-options-plist=ios/ExportOptions.plist
   ```
4. **Archive `build/symbols/1.4.0+42/` off-machine** alongside the artifact, before
   anything is uploaded. This is the step nobody misses twice.
5. **Verify the artifact on real hardware** — install the built bundle, walk the
   primary flow, force-stop and relaunch, and upgrade *over the previous released
   version* so the real migration path runs (see `run-migration`).
6. **Measure the budgets** and record them next to the previous release's numbers:
   ```bash
   flutter build appbundle --release --analyze-size   # bytes, by library/asset
   flutter run --profile --trace-startup              # start_up_info.json
   ```
7. **Reconcile the declarations** — merged permission set, Data Safety / nutrition
   labels / `PrivacyInfo.xcprivacy`, and every privacy sentence in the listing,
   against what the code now does.
8. **Upload to the internal track / TestFlight and smoke-test from the store**, not
   from a local install — store delivery re-signs and re-compresses the artifact.
9. **Reconcile store-side configuration by reading it back** — price and territory
   availability set, in-app purchases ready and attached to the version, screenshots
   present for every required display type, metadata complete, and the account-holder-only
   gates (privacy questionnaire, Paid Applications Agreement) done. Query the store; do not
   trust the tool that wrote them (`references/app-store-connect-submission.md`).
10. **Tag the commit, publish the notes, then start the staged rollout** and watch the
    crash-free rate against the halt criterion agreed in step 1.

## Version and build number mapping

| `pubspec.yaml` | Android | iOS | Rules |
|---|---|---|---|
| `x.y.z` | `versionName` | `CFBundleShortVersionString` | User-visible; may repeat across builds of the same release |
| `+N` | `versionCode` | `CFBundleVersion` | Integer, strictly increasing, **never reused**; a failed upload still consumes it |

Override for a rebuild with `--build-name=1.4.0 --build-number=43`; never edit the
generated values in Gradle or `Info.plist`. In a flavored app, the store flavor's
`applicationId` / bundle id is fixed for the lifetime of the listing — changing it
creates a *new* app that existing users never receive.

## Symbols and crash symbolization

An obfuscated release produces stack traces of meaningless symbols. They decode only
against the symbol files produced *by that exact build*:

```bash
flutter symbolize -i crash.txt -d build/symbols/1.4.0+42/app.android-arm64.symbols
```

Keep one directory per `version+build`, uploaded to the same durable store as the
artifact, retained at least as long as the release can still be running on a device.
A rebuilt binary produces different symbols — "just build it again" recovers nothing.

## What a release proves that CI cannot

CI runs debug/JIT code on a clean runner. Only the release pass can prove: R8 and
tree-shaking left reflective plugins working; the merged permission set is what you
intend; the signed artifact installs and *upgrades* over the previous release; first
frame and size fit the budget on real low-end hardware; store-delivered binaries run.
State this honestly rather than claiming a green pipeline means shippable.

## Anti-patterns

- **A version hardcoded in `build.gradle` or `Info.plist`** — diverges from pubspec;
  crash reports name a build that does not exist.
- **Reusing or lowering a build number after a failed upload** — the store rejects
  it, and worse, an accepted lower number can hide a newer build from updates.
- **Committing a keystore, `key.properties`, `.p8`, or a service-account JSON** —
  compromised permanently; scrubbing history does not un-leak it.
- **Building with `--obfuscate` but not archiving `--split-debug-info` output** — the
  release's crashes become permanently unreadable the moment the build dir is wiped.
- **Shipping a build verified only in debug/profile** — R8, shrinking, and stripped
  asserts change behavior; reflective plugin failures appear only in release.
- **Auditing your own `AndroidManifest.xml` instead of the merged one** — the
  permissions users see on the listing come from the merge, not from your file.
- **Declaring "we collect no data" with a crash reporter or ads SDK linked** — a
  false Data Safety / nutrition-label declaration is a takedown risk.
- **A dev menu, seeded fixtures, or `eraseDatabaseOnSchemaChange` reachable in the
  store flavor** — destroys or exposes real user data.
- **Publishing straight to 100%** — with no staged rollout there is no halt, only a
  hotfix that itself takes a review cycle.
- **Changing `applicationId`/bundle id to "fix" a signing problem** — it creates a
  new app; every existing user is stranded on the old one.
- **Uploading an IPA built from a tree that last built for the simulator** — Apple
  rejects it (90087/91169) and thinning the binary cannot fix it; only a clean rebuild can.
- **Trusting the tool that configured the store instead of reading the store back** —
  price, availability, in-app-purchase state and screenshots are all commonly "set" and
  not actually set.
- **Treating a committed screenshot folder as an uploaded screenshot set** — submission
  is blocked per display type, and the message names a device class, not a file.

## Definition of done

- [ ] `version: x.y.z+N` bumped in `pubspec.yaml` only; `N` higher than every number
      ever uploaded; no version hardcoded in platform files.
- [ ] Artifact built `--release` with `--obfuscate --split-debug-info=<per-build dir>`;
      symbols archived off-machine with the artifact before upload.
- [ ] No keystore, `key.properties`, `.p8`, or service-account JSON tracked by git;
      Play App Signing enrolled; upload key held separately.
- [ ] The exact release artifact was installed on real hardware, upgraded over the
      previous released version, force-stopped and relaunched.
- [ ] Merged permission set diffed against the committed expected list; every iOS
      `NS*UsageDescription` present and honest.
- [ ] Data Safety / nutrition labels / `PrivacyInfo.xcprivacy` reconciled with the
      current dependency set; no absolute privacy claim in listing or onboarding copy.
- [ ] Debug affordances proved unreachable in the store flavor by a gate.
- [ ] Size (`--analyze-size`) and cold start (`--trace-startup`) recorded against the
      previous release's numbers; no unexplained regression.
- [ ] Dated design-review sign-off present; commit tagged; notes published.
- [ ] Rollout staged with a written halt criterion and someone watching it.
- [ ] `scripts/check-release-hygiene.sh` passes on the release commit, and
      `scripts/check-ipa-slices.sh` passes on the IPA before it is uploaded.
- [ ] Store-side state read back before submission: price and territory availability,
      in-app purchases ready and attached to the version, screenshots present for every
      required display type, metadata complete, account-holder-only gates done.

## When multi-flavor

Build each flavor with its own `--flavor` and entry point, and keep one symbol
directory per flavor *and* build (`symbols/<flavor>/<x.y.z>+<N>/`). Store flavors
and their `applicationId`s are fixed for the life of the listing; non-store flavors
(dev, QA) must never be uploadable — enforce it in the release script, not in a
person's memory. See `service-boundary-and-native` for the flavor composition roots.

## Related skills

- `ci-pipeline-and-gates` — the gates that must be green before this pass starts, and
  the honest statement of what CI cannot prove.
- `design-review-workflow` — the dated sign-off that is a precondition for step 1.
- `run-migration` — the upgrade-over-previous-release path step 5 exercises.
- `dependency-hygiene` — where a new dependency is audited *before* it changes a
  store declaration here.
- `service-boundary-and-native` — flavors, native seams, and the plugins whose
  manifests get merged.
- `flutter-performance` — the profile-mode measurement discipline behind the budgets.
- `ads-and-iap-monetization` — the entitlement, restore-before-init and preload-or-hide
  rules that decide what an App Review reviewer actually sees, and the ad identifiers the
  release gate checks.

## References

- Flutter — Build and release for Android: https://docs.flutter.dev/deployment/android
- Flutter — Build and release for iOS: https://docs.flutter.dev/deployment/ios
- Flutter — Obfuscating Dart code / `flutter symbolize`: https://docs.flutter.dev/deployment/obfuscate
- Flutter — Measuring your app's size: https://docs.flutter.dev/perf/app-size
- Android — Play App Signing: https://developer.android.com/studio/publish/app-signing
- Android — Merge multiple manifest files: https://developer.android.com/build/manage-manifests
- Google Play — Data safety form: https://support.google.com/googleplay/android-developer/answer/10787469
- Apple — Privacy manifest files: https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
