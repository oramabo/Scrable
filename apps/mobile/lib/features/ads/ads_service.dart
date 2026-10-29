import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../core/analytics/analytics.dart';
import '../../core/config/app_config.dart';
import '../../core/config/game_config.dart';
import '../../core/storage/json_store.dart';
import '../../core/util/clock.dart';
import 'ad_policy.dart';

enum RewardedOutcome { rewarded, dismissed, unavailable, capped, disabled }

/// Ad placements (analytics + policy).
abstract final class AdPlacements {
  static const walletTopUp = 'wallet_top_up';
  static const freeLetter = 'free_letter';
  static const completionInterstitial = 'completion_interstitial';
}

/// Everything the UI may ask of the ads layer. The real implementation talks
/// to Google Mobile Ads + UMP; [DisabledAdsService] is used when
/// [AppConfig.adsEnabled] is false; [FakeAdsService] in tests.
abstract class AdsService {
  const AdsService();

  bool get enabled;

  /// Consent (UMP → ATT where applicable) then SDK init. Safe to call once.
  Future<void> initialize();

  /// Whether a privacy-options entry point should be shown in settings.
  Future<bool> privacyOptionsAvailable();
  Future<void> showPrivacyOptions();

  Future<void> loadRewarded(String placement);
  Future<RewardedOutcome> showRewarded(String placement);

  /// Interstitial on the completion screen only, subject to [AdPolicy].
  Future<bool> showInterstitialIfAllowed(String placement, {required bool adsFree});

  /// Counters the policy depends on.
  Future<void> recordPuzzleCompleted();
  Future<void> recordPurchase();
  Future<void> markFirstSessionOver();
}

class DisabledAdsService extends AdsService {
  const DisabledAdsService();
  @override
  bool get enabled => false;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> privacyOptionsAvailable() async => false;
  @override
  Future<void> showPrivacyOptions() async {}
  @override
  Future<void> loadRewarded(String placement) async {}
  @override
  Future<RewardedOutcome> showRewarded(String placement) async => RewardedOutcome.disabled;
  @override
  Future<bool> showInterstitialIfAllowed(String placement, {required bool adsFree}) async => false;
  @override
  Future<void> recordPuzzleCompleted() async {}
  @override
  Future<void> recordPurchase() async {}
  @override
  Future<void> markFirstSessionOver() async {}
}

/// Deterministic stand-in for tests.
class FakeAdsService extends AdsService {
  FakeAdsService({this.rewardedOutcome = RewardedOutcome.rewarded, this.interstitialAllowed = false});

  RewardedOutcome rewardedOutcome;
  bool interstitialAllowed;
  final List<String> rewardedShown = [];
  final List<String> interstitialsShown = [];
  int completions = 0;

  @override
  bool get enabled => true;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> privacyOptionsAvailable() async => true;
  @override
  Future<void> showPrivacyOptions() async {}
  @override
  Future<void> loadRewarded(String placement) async {}
  @override
  Future<RewardedOutcome> showRewarded(String placement) async {
    rewardedShown.add(placement);
    return rewardedOutcome;
  }

  @override
  Future<bool> showInterstitialIfAllowed(String placement, {required bool adsFree}) async {
    if (adsFree || !interstitialAllowed) return false;
    interstitialsShown.add(placement);
    return true;
  }

  @override
  Future<void> recordPuzzleCompleted() async => completions++;
  @override
  Future<void> recordPurchase() async {}
  @override
  Future<void> markFirstSessionOver() async {}
}

/// Google Mobile Ads implementation with the UMP consent flow and the
/// frequency caps of [AdPolicy]. Never shows anything during solving.
class AdMobAdsService extends AdsService {
  AdMobAdsService({
    required this.appConfig,
    required this.gameConfig,
    required this.store,
    required this.clock,
    required this.analytics,
  });

  final AppConfig appConfig;
  final GameConfig gameConfig;
  final JsonStore store;
  final Clock clock;
  final Analytics analytics;

  static const _stateKey = 'ads/state';

  bool _initialized = false;
  bool _canRequestAds = false;
  bool _firstSession = true;
  RewardedAd? _rewarded;
  InterstitialAd? _interstitial;
  Future<void>? _rewardedLoading;
  AdState _state = const AdState();
  bool _stateLoaded = false;

  AdPolicy get _policy => AdPolicy(gameConfig);

  @override
  bool get enabled => appConfig.adsEnabled;

  Future<void> _loadState() async {
    if (_stateLoaded) return;
    _stateLoaded = true;
    final j = await store.read(_stateKey);
    if (j != null) _state = AdState.fromJson(j);
  }

  Future<void> _saveState() => store.write(_stateKey, _state.toJson());

  @override
  Future<void> initialize() async {
    if (!enabled || _initialized) return;
    _initialized = true;
    await _loadState();
    try {
      await _runConsentFlow();
      _canRequestAds = await ConsentInformation.instance.canRequestAds();
      if (_canRequestAds) {
        await MobileAds.instance.initialize();
        unawaited(loadRewarded(AdPlacements.walletTopUp));
      }
    } catch (e) {
      debugPrint('ads init failed: $e');
      _canRequestAds = false;
    }
  }

  /// UMP consent form (GDPR/UK/Swiss where required) → ATT prompt (iOS, shown
  /// by UMP's IDFA message when configured in AdMob) → SDK init.
  Future<void> _runConsentFlow() async {
    final params = ConsentRequestParameters(
      consentDebugSettings: appConfig.umpDebugGeography
          ? ConsentDebugSettings(debugGeography: DebugGeography.debugGeographyEea)
          : null,
    );
    final updated = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      params,
      () => updated.complete(),
      (FormError error) => updated.complete(),
    );
    await updated.future;
    final shown = Completer<void>();
    await ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
      if (!shown.isCompleted) shown.complete();
    });
    await shown.future;
  }

  @override
  Future<bool> privacyOptionsAvailable() async {
    if (!enabled) return false;
    try {
      final status = await ConsentInformation.instance.getPrivacyOptionsRequirementStatus();
      return status == PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> showPrivacyOptions() async {
    if (!enabled) return;
    final done = Completer<void>();
    await ConsentForm.showPrivacyOptionsForm((FormError? error) {
      if (!done.isCompleted) done.complete();
    });
    await done.future;
  }

  @override
  Future<void> loadRewarded(String placement) {
    if (!_canRequestAds || _rewarded != null) return Future.value();
    if (_rewardedLoading != null) return _rewardedLoading!;
    final c = Completer<void>();
    analytics.track(AnalyticsEvents.adRequested, {'placement': placement, 'format': 'rewarded'});
    RewardedAd.load(
      adUnitId: appConfig.admobRewardedUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _rewarded = ad;
          if (!c.isCompleted) c.complete();
        },
        onAdFailedToLoad: (err) {
          debugPrint('rewarded load failed: $err');
          if (!c.isCompleted) c.complete();
        },
      ),
    );
    _rewardedLoading = c.future.whenComplete(() => _rewardedLoading = null);
    return _rewardedLoading!;
  }

  @override
  Future<RewardedOutcome> showRewarded(String placement) async {
    if (!enabled) return RewardedOutcome.disabled;
    if (!_canRequestAds) return RewardedOutcome.unavailable;
    await _loadState();
    final now = clock.nowMs;
    final today = dateKey(clock.now());
    if (!_policy.canShowRewarded(
      rewardedToday: _state.rewardedOn(today),
      lastRewardedAtMs: _state.lastRewardedAtMs,
      nowMs: now,
    )) {
      return RewardedOutcome.capped;
    }
    if (_rewarded == null) {
      await loadRewarded(placement).timeout(const Duration(seconds: 10), onTimeout: () {});
    }
    final ad = _rewarded;
    if (ad == null) return RewardedOutcome.unavailable;
    _rewarded = null;

    var earned = false;
    final dismissed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => analytics.track(AnalyticsEvents.adShown, {'placement': placement}),
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!dismissed.isCompleted) dismissed.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose();
        if (!dismissed.isCompleted) dismissed.complete();
      },
    );
    await ad.show(onUserEarnedReward: (_, reward) {
      earned = true;
      analytics.track(AnalyticsEvents.adRewarded, {'placement': placement, 'amount': reward.amount});
    });
    await dismissed.future;
    _state = _state.rewardedShown(now, today);
    await _saveState();
    unawaited(loadRewarded(placement));
    return earned ? RewardedOutcome.rewarded : RewardedOutcome.dismissed;
  }

  Future<InterstitialAd?> _loadInterstitial(String placement) async {
    if (_interstitial != null) return _interstitial;
    final c = Completer<InterstitialAd?>();
    analytics.track(AnalyticsEvents.adRequested, {'placement': placement, 'format': 'interstitial'});
    await InterstitialAd.load(
      adUnitId: appConfig.admobInterstitialUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) => c.complete(ad),
        onAdFailedToLoad: (err) => c.complete(null),
      ),
    );
    return _interstitial = await c.future.timeout(const Duration(seconds: 8), onTimeout: () => null);
  }

  @override
  Future<bool> showInterstitialIfAllowed(String placement, {required bool adsFree}) async {
    if (!enabled || !_canRequestAds) return false;
    await _loadState();
    final now = clock.nowMs;
    final allowed = _policy.canShowInterstitial(
      adsFree: adsFree,
      firstSession: _firstSession,
      completedPuzzles: _state.completedPuzzles,
      completionsSinceLastInterstitial: _state.completionsSinceLastInterstitial,
      lastInterstitialAtMs: _state.lastInterstitialAtMs,
      lastRewardedAtMs: _state.lastRewardedAtMs,
      lastPurchaseAtMs: _state.lastPurchaseAtMs,
      nowMs: now,
    );
    if (!allowed) return false;
    final ad = await _loadInterstitial(placement);
    if (ad == null) return false;
    _interstitial = null;
    final dismissed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (_) => analytics.track(AnalyticsEvents.adShown, {'placement': placement}),
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!dismissed.isCompleted) dismissed.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose();
        if (!dismissed.isCompleted) dismissed.complete();
      },
    );
    await ad.show();
    await dismissed.future;
    _state = _state.interstitialShown(now);
    await _saveState();
    return true;
  }

  @override
  Future<void> recordPuzzleCompleted() async {
    await _loadState();
    _state = _state.puzzleCompleted();
    await _saveState();
    // Preload for the next completion only once the caps could allow it.
    if (_canRequestAds &&
        _state.completedPuzzles >= gameConfig.interstitialMinCompletedPuzzles &&
        _state.completionsSinceLastInterstitial >= gameConfig.interstitialEveryNCompletions) {
      unawaited(_loadInterstitial(AdPlacements.completionInterstitial));
    }
  }

  @override
  Future<void> recordPurchase() async {
    await _loadState();
    _state = _state.purchased(clock.nowMs);
    await _saveState();
  }

  @override
  Future<void> markFirstSessionOver() async => _firstSession = false;
}
