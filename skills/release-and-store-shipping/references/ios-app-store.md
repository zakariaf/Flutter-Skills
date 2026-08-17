# iOS / App Store release mechanics

Everything here assumes the ritual in `SKILL.md`; this file holds the iOS-specific
detail that would bloat it.

## Building the IPA

```bash
flutter build ipa --release \
  --obfuscate --split-debug-info=build/symbols/1.4.0+42 \
  --export-options-plist=ios/ExportOptions.plist
# → build/ios/ipa/*.ipa  (and the archive under build/ios/archive/)
```

`ios/ExportOptions.plist` is committed (it contains no secrets) and pins the export:

```xml
<key>method</key>            <string>app-store-connect</string>
<key>teamID</key>            <string>ABCDE12345</string>
<key>uploadSymbols</key>     <true/>
<key>signingStyle</key>      <string>automatic</string>
```

Older Xcode versions name the method `app-store`; match the toolchain you pin in CI.
Upload with Transporter, Xcode's Organizer, or `xcrun altool --upload-app`. On CI,
authenticate with an **App Store Connect API key** (`.p8` + Key ID + Issuer ID) held in
the secret store — never a committed file, never a personal Apple ID password.

## The simulator-slice rejection — clean first, verify before uploading

⚠️ If the tree was previously built for the **simulator** — which it will have been if
screenshots were just captured — `flutter build ipa` embeds a simulator framework slice and
Apple rejects the upload with **90087** ("unsupported architectures x86_64") or **91169**
("references an unsupported platform in the arm64 slice").

**Thinning the fat binary does not fix it.** The remaining arm64 slice still *targets the
simulator*, because the device slice was never built. Only a clean rebuild works:

```bash
flutter clean && rm -rf ~/Library/Developer/Xcode/DerivedData/Runner-*
flutter build ipa --release --obfuscate --split-debug-info=build/symbols/1.4.0+42 \
  --export-options-plist=ios/ExportOptions.plist
scripts/check-ipa-slices.sh build/ios/ipa/YourApp.ipa   # arm64 only, iOS platform
```

On Apple Silicon the simulator slice is *also* arm64, so the architecture alone proves nothing —
the script reads each Mach-O's build-version load command, which is what actually distinguishes
a device build from a simulator one. Five seconds, against a ten-minute upload-and-ingest round
trip.

Two more upload facts worth knowing before they cost a build:

- **Ingest is asynchronous.** A build that is not visible yet is normal; a build that never
  appears usually means a reused build number (rule 2) — it ingests into nowhere and nothing
  tells you.
- **Deprecation notices are warnings.** A minimum-deployment-target notice (`ITMS-90068`-class)
  comes back on every upload and blocks nothing. Never chase one mid-submission: it costs another
  build, upload and ingest wait for no review benefit. Schedule it as its own change.
- Setting `ITSAppUsesNonExemptEncryption` in `Info.plist` removes the export-compliance step from
  every future upload.

## Two symbol layers — keep both

| Layer | Produced by | Where it goes |
|---|---|---|
| Native (dSYM) | Xcode archive | Uploaded with the build when `uploadSymbols` is true, so App Store Connect symbolicates native frames |
| Dart | `--obfuscate --split-debug-info` | Kept by you; `flutter symbolize -d symbols/<ver>/app.ios-arm64.symbols` |

Apple never sees the Dart symbols. If you discard them, the Dart frames of every crash
report for that release stay unreadable forever.

## Deployment target and toolchain

- The iOS deployment target in the Xcode project must be **at least** the minimum the
  pinned Flutter version supports; raising it drops devices silently, and lowering it
  below Flutter's floor fails at link time or, worse, at launch on an old device.
- App Store submissions require a build made with a recent Xcode/SDK; Apple announces
  these cutoffs with a deadline. Treat the pinned CI Xcode version as a release-blocking
  dependency, not an incidental.
- Bitcode is removed from modern Xcode — do not re-enable it or copy advice that does.

## TestFlight and review

- **Internal testers** (members of your App Store Connect team) get builds without Beta
  App Review — this is the fast smoke-test loop for step 8 of the ritual.
- **External testers** require Beta App Review; budget real time for it.
- App Review rejects on missing or dishonest `NS*UsageDescription` strings, on a login
  flow that offers a third-party sign-in without Sign in with Apple, and on an app that
  creates accounts but offers no in-app **account deletion** path.

## Phased release, and the thing you cannot undo

An App Store release can be set to **phased release** for automatic updates, and paused
mid-phase. What it can never do is *unship*: a build that reached a device stays there
until the user updates. There is no halt-and-roll-back equivalent to Play's halted
rollout — the only remedy is a new build through review (an expedited review request
exists, and it is a favor, not a mechanism). This asymmetry is why step 5 verifies the
real artifact on real hardware before anything is uploaded.

## Info.plist claims

Every `NS*UsageDescription` is a user-facing sentence and a promise. It must:

- exist for every capability the binary can reach (a plugin linked but "not used yet"
  still triggers the requirement),
- say what the app does with the data in plain language, not "required by the app",
- match the store privacy declaration and the onboarding copy — see
  `privacy-permissions-and-claims.md`.

Removing a plugin removes its requirement: delete the stale usage string in the same
change, or you are declaring access you no longer have. Some plugins (notably
`permission_handler`) additionally require compile-time macros in the `Podfile`
`post_install` block to *exclude* permissions you do not use — an unexcluded permission
is compiled in and must then be declared.
