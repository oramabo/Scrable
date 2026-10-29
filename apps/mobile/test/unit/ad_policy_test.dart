import 'package:chetz_app/core/config/game_config.dart';
import 'package:chetz_app/features/ads/ad_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = AdPolicy(GameConfig());
  const now = 10 * 60 * 1000; // 10 minutes in

  bool interstitial({
    bool adsFree = false,
    bool firstSession = false,
    int completed = 5,
    int since = 2,
    int? lastInterstitial,
    int? lastRewarded,
    int? lastPurchase,
  }) =>
      policy.canShowInterstitial(
        adsFree: adsFree,
        firstSession: firstSession,
        completedPuzzles: completed,
        completionsSinceLastInterstitial: since,
        lastInterstitialAtMs: lastInterstitial,
        lastRewardedAtMs: lastRewarded,
        lastPurchaseAtMs: lastPurchase,
        nowMs: now,
      );

  group('interstitial caps (GAME_PLAN §4.3)', () {
    test('allowed in the normal case', () => expect(interstitial(), isTrue));
    test('never for premium / remove-ads', () => expect(interstitial(adsFree: true), isFalse));
    test('never in the first session', () => expect(interstitial(firstSession: true), isFalse));
    test('never before the 3rd completed puzzle', () {
      expect(interstitial(completed: 2), isFalse);
      expect(interstitial(completed: 3), isTrue);
    });
    test('max one per 2 completions', () {
      expect(interstitial(since: 1), isFalse);
      expect(interstitial(since: 2), isTrue);
    });
    test('at least 3 minutes apart', () {
      expect(interstitial(lastInterstitial: now - 2 * 60 * 1000), isFalse);
      expect(interstitial(lastInterstitial: now - 3 * 60 * 1000), isTrue);
    });
    test('quiet for 60 s after a rewarded ad or a purchase', () {
      expect(interstitial(lastRewarded: now - 30 * 1000), isFalse);
      expect(interstitial(lastRewarded: now - 61 * 1000), isTrue);
      expect(interstitial(lastPurchase: now - 10 * 1000), isFalse);
    });
    test('kill switch', () {
      const off = AdPolicy(GameConfig(interstitialEnabled: false));
      expect(
        off.canShowInterstitial(
          adsFree: false,
          firstSession: false,
          completedPuzzles: 10,
          completionsSinceLastInterstitial: 5,
          lastInterstitialAtMs: null,
          lastRewardedAtMs: null,
          lastPurchaseAtMs: null,
          nowMs: now,
        ),
        isFalse,
      );
    });
  });

  group('rewarded caps', () {
    test('daily cap of 6 and 3-minute cooldown', () {
      expect(policy.canShowRewarded(rewardedToday: 5, lastRewardedAtMs: null, nowMs: now), isTrue);
      expect(policy.canShowRewarded(rewardedToday: 6, lastRewardedAtMs: null, nowMs: now), isFalse);
      expect(policy.canShowRewarded(rewardedToday: 0, lastRewardedAtMs: now - 100000, nowMs: now), isFalse);
      expect(policy.canShowRewarded(rewardedToday: 0, lastRewardedAtMs: now - 180000, nowMs: now), isTrue);
    });
  });

  group('AdState', () {
    test('counters and per-day reward count', () {
      var s = const AdState().puzzleCompleted().puzzleCompleted();
      expect(s.completedPuzzles, 2);
      expect(s.completionsSinceLastInterstitial, 2);
      s = s.interstitialShown(now);
      expect(s.completionsSinceLastInterstitial, 0);
      expect(s.lastInterstitialAtMs, now);
      s = s.rewardedShown(now, '2026-10-28').rewardedShown(now, '2026-10-28');
      expect(s.rewardedOn('2026-10-28'), 2);
      expect(s.rewardedOn('2026-10-29'), 0);
      final back = AdState.fromJson(s.toJson());
      expect(back.completedPuzzles, 2);
      expect(back.rewardedToday, 2);
      expect(back.rewardedDate, '2026-10-28');
    });
  });
}
