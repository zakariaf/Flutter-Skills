---
name: ads-and-iap-monetization
description: >-
  Enforces opt-in, rewarded-first monetization over the service seam — a rewarded view grants
  exactly one benefit and only on a genuine reward outcome (a sealed Rewarded/Dismissed/NoFill),
  earn loops capped per day against an injected Clock, the
  earn control preloaded and hidden unless an ad is loaded so a fresh account never dead-ends on
  "no ads available" (a Guideline 2.1 risk), interstitials only at a natural break under a
  count-and-elapsed cap owned by the service so callers stay dumb, no banner on the primary work
  surface, one non-consumable unlock plus Restore re-checked each launch and committed through
  the single write path before the UI reacts, one derived isEntitled provider as the only gate,
  and the entitlement restored BEFORE the ad SDK initializes so a paying user never starts it,
  resolves consent, or sees a tracking prompt. Use when adding ads, wiring a rewarded earn loop,
  placing an interstitial, building a paywall, gating an entitlement, or setting up ad units.
---

# Ads and IAP monetization

The policy layer over the ads and billing seams: *what* a rewarded view grants, *when* an
interstitial may fire and how often, *how* an entitlement gates both, and *in what order* they
initialize at launch. It assumes the seam already exists — declaring the interface, overriding it per
flavor, and keeping SDK types out of feature code belong to `service-boundary-and-native`.

The model this encodes is **free, opt-in-first**: value is exchanged for attention the user chose to
give, and one non-consumable purchase removes the exchange. It is not the only viable model, but the
rules below are what keep any ad-funded app honest, reviewable, and out of the "feels like adware"
bucket.

## Non-negotiable rules

1. **Every ad and store call goes through an injected interface, never an SDK type in feature code.**
   `AdsService`, `BillingService`; the concrete SDK is wired once at the composition root and faked
   in tests. Mechanism is owned by `service-boundary-and-native` — do not re-derive it here.

2. **A rewarded view is opt-in and grants exactly one concrete benefit.** It fires only from an
   explicit "watch to earn" tap, never automatically, and it hands back **one** unit — a credit, an
   extra attempt, a partial reveal — never the whole outcome the user is working toward. WHY: an
   auto-playing "rewarded" ad is an interstitial wearing a costume, and a grant that finishes the
   task for the user destroys the thing they came for.

3. **Grant only on a genuine reward outcome.** Model the result as a sealed type
   (`Rewarded` / `Dismissed` / `NoFill`) and switch exhaustively; `Dismissed` (closed early) and
   `NoFill` grant nothing and leave state untouched. WHY: a `bool` return collapses "no ad existed"
   into "user declined" and the two need different UI.

4. **Cap the earn loop per day, in the policy layer, against an injected `Clock`.** An uncapped
   watch-to-earn loop lets any user bypass whatever the benefit was rationing, and the ceiling
   belongs next to the rule it protects — not in the ad network console (see
   `references/ad-unit-setup.md` for why a console-side frequency cap actively harms an opt-in
   format). Key the cap to a calendar day derived from `clock.now()`, never `DateTime.now()`.

5. **Never ship an earn control that can dead-end.** A brand-new ad account has near-zero fill, so an
   always-visible "watch to earn" button answers *"no ads available"* every time — poor UX and a
   **Guideline 2.1** rejection risk for a control that looks broken. Preload, expose availability as
   a stream, and show the control **only while an ad is actually loaded** (or a redemption is
   in flight). Whatever the user needs must remain reachable without watching anything.

6. **Interstitials fire only at a natural break, under a two-part cap the service owns.** The only
   eligible moment is a completion or transition boundary the user already expected — never
   mid-task, never during onboarding, never in the first session. Both halves of the cap must pass:
   at most one per N completions **and** at least M seconds since the last one. Put the counting and
   the clock inside `maybeShowInterstitial()`, and return whether it showed, so no caller counts
   anything. WHY: a cap enforced at three call sites is three caps that will disagree.

7. **No banner on the primary work surface.** A banner on the screen where the user is actually doing
   the thing reflows layout, invites mis-taps, and earns the least of any format. A menu or home
   surface is the only defensible placement, and it is optional.

8. **One non-consumable unlock plus Restore, re-checked on every launch.** Sell it once; expose a
   visible **Restore**; silently re-check entitlement at launch so a reinstall or a new device
   re-grants it without a support ticket. Not a subscription for a one-time capability, and not a
   consumable currency sold for cash where an opt-in rewarded path already exists.

9. **One derived `isEntitled` provider is the only gate.** Everything — every ad call site, every cap,
   every paywall affordance — reads it. Nothing branches on the raw entitlement stream. WHY: a second
   read of the same truth is a second gate that will drift out of agreement with the first.

10. **Restore the entitlement BEFORE initializing the ad SDK.** No-op-ing ad calls is not enough: if
    `AdsService.init()` already ran, a paying user has had the SDK started, consent resolved, a
    tracking prompt shown, and their device identified — everything they paid to avoid. Await the
    restore first and initialize ads **only** for a confirmed non-entitled user. A store or network
    failure resolves to *not entitled* and initializes — never withhold ads from every free user
    because one call flaked — so cache the last known entitlement locally to keep an offline launch
    correct for an owner. See `references/entitlement-and-restore.md`.

11. **A purchase persists through the single write path before the UI reacts.** One committed
    transaction through the repository, then the UI updates because `isEntitled` re-emits — never an
    optimistic dismiss. WHY: a crash mid-flow must never leave a "paid but not entitled" ghost.
    Write-path mechanics are owned by `persistence-drift`.

12. **Never paid-upfront *and* ad-supported.** Pick one. Charging for the app and then monetizing the
    buyer's attention is the pattern users punish in reviews, and it makes the paywall unarguable.

13. **Ad unit identifiers are configuration, not secrets — but sample ids must never ship.** They are
    visible in any decompiled app, so compile-time constants beat `--dart-define` (a release build
    cannot forget a constant). Gate the release on it: `scripts/check-release-ad-ids.sh` fails a
    release that still carries the network's well-known sample ids, which serve "test ad" creatives
    and read as broken to a reviewer.

## The earn loop, end to end

```dart
// Policy layer: depends on the interfaces and the entitlement gate — never on an SDK.
sealed class RewardOutcome { const RewardOutcome(); }
final class Rewarded  extends RewardOutcome { const Rewarded(); }
final class Dismissed extends RewardOutcome { const Dismissed(); }   // closed early
final class NoFill    extends RewardOutcome { const NoFill(); }      // no ad existed

class CreditEconomy extends Notifier<CreditState> {
  static const int freeCreditsPerDay = 1;   // the allowance the design assumes
  static const int maxEarnedPerDay = 3;     // the integrity ceiling (rule 4)

  @override
  CreditState build() => const CreditState();

  /// Opt-in earn path. Grants ONLY on `Rewarded`, and only under the daily cap.
  Future<Result<Credit, MonetizationFailure>> watchToEarn() async {
    if (ref.read(isEntitledProvider).valueOrNull ?? false) return _grant(); // no ad at all
    if (state.earnedToday(ref.read(clockProvider)) >= maxEarnedPerDay) {
      return const Err(EarnCapReached());
    }
    return switch (await ref.read(adsServiceProvider).showRewarded()) {
      Rewarded()  => _grant(),
      Dismissed() => const Err(RewardNotEarned()),   // distinct: the user closed it
      NoFill()    => const Err(NoAdAvailable()),     // distinct: nothing to show
    };
  }
}
```

The control that calls it is bound to availability, so it is never a dead end (rule 5):

```dart
// Shown only while an ad is genuinely loaded; the free path stays reachable regardless.
final rewardedReadyProvider =
    StreamProvider<bool>((ref) => ref.watch(adsServiceProvider).rewardedAvailability);

if (ref.watch(rewardedReadyProvider).valueOrNull ?? false)
  const WatchToEarnButton(),
```

And the interstitial call site counts nothing (rule 6):

```dart
Future<void> onTaskCompleted(WidgetRef ref) async {
  if (ref.read(isEntitledProvider).valueOrNull ?? false) return;   // rule 9
  await ref.read(adsServiceProvider).maybeShowInterstitial();      // owns both cap halves
}
```

## Launch order

```dart
// Entitlement first, ads only if the user is not entitled (rule 10).
// Startup-sequence mechanics are owned by `app-startup-and-bootstrap`.
final entitlement = await ref.read(billingServiceProvider).restore();   // failure ⇒ not entitled
if (!entitlement.isEntitled) {
  await ref.read(adsServiceProvider).init();      // consent / tracking prompt happens in here
  await ref.read(adsServiceProvider).preloadRewarded();
}
```

Cover it with a test asserting the fake ads service records `initCount == 0` for an entitled user —
that single assertion is what keeps rule 10 true through future refactors.

## Anti-patterns

- **Auto-playing a "rewarded" ad**, or granting on `Dismissed`/`NoFill` — it is opt-in, and the grant
  is for a completed view only.
- **A `bool` rewarded result** — "no fill" and "user closed it" need different UI; use the sealed type.
- **An uncapped earn loop**, or a cap enforced in the ad console instead of the app — the console cap
  produces no-fill, and no-fill *hides the control* (rule 5), so the user loses the path with no
  visible reason.
- **An always-visible earn button on a new account** — permanent "no ads available"; Guideline 2.1.
- **A grant that completes the user's task** — reveal a step, never the destination.
- **Interstitials mid-task, on first launch, during onboarding**, or a caller that counts completions
  or reads a clock — the break is the only trigger and the cap lives in the service.
- **A banner on the working surface** — the one placement that is never worth it.
- **Widgets reading the raw entitlement stream** — everything reads the one derived gate.
- **No-op-ing ads for an entitled user without moving the restore before `init()`** — they still got
  the SDK, the consent flow, and the tracking prompt.
- **Blocking ads for everyone when a restore call fails** — failure means *not entitled*; cache the
  last known state so an offline owner stays correct.
- **Dismissing the paywall before the entitlement is durably written** — persist, then let the gate re-emit.
- **Skipping the launch restore** — reinstalls and device swaps become support tickets.
- **Paid-upfront plus ads, or a subscription for a one-time unlock.**
- **Shipping the network's sample ad ids** — "test ad" creatives earn nothing and look broken on review.

## Definition of done

- [ ] Ads and billing are reached only through injected interfaces; no SDK type appears in feature code.
- [ ] Rewarded is opt-in, grants exactly one benefit, and grants **only** on `Rewarded`; the outcome
      type is sealed and switched exhaustively.
- [ ] The earn loop is capped per calendar day against the injected `Clock`; the cap lives in the app.
- [ ] The earn control is preloaded and hidden unless an ad is loaded; the task stays completable
      without watching anything.
- [ ] Interstitials fire only at a break; `maybeShowInterstitial()` owns the count **and** elapsed
      caps and reports whether it showed; no caller counts.
- [ ] No banner on any primary work surface.
- [ ] One non-consumable + a visible Restore; entitlement silently re-checked at every launch.
- [ ] `isEntitled` is the single gate; no feature branches on the raw entitlement stream.
- [ ] Restore runs **before** `AdsService.init()`; a test asserts the fake's `initCount == 0` for an
      entitled user; a failed restore falls back to *not entitled* with a local cache for offline.
- [ ] The purchase commits through the single write path before any UI reacts.
- [ ] Release ad ids verified by `scripts/check-release-ad-ids.sh`; no sample ids in a release build.
- [ ] Tests drive: watch → granted, cap reached → refused, no-fill → control hidden, purchase →
      ads gone and caps lifted, against fakes.

## Related skills

- See `service-boundary-and-native` for declaring `AdsService`/`BillingService`, the per-flavor live
  implementation, and the fakes these tests use.
- See `app-startup-and-bootstrap` for where the restore-then-init sequence belongs in `main()`.
- See `state-management-riverpod` for the derived-gate provider and `persistence-drift` for the
  single write path the purchase commits through.
- See `error-handling-typed-results` for the `Result`/`Failure` arms returned above.
- See `release-and-store-shipping` for the privacy declaration the ad SDK drives and the reviewer note that
  explains empty ad inventory during review.

## References

- App Store Review Guidelines (2.1 App Completeness, 3.1 Payments): https://developer.apple.com/app-store/review/guidelines/
- `in_app_purchase` (StoreKit / Play Billing): https://pub.dev/packages/in_app_purchase
- Flutter — in-app purchases cookbook: https://docs.flutter.dev/cookbook/plugins/in-app-purchases
- `google_mobile_ads`: https://pub.dev/packages/google_mobile_ads
- AdMob rewarded ads (Flutter): https://developers.google.com/admob/flutter/rewarded
- User Messaging Platform / consent: https://developers.google.com/admob/flutter/privacy
- App Tracking Transparency: https://developer.apple.com/documentation/apptrackingtransparency
