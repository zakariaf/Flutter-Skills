# App Store Connect: the gates, the configuration, and reading it back

The ritual in `SKILL.md` gets a correct artifact uploaded. This file is about everything
*around* the binary that blocks a submission — and about the fact that none of it can be
trusted from the tool that wrote it. Every trap here cost a real submission.

## The three gates no API can open

An App Store Connect API key automates most of a release. These it cannot touch, and every app
stalls on them at least once:

1. **Creating the app record.** `POST /v1/apps` returns 403 (`apps does not allow CREATE`), and
   `fastlane produce` demands an Apple ID session.
2. **The App Privacy questionnaire.** No public API; the fastlane task that uploads privacy
   details rejects an API key because the endpoint behind it is Apple-ID-session-only.
3. **The Paid Applications Agreement** (legal + banking + tax).

⚠️ **The third one is required even for a free app that has any in-app purchase.** Until it is
*Active*, StoreKit returns **no products** — so the purchase button stays disabled, every
purchase test fails, and nothing anywhere says "agreement". This is the single most common
"why is the unlock broken".

Raise all three with the account holder on **day one**. A release is never "ready" while one is
outstanding, and the final *Submit for Review* click is theirs too.

## Configure, then prove it by querying the store

The repo, the fastlane log, and your memory are all statements about intent. Read the state back:

- **Price and availability are unset on a new app and block submission.** Both halves are
  API-settable — a price schedule with a base territory, and territory availability. Neither has
  a sensible default, and the submission error does not say which is missing.
- **In-app purchases.**
  - ⚠️ `MISSING_METADATA` on an IAP usually means **missing territory availability**, not a
    missing screenshot. An availability query that 404s means none is set; setting it flips the
    product straight to `READY_TO_SUBMIT`.
  - ⚠️ Product identifiers accept alphanumerics, underscores and periods — **no hyphens** — even
    when the bundle id has one.
  - **Attach the IAP to the version** when submitting, or it reviews separately and lags a
    release behind.
  - Add the required review screenshot; a shot of the screen that offers the purchase is enough.
- Endpoint paths for availability have moved between API versions. When one 404s, check the
  current API reference rather than concluding the setting does not exist.

Script the read-back and run it as the last step, not the first.

## Screenshots: capturing is not uploading

A committed `store/screenshots/` folder and an App Store Connect screenshot set are unrelated
facts. Submission is blocked **per display type**, and the message names a device class, not a
file — so a missing tablet set blocks an otherwise finished release.

Apple's required display types and sizes change; check the current specifications page before a
release rather than trusting any table, including this one. At the time of writing a universal
app needs:

| Display type | Ship this size |
|---|---|
| 6.7″ iPhone | **1290 × 2796** |
| 6.5″ iPhone | **1242 × 2688** |
| 13″ iPad | **2064 × 2752** |

⚠️ **Do not ship 1284 × 2778.** `fastlane deliver` maps it *and* 1242 × 2688 into the same 6.5″
slot; the slot's ten-image cap is then hit and the remaining files are **silently skipped**.
⚠️ **A retried upload can append rather than replace**, leaving more images in a slot than the
set contains. So the last step of a screenshot upload is always a query: list what is attached
per display type, compare counts, and delete strays.

**Device family is a decision.** `TARGETED_DEVICE_FAMILY = "1,2"` (universal) makes the iPad set
mandatory *and* renders a phone-shaped layout sparsely on a tablet; `"1"` removes the requirement
entirely.

Capture deterministically — a scripted run against a booted simulator with a standardized status
bar (`xcrun simctl status_bar … override`), sortable filenames per slot — so successive runs
differ only where the UI differs. ⚠️ **A screenshot run leaves the tree built for the simulator**;
`flutter clean` before the release build that follows (see `ios-app-store.md`).

## Metadata

- **The app name must be globally unique across the store.** First choices are frequently taken —
  resolve the name before it is baked into a bundle id, a website, and marketing.
- Subtitle, promo text, description, keywords and categories are API-settable and locale-scoped.
  Promo text can change without a new build, which is the fastest channel for a known issue.
- Shipping five app locales and one store locale wastes the localization; keep the locale list in
  one place.

## The reviewer note

Write it for someone with a fresh account on a device with no history. Anything a reviewer will
legitimately find empty, unavailable, or slow deserves one sentence — most often:

- ad inventory that does not fill until the app is live and the account is verified
  (see `ads-and-iap-monetization`, which also keeps such a control from dead-ending at all),
- content that unlocks on a schedule,
- a purchase that cannot complete until the Paid Applications Agreement is active,
- test credentials, where an account is required.

An unexplained empty state is indistinguishable from a broken feature, and that is a rejection
under Guideline 2.1.

## Pre-submission read-back checklist

Tick each against a fresh query, never from memory:

- [ ] Build **VALID**, export compliance answered, `version:` bumped
- [ ] `scripts/check-ipa-slices.sh` passed before the upload was spent
- [ ] Price **and** territory availability set — verified by reading them back
- [ ] IAP `READY_TO_SUBMIT`, has availability + review screenshot, **attached to the version**
- [ ] Screenshots present **on the server** for every required display type, no strays
- [ ] Metadata complete in every store locale
- [ ] App Privacy published (account holder) and consistent with every bundled SDK's manifest
- [ ] Paid Applications Agreement **Active** if any IAP exists (account holder)
- [ ] Reviewer note covers everything that will look empty; privacy policy URL live
- [ ] Final *Submit for Review* handed to the account holder
