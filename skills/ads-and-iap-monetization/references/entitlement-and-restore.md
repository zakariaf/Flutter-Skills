# Entitlement, restore, and launch order

The purchased entitlement is the highest-stakes boolean in a monetized app: wrong in one direction
and a paying user still gets ads, wrong in the other and everyone does not. Three rules carry most of
the weight — restore before you initialize, treat the local copy as a cache, and let one derived
provider be the gate.

## Restore before init — the ordering that actually matters

No-op-ing ad calls for an entitled user is **not** enough. By the time a call site checks the gate,
`AdsService.init()` has usually already run at startup, which means a paying user has had:

- the ad SDK started,
- a consent flow resolved,
- a tracking-authorization prompt shown,
- their device identified for advertising.

All of it is exactly what the purchase was meant to prevent, and none of it is undone by a later
no-op. So the startup sequence is:

```dart
Future<void> bootstrap(ProviderContainer container) async {
  final billing = container.read(billingServiceProvider);
  final entitlement = await billing.restore();        // 1. ask the store first

  if (!entitlement.isEntitled) {                      // 2. only then, and only for free users
    final ads = container.read(adsServiceProvider);
    await ads.init();                                 //    consent + tracking prompt live in here
    await ads.preloadRewarded();                      //    so the earn control can appear at all
  }
}
```

**A failed restore resolves to "not entitled" and initializes.** Never withhold ads from every free
user because one network call flaked — that is a revenue outage caused by a defensive default.

The obvious tension: an entitled user launching **offline** also fails the restore, and would get the
SDK started once. That is what the cache is for.

## The local entitlement row is a cache, not proof

Persist the last known entitlement (through the single write path — see `persistence-drift`) and read
it at startup **before** the restore returns, so an offline launch by an owner takes the entitled
branch. Then let the store's answer overwrite it when it arrives.

Be clear about what that row is:

- It is a **cache for offline correctness and first-frame UI**, not authorization.
- The store account remains the authority; a re-verified restore is what grants or revokes.
- Without a receipt-validation backend, a determined user can flip a local flag. That is an accepted
  trade for a one-time unlock on a small app — but never design a *server-backed* benefit on top of a
  local boolean.

Failing to cache at all is the common bug; treating the cache as proof is the dangerous one.

## One derived gate

```dart
// The only entitlement read in the app. Everything — ad call sites, caps, paywall — watches this.
final isEntitledProvider = StreamProvider<bool>(
  (ref) => ref.watch(billingServiceProvider).entitlement.map((e) => e.isEntitled),
);
```

A second read of the same truth somewhere in a widget is a second gate, and the two will disagree
after the next refactor. If a feature needs to know *why* (trial vs purchased vs cached), derive that
as another provider from the same source — never as a parallel subscription.

## The purchase itself

1. `buyNonConsumable()` → the store's purchase stream reports a verified purchase.
2. The repository writes the entitlement in **one committed transaction**.
3. `isEntitledProvider` re-emits because the watched source changed.
4. The paywall closes **because** the gate flipped — not because the button was tapped.

Never dismiss optimistically. A crash between 1 and 2 must leave a state the next launch's restore
repairs, not a "paid but not entitled" ghost the user has to file a ticket about.

Complete a pending purchase exactly once, and always — an unacknowledged purchase is refunded by the
store after a grace period, which reads to the user as the app taking their money and revoking the
feature.

## Restore is a visible control, and a silent launch step

Both. The visible **Restore** button is required by store review for a non-consumable and is the
answer to "I bought this on my old phone". The silent launch restore is what stops most people ever
needing to press it.

## Testing it

The fakes make all of this assertable without a store:

- `FakeBillingService(entitled: true)` + `FakeAdsService` → assert `initCount == 0`. This single test
  is what keeps the restore-before-init ordering true through future refactors.
- `FakeBillingService(restoreThrows: true)` → assert ads **did** initialize (the free-user fallback).
- Entitled + offline (cache primed) → assert `initCount == 0` again.
- Purchase flow → assert the entitlement row is committed before the paywall's gate emits `true`.
