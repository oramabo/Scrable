import '../../core/config/game_config.dart';

/// Pure frequency-cap rules from docs/GAME_PLAN.md §4.3. The ads service
/// consults it before showing anything; tests exercise it directly.
class AdPolicy {
  const AdPolicy(this.config);

  final GameConfig config;

  /// Interstitials run only when leaving the completion screen.
  bool canShowInterstitial({
    required bool adsFree,
    required bool firstSession,
    required int completedPuzzles,
    required int completionsSinceLastInterstitial,
    required int? lastInterstitialAtMs,
    required int? lastRewardedAtMs,
    required int? lastPurchaseAtMs,
    required int nowMs,
  }) {
    if (adsFree || !config.interstitialEnabled || firstSession) return false;
    if (completedPuzzles < config.interstitialMinCompletedPuzzles) return false;
    if (completionsSinceLastInterstitial < config.interstitialEveryNCompletions) return false;
    if (lastInterstitialAtMs != null && nowMs - lastInterstitialAtMs < config.interstitialMinIntervalSec * 1000) {
      return false;
    }
    if (lastRewardedAtMs != null && nowMs - lastRewardedAtMs < config.quietAfterRewardedSec * 1000) return false;
    if (lastPurchaseAtMs != null && nowMs - lastPurchaseAtMs < config.quietAfterRewardedSec * 1000) return false;
    return true;
  }

  /// Rewarded ads are user-initiated; only the daily cap and cooldown apply.
  bool canShowRewarded({
    required int rewardedToday,
    required int? lastRewardedAtMs,
    required int nowMs,
  }) {
    if (rewardedToday >= config.rewardedAdDailyCap) return false;
    if (lastRewardedAtMs != null && nowMs - lastRewardedAtMs < config.rewardedCooldownSec * 1000) return false;
    return true;
  }
}

/// Persisted counters the policy needs.
class AdState {
  const AdState({
    this.completedPuzzles = 0,
    this.completionsSinceLastInterstitial = 0,
    this.lastInterstitialAtMs,
    this.lastRewardedAtMs,
    this.lastPurchaseAtMs,
    this.rewardedDate,
    this.rewardedToday = 0,
  });

  final int completedPuzzles;
  final int completionsSinceLastInterstitial;
  final int? lastInterstitialAtMs;
  final int? lastRewardedAtMs;
  final int? lastPurchaseAtMs;

  /// Date (`YYYY-MM-DD`) [rewardedToday] refers to.
  final String? rewardedDate;
  final int rewardedToday;

  int rewardedOn(String date) => rewardedDate == date ? rewardedToday : 0;

  AdState puzzleCompleted() =>
      copyWith(completedPuzzles: completedPuzzles + 1, completionsSinceLastInterstitial: completionsSinceLastInterstitial + 1);

  AdState interstitialShown(int nowMs) => copyWith(completionsSinceLastInterstitial: 0, lastInterstitialAtMs: nowMs);

  AdState rewardedShown(int nowMs, String date) =>
      copyWith(lastRewardedAtMs: nowMs, rewardedDate: date, rewardedToday: rewardedOn(date) + 1);

  AdState purchased(int nowMs) => copyWith(lastPurchaseAtMs: nowMs);

  AdState copyWith({
    int? completedPuzzles,
    int? completionsSinceLastInterstitial,
    int? lastInterstitialAtMs,
    int? lastRewardedAtMs,
    int? lastPurchaseAtMs,
    String? rewardedDate,
    int? rewardedToday,
  }) =>
      AdState(
        completedPuzzles: completedPuzzles ?? this.completedPuzzles,
        completionsSinceLastInterstitial: completionsSinceLastInterstitial ?? this.completionsSinceLastInterstitial,
        lastInterstitialAtMs: lastInterstitialAtMs ?? this.lastInterstitialAtMs,
        lastRewardedAtMs: lastRewardedAtMs ?? this.lastRewardedAtMs,
        lastPurchaseAtMs: lastPurchaseAtMs ?? this.lastPurchaseAtMs,
        rewardedDate: rewardedDate ?? this.rewardedDate,
        rewardedToday: rewardedToday ?? this.rewardedToday,
      );

  Map<String, dynamic> toJson() => {
        'completedPuzzles': completedPuzzles,
        'sinceInterstitial': completionsSinceLastInterstitial,
        if (lastInterstitialAtMs != null) 'lastInterstitialAt': lastInterstitialAtMs,
        if (lastRewardedAtMs != null) 'lastRewardedAt': lastRewardedAtMs,
        if (lastPurchaseAtMs != null) 'lastPurchaseAt': lastPurchaseAtMs,
        if (rewardedDate != null) 'rewardedDate': rewardedDate,
        'rewardedToday': rewardedToday,
      };

  static AdState fromJson(Map<String, dynamic> j) => AdState(
        completedPuzzles: (j['completedPuzzles'] as int?) ?? 0,
        completionsSinceLastInterstitial: (j['sinceInterstitial'] as int?) ?? 0,
        lastInterstitialAtMs: j['lastInterstitialAt'] as int?,
        lastRewardedAtMs: j['lastRewardedAt'] as int?,
        lastPurchaseAtMs: j['lastPurchaseAt'] as int?,
        rewardedDate: j['rewardedDate'] as String?,
        rewardedToday: (j['rewardedToday'] as int?) ?? 0,
      );
}
