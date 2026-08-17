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
