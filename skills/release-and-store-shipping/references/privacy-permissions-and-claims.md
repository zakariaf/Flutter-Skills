# Permissions, store declarations, and the wording of claims

A store declaration is not paperwork — it is an assertion about the code, checked
against the binary, and enforced by takedown. Treat it as a build artifact: it changes
in the same PR as the dependency that changed it.

## The permission set is asserted whole, not audited by eye

Keep a committed list of every permission the app is allowed to ship with, and diff the
**merged** manifest against it in CI. Whole-set assertion (not "no forbidden
permission") is what catches a *newly added* permission from a transitive plugin bump.

```dart
// test/policy/permissions_test.dart — one expectation, whole set, sorted.
test('shipped Android permissions are exactly the declared set', () {
  final merged = File(mergedManifestPath).readAsStringSync();
  final found = RegExp(r'uses-permission android:name="([^"]+)"')
      .allMatches(merged)
      .map((m) => m.group(1)!)
      .toSet();
  expect(
    found,
    {
      'android.permission.POST_NOTIFICATIONS',
      'android.permission.RECEIVE_BOOT_COMPLETED',
    },
    reason: 'a dependency changed the permission set — update the store declaration '
        'in the same change, or strip it with tools:node="remove"',
  );
});
```

The iOS equivalent asserts the exact set of `NS*UsageDescription` keys in `Info.plist`.
Both tests fail *loudly on a dependency bump*, which is exactly when the store
declaration silently becomes wrong.

## Play Data Safety

Declared per data type: collected, shared, whether transmission is encrypted, whether
users can request deletion. Two traps:

- **Crash logs and diagnostics are data collection.** Adding any crash/analytics SDK
  changes the declaration even though "we don't collect anything" still feels true.
- **A dependency collects on your behalf.** The declaration covers what the app and its
  SDKs do, so an ads or attribution SDK's collection is yours to declare.

## App Store privacy labels and `PrivacyInfo.xcprivacy`

- **Nutrition labels** in App Store Connect mirror the Data Safety content.
- **`PrivacyInfo.xcprivacy`** is a bundled privacy manifest declaring tracking, collected
  data types, and **required-reason API** usage (file timestamps, system boot time, disk
  space, active keyboard, `UserDefaults`) with an approved reason code.
- Third-party SDKs on Apple's list must ship their own privacy manifest **and** a valid
  signature — an outdated plugin without one blocks upload, which is a dependency
  problem discovered at release time unless `dependency-hygiene` caught it earlier.

### Read the SDKs' manifests; do not reason about them

For an app whose own code opens no sockets, **100% of collected data is usually some bundled
SDK's**. Each ships a manifest declaring exactly what it collects and why — transcribe that
instead of guessing:

```bash
find ios/Pods -name 'PrivacyInfo.xcprivacy' -print
plutil -p ios/Pods/<SDK>/…/<Framework>.framework/PrivacyInfo.xcprivacy
```

Apple treats the union of all shipped manifests as *inputs*; declaring a **narrower** purpose set
in the questionnaire than an SDK's manifest lists is legitimate and needs no rebuild — you are
stating what *this app* does with a capability the SDK merely supports. Two judgement calls that
recur:

- **Analytics usually applies even with no analytics of your own** — the question covers data used
  by you *or your third-party partners*.
- **"Developer's advertising or marketing" usually does not** — an SDK lists it because the network
  supports it across all publishers, which is not a statement about your app. Revisit the day you
  ship cross-promotion.
- **"Product personalization" only applies if content actually differs per user** — content that is
  identical for everyone is not personalized, however dynamic it is.
- **"Collect" means transmitted off the device.** Data that never leaves local storage is not
  collected, and payment details handled entirely by the store are not collected by you.

### `NSPrivacyTracking` and `NSPrivacyTrackingDomains` must agree — ITMS-91064

In **your app's** manifest, `NSPrivacyTracking = true` obliges you to list at least one domain in
`NSPrivacyTrackingDomains`. `true` with an empty array is **rejected: ITMS-91064, "Invalid tracking
information"**. And listing a domain has a runtime consequence, not just a paperwork one: **iOS
blocks every listed domain whenever tracking authorization is not granted**, killing even the
non-personalized requests you were still allowed to make for those users.

For an app whose own binary performs no tracking, the correct resolution is `NSPrivacyTracking =
false` with `NSPrivacyTrackingDomains` **omitted**. The tracking that actually happens belongs to
the SDK, is declared in *its* manifest, and is disclosed through the App Store Connect
questionnaire and `NSUserTrackingUsageDescription`. Mature ad SDKs ship no tracking key and no
domains for exactly this reason. Keep any accurate **type-level**
`NSPrivacyCollectedDataTypeTracking` flags — those describe data types and are what clear the
tracking-permission submission error.

Keep the questionnaire answers as a committed file so the next release re-declares the same thing
and a diff shows when a dependency bump changed what the app collects.

## Writing claims that stay true

**Banned as absolutes:** "nothing ever leaves your device", "completely private", "we
can't see anything", "100% secure/offline". One crash upload, one share-sheet export,
one map tile, or one future feature makes them false — and the copy usually outlives the
architecture that justified it.

**Write the mechanism instead.** Each sentence must name what is stored, where it lives,
what leaves the device, and on whose action:

> Your records are stored in a database on this device. The app has no network
> permission, so nothing is uploaded. Exports leave the app only when you tap Share, and
> go wherever you send them.

Rules that keep it honest:

- **Every claim must be checkable against the repo.** "No network permission" is a claim
  a permission test proves. "We respect your privacy" proves nothing and says nothing.
- **Onboarding and listing copy are claims too**, not marketing — hold them to the same
  standard as the privacy policy.
- **A translation must not be stronger than the source.** Claims live in ARB like every
  other string (`i18n-rtl-l10n`); flag them for translators so "no data is uploaded"
  does not become "totally anonymous" in another locale.
- **Sharing is a hand-off, not a leak — say so.** Once a user shares an export, its
  privacy is the destination app's, and the copy should not imply otherwise.
- **If the app has accounts, both stores require an in-app account-deletion path**, and
  the deletion claim must match what the code actually deletes.

## When a declaration and the code disagree

Fix the code or fix the declaration in the same change — never ship the gap and never
"declare defensively" (declaring collection you do not do costs real installs and
invites review questions you cannot answer). If a dependency forced the change, that is
a `dependency-hygiene` decision: the honest options are to declare it, to strip it, or
to drop the dependency.
