# Setting up ad units — the console decisions that reach the code

The once-per-app pass between "the code is ready for ads" and "the release gate is green". AdMob is
the worked example because it is the common case; the shape (formats, an irreversible flag, capping,
floors, two kinds of identifier) generalizes to any network.

## Create only the formats the app actually uses

For the model in `SKILL.md` that is two: **Rewarded** for the opt-in earn loop and **Interstitial**
for the capped break. Name them for the placement (`<app>-rewarded-<benefit>`,
`<app>-interstitial-<break>`) — the name is internal and is what you will read in a revenue report
six months from now.

**The formats not to create, and why:**

- **Rewarded interstitial** — the confusable one, and the most consequential mistake on the page. It
  *appears* at a break and rewards sitting through it. That is the opposite of an opt-in earn loop
  where the user taps "watch to earn" and never sees an ad they did not ask for. Picking this format
  quietly breaks the promise rule 2 makes.
- **Banner** — never on the primary work surface (rule 7).
- **App open** — a forced ad on every launch; precisely the ad creep an opt-in model is positioned
  against.
- **Native advanced** — only if a genuine inline ad surface exists in the design. Usually it does not.

## The form fields that matter

- **Partner / third-party bidding: leave unchecked** unless you are actually running third-party
  mediation. It is **irreversible** — checking it locks the unit out of the network's own mediation
  and campaigns permanently. Read the checkbox before clicking it.
- **Reward amount and item are cosmetic in most client-only integrations.** The callback sets a flag
  and the app grants what its own economy says (rule 2); the payload is never read. Set them
  readably, but do not treat them as load-bearing — the app's cap is the real ceiling.
- **Ad pods: off.** Pods chain several ads for one bigger reward. The user is buying one benefit;
  making them sit through three ads for it earns exactly the reviews an opt-in model exists to avoid.
- **Server-side verification: off unless you have a server.** SSV protects rewards of real value
  against fraud. A benefit that is already capped per day, on-device, with nothing to spend it on
  outside the app, has nothing to defend and no server to verify against.
- **Frequency capping: disabled — the app caps.** A console-side cap on an *opt-in* format only
  produces no-fill, and no-fill **hides the earn control** (rule 5), so the user silently loses the
  path for a reason they cannot see. Caps belong next to the rule they protect.
- **eCPM floor: take all prices at launch.** A high floor earns more per impression and fills less,
  and a brand-new app gives the optimizer no history. On a rewarded unit a no-fill does not merely
  cost an impression — it removes the affordance. Take fill now; revisit after a month of real data.

## Two identifiers, two homes, two separators

Mixing these up is a reliable half hour of confusion. The separator tells you which is which:

| Identifier | Separator | Belongs in |
|---|---|---|
| **App** id | `~` | `ios/Runner/Info.plist` → `GADApplicationIdentifier` (and the Android manifest meta-data) |
| **Unit** ids | `/` | a Dart config constant |

The SDK reads the app id from the platform manifest at initialization — it cannot come from Dart, and
**a missing or empty value crashes the app at launch**.

Unit ids are **not secrets**: they are visible in any decompiled app and networks publish their own in
sample code. So make them compile-time constants rather than `--dart-define` flags — that removes a
real failure mode where a release build forgets a define. Keep debug builds on the network's test
ids so day-to-day work never generates invalid traffic against the real account.

## Before the release gate goes green

- `scripts/check-release-ad-ids.sh` passes: no empty ids, and no sample-publisher prefix in a release
  configuration. Shipping sample ids serves "test ad" creatives — earns nothing, reads as broken to a
  reviewer.
- `app-ads.txt` is reachable on the app's public site and carries the publisher line verbatim; the
  network cannot verify it until it is live, and it cannot verify the app until the store listing is
  linked.
- Add a launch-time assertion that a **release** build has non-empty real ids, so a
  misconfiguration throws loudly instead of silently falling back to test creatives.

## Traps worth knowing before you panic

1. **A new account or a new app may sit in review before serving live ads.** Zero fill on the first
   real build looks exactly like a bug and is not. Debug builds are unaffected — they are on test units.
2. **Fill ramps only once the app is live**, the listing is linked, `app-ads.txt` is hosted, and
   payment/tax details are complete. Say so in the reviewer note (`release-and-store-shipping`).
3. **Never reuse another app's unit ids to "get going".** It mis-attributes traffic and revenue and it
   is discovered late.
