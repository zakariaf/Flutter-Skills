// Demonstrates the opt-in earn loop end to end: a sealed reward outcome granted only on
// `Rewarded`, a per-calendar-day cap read from an injected Clock, one derived entitlement
// gate that lifts the cap and no-ops every ad, an availability-bound control that can never
// dead-end, and an interstitial call site that counts nothing.
//
// Self-contained on purpose. In a real app the service interfaces live in lib/services/
// (see `service-boundary-and-native`) and Result/Failure come from
// `error-handling-typed-results`.

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Typed results ────────────────────────────────────────────────────────────
sealed class Result<T, F> {
  const Result();
}

final class Ok<T, F> extends Result<T, F> {
  const Ok(this.value);
  final T value;
}

final class Err<T, F> extends Result<T, F> {
  const Err(this.failure);
  final F failure;
}

sealed class MonetizationFailure {
  const MonetizationFailure();
}

/// The user hit today's earn ceiling — a design rule, not an error.
final class EarnCapReached extends MonetizationFailure {
  const EarnCapReached();
}

/// The ad was closed before the reward threshold. The user declined; say so.
final class RewardNotEarned extends MonetizationFailure {
  const RewardNotEarned();
}

/// No ad existed to show. Distinct from declining — the control should hide.
final class NoAdAvailable extends MonetizationFailure {
  const NoAdAvailable();
}

// ── The seams (declared here only so this file stands alone) ─────────────────
/// The outcome of a rewarded presentation. Sealed so `Dismissed` and `NoFill`
/// can never collapse into one `false` that the UI cannot explain.
sealed class RewardOutcome {
  const RewardOutcome();
}

final class Rewarded extends RewardOutcome {
  const Rewarded();
}

final class Dismissed extends RewardOutcome {
  const Dismissed();
}

final class NoFill extends RewardOutcome {
  const NoFill();
}

abstract interface class AdsService {
  Future<void> init();
  Future<void> preloadRewarded();

  /// Emits whether a rewarded ad is loaded right now.
  Stream<bool> get rewardedAvailability;

  Future<RewardOutcome> showRewarded();

  /// Owns BOTH cap halves (one per N completions AND >= M seconds apart) and
  /// reports whether it actually showed, so no caller ever counts or times.
  Future<bool> maybeShowInterstitial();
}

abstract interface class BillingService {
  Stream<Entitlement> get entitlement;
  Future<Entitlement> restore();
  Future<Result<Entitlement, MonetizationFailure>> buyUnlock();
}

@immutable
class Entitlement {
  const Entitlement({required this.isEntitled});
  final bool isEntitled;
}

final adsServiceProvider = Provider<AdsService>(
  (ref) => throw UnimplementedError('override in main_<flavor>.dart'),
);
final billingServiceProvider = Provider<BillingService>(
  (ref) => throw UnimplementedError('override in main_<flavor>.dart'),
);

/// Injected time. Never `DateTime.now()` — tests pin this with `Clock.fixed(...)`.
final clockProvider = Provider<Clock>((ref) => const Clock());

// ── The single entitlement gate ──────────────────────────────────────────────
/// The ONLY entitlement read in the app. A second read is a second gate that
/// will eventually disagree with this one.
final isEntitledProvider = StreamProvider<bool>(
  (ref) => ref.watch(billingServiceProvider).entitlement.map((e) => e.isEntitled),
);

// ── The economy ──────────────────────────────────────────────────────────────
@immutable
class CreditState {
  const CreditState({this.credits = 0, this.earnedToday = 0, this.day});

  final int credits;
  final int earnedToday;

  /// Local calendar day the counters belong to; null before the first earn.
  final DateTime? day;

  CreditState copyWith({int? credits, int? earnedToday, DateTime? day}) => CreditState(
        credits: credits ?? this.credits,
        earnedToday: earnedToday ?? this.earnedToday,
        day: day ?? this.day,
      );
}

DateTime _dayKey(DateTime t) => DateTime(t.year, t.month, t.day);

class CreditEconomy extends Notifier<CreditState> {
  /// The integrity ceiling: an uncapped watch-to-earn loop lets any user bypass
  /// whatever the credit was rationing. It lives here, in the app — never as a
  /// frequency cap in the ad console (that only produces no-fill, which hides
  /// the control and leaves the user with no visible reason).
  static const int maxEarnedPerDay = 3;

  @override
  CreditState build() => const CreditState();

  bool get _entitled => ref.read(isEntitledProvider).valueOrNull ?? false;

  int _earnedOn(DateTime day) => state.day == day ? state.earnedToday : 0;

  /// The opt-in earn path. Called ONLY from an explicit "watch to earn" tap —
  /// a rewarded ad that plays by itself is an interstitial wearing a costume.
  Future<Result<int, MonetizationFailure>> watchToEarn() async {
    final today = _dayKey(ref.read(clockProvider).now());

    // Entitled users skip the ad entirely and are not capped (the single gate).
    if (_entitled) return Ok(_grant(today));

    if (_earnedOn(today) >= maxEarnedPerDay) return const Err(EarnCapReached());

    // Exhaustive: closing early and no-fill are different facts with different UI.
    return switch (await ref.read(adsServiceProvider).showRewarded()) {
      Rewarded() => Ok(_grant(today)),
      Dismissed() => const Err(RewardNotEarned()),
      NoFill() => const Err(NoAdAvailable()),
    };
  }

  int _grant(DateTime today) {
    state = state.copyWith(
      credits: state.credits + 1,
      earnedToday: _earnedOn(today) + 1,
      day: today,
    );
    return state.credits;
  }
}

final creditEconomyProvider =
    NotifierProvider<CreditEconomy, CreditState>(CreditEconomy.new);

/// True only while an ad is genuinely loaded, so the earn control is never a
/// dead end on a fresh account with no fill (a Guideline 2.1 rejection risk).
final rewardedReadyProvider =
    StreamProvider<bool>((ref) => ref.watch(adsServiceProvider).rewardedAvailability);

// ── Call sites ───────────────────────────────────────────────────────────────
class EarnCreditControl extends ConsumerWidget {
  const EarnCreditControl({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entitled = ref.watch(isEntitledProvider).valueOrNull ?? false;
    final adReady = ref.watch(rewardedReadyProvider).valueOrNull ?? false;

    // Entitled users are granted instantly; free users see the control only
    // while an ad exists. Whatever the user actually needs stays reachable
    // either way — nothing is gated behind watching an ad.
    if (!entitled && !adReady) return const SizedBox.shrink();

    return FilledButton(
      onPressed: () => ref.read(creditEconomyProvider.notifier).watchToEarn(),
      child: Text(entitled ? 'Add a credit' : 'Watch to earn a credit'),
    );
  }
}

/// The break — the only place an interstitial may fire. The caller counts
/// nothing and reads no clock; both cap halves live inside the service.
Future<void> onTaskCompleted(WidgetRef ref) async {
  if (ref.read(isEntitledProvider).valueOrNull ?? false) return;
  await ref.read(adsServiceProvider).maybeShowInterstitial();
}

/// Startup: ask the store FIRST, and start the ad SDK only for a user who is
/// confirmed not entitled — otherwise a paying user still gets the SDK started,
/// consent resolved and a tracking prompt shown. A failed restore resolves to
/// "not entitled" and initializes; the locally cached entitlement is what keeps
/// an offline launch by an owner correct.
Future<void> bootstrapMonetization(ProviderContainer container) async {
  final entitlement = await container.read(billingServiceProvider).restore();
  if (entitlement.isEntitled) return;

  final ads = container.read(adsServiceProvider);
  await ads.init();
  await ads.preloadRewarded();
}
