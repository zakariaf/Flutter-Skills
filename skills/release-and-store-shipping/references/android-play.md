# Android / Google Play release mechanics

Everything here assumes the ritual in `SKILL.md`; this file holds the Android-specific
detail that would bloat it.

## Signing without secrets in the repo

`android/key.properties` is **gitignored** and generated from a secret store at build
time; `build.gradle(.kts)` reads it and fails loudly when it is absent rather than
falling back to the debug key.

```kotlin
// android/app/build.gradle.kts
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    require(f.exists()) { "key.properties missing — release builds must not fall back to debug signing" }
    f.inputStream().use { load(it) }
}

android {
    signingConfigs {
        create("release") {
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
```

The Flutter template ships `signingConfig = signingConfigs.getByName("debug")` in the
release build type so `flutter build` works out of the box. **Shipping that is the
single most common Android release defect** — a debug-signed artifact is rejected by
Play, and if it ever reached a device it could never be updated by a real build.

## Two different obfuscation mappings — keep both straight

| Layer | Produced by | Artifact | Where it goes |
|---|---|---|---|
| Java/Kotlin (R8) | Gradle release build | `build/app/outputs/mapping/release/mapping.txt` | Uploaded with the bundle so Play deobfuscates native-side traces |
| Dart | `--obfuscate --split-debug-info` | `symbols/<x.y.z>+<N>/app.android-*.symbols` | **Never** uploaded to Play — you keep it, and `flutter symbolize` uses it |

Losing the Dart symbols loses the Dart half of every stack trace for that release,
which is where your own code lives.

## R8, shrinking, and reflective plugins

R8 runs for release builds. The failure it produces is not a build error — it is a
runtime `ClassNotFoundException`/`NoSuchMethodError` in the shipped app, from a plugin
that looks a class up by name. Fix it with a targeted `-keep` in
`android/app/proguard-rules.pro` (never by disabling shrinking wholesale), and prove
it by running the release artifact — which is rule 6 in `SKILL.md`.

## Building and installing the real artifact

```bash
flutter build appbundle --release \
  --obfuscate --split-debug-info=build/symbols/1.4.0+42
# → build/app/outputs/bundle/release/app-release.aab
```

An `.aab` is not installable directly. Verify it as the store will serve it:

- **Play internal app sharing** — upload, get a link, install on the device. Closest to
  the real delivery path (Play re-signs with the app signing key).
- **`bundletool build-apks --connected-device`** then `install-apks` — offline, proves
  the split APKs Play would generate for that device.

Installing an `.apk` built separately proves nothing about the bundle you upload.

## Distributing an APK (outside Play)

```bash
flutter build apk --release --split-per-abi \
  --obfuscate --split-debug-info=build/symbols/1.4.0+42
```

A universal (non-split) APK carries every ABI and is often twice the size; only build
one when a store or sideload target requires a single file.

## Version code ceiling and target API

- `versionCode` is a positive integer with a hard Play ceiling (2,100,000,000). Schemes
  that encode dates or version parts into it hit the ceiling or lose monotonicity —
  a plain incrementing integer from `+N` is the durable choice.
- Play enforces a **rolling `targetSdk` requirement**: new apps and updates must target
  within roughly one year of the latest major Android release. This is a hard upload
  rejection with a deadline, not a warning — check `targetSdk` when planning a release,
  not when the upload fails.

## Tracks and staged rollout

internal (fast, small tester list, no review wait) → closed (real tester cohort) →
open/production. Production goes out at a **staged percentage**; a Play rollout can be
**halted**, which is the entire reason to stage it. Decide the halt criterion (e.g. a
crash-free-sessions floor over the first N hours) before the rollout starts, and put it
in the release notes for whoever is watching.

## Auditing the merged manifest

Plugins inject permissions and features through manifest merging, so your source file
is not the truth:

```bash
flutter build appbundle --release   # produces the merge outputs
# blame report — shows WHICH dependency contributed each node:
#   build/app/outputs/logs/manifest-merger-blame-report.txt
# merged result (exact path varies by AGP version):
#   build/app/intermediates/merged_manifests/<variant>/AndroidManifest.xml
```

Strip an inherited permission you do not want, with the `tools` namespace declared on
the root element:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
          xmlns:tools="http://schemas.android.com/tools">
    <uses-permission android:name="android.permission.INTERNET" tools:node="remove" />
</manifest>
```

Then diff the merged permission set against a committed expected list so a dependency
bump can never silently add a permission to your store listing. Note that removing
`INTERNET` is a real, testable claim for an offline app — an accidental network call
then fails at runtime rather than shipping quietly.
