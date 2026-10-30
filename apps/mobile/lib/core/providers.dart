import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/account/account_service.dart';
import '../features/ads/ads_service.dart';
import '../features/daily/daily_history.dart';
import '../features/feedback/feedback_service.dart';
import '../features/feedback/review_service.dart';
import '../features/leaderboard/leaderboard_service.dart';
import '../features/meta/meta_state.dart';
import '../features/puzzle/data/progress_repository.dart';
import '../features/settings/settings_model.dart';
import '../features/settings/settings_repository.dart';
import '../features/store/store_service.dart';
import '../features/sync/cloud_sync.dart';
import '../features/wallet/ledger.dart';
import 'analytics/analytics.dart';
import 'config/app_config.dart';
import 'config/game_config.dart';
import 'content/clue_image_store.dart';
import 'content/content_repository.dart';
import 'content/content_source.dart';
import 'storage/json_store.dart';
import 'util/clock.dart';
import 'util/feedback.dart';

/// Everything loaded before the first frame so theme, locale and balances
/// render synchronously.
class AppBootstrap {
  const AppBootstrap({
    required this.settings,
    required this.ledger,
    required this.dailyHistory,
    required this.summaries,
    this.meta = const MetaState(),
    this.cloudSync = const DisabledCloudSync(),
  });

  final AppSettings settings;
  final Ledger ledger;
  final DailyHistory dailyHistory;
  final Map<String, ProgressSummary> summaries;
  final MetaState meta;
  final CloudSync cloudSync;

  static Future<AppBootstrap> load({
    required JsonStore store,
    required GameConfig gameConfig,
    required Clock clock,
    CloudSync cloudSync = const DisabledCloudSync(),
  }) async {
    final settings = await JsonSettingsRepository(store).load();
    final ledger = await JsonWalletRepository(store).load() ??
        Ledger.initial(startingWallet: gameConfig.startingWallet, now: clock.nowMs);
    final history = await JsonDailyRepository(store).load();
    final summaries = await JsonProgressRepository(store).summaries();
    final meta = await JsonMetaRepository(store).load();
    return AppBootstrap(
      settings: settings,
      ledger: ledger,
      dailyHistory: history,
      summaries: summaries,
      meta: meta,
      cloudSync: cloudSync,
    );
  }
}

/// Overridden in main / tests.
final appConfigProvider = Provider<AppConfig>((ref) => const AppConfig());

/// Overridden in main / tests.
final jsonStoreProvider = Provider<JsonStore>((ref) => MemoryJsonStore());

/// Overridden in main / tests with the loaded values.
final bootstrapProvider = Provider<AppBootstrap>(
  (ref) => throw UnimplementedError('bootstrapProvider must be overridden'),
);

final clockProvider = Provider<Clock>((ref) => const SystemClock());

/// Periodic UI timers (solving timer, mission countdowns). Tests override it
/// to `false` so no timer is left pending.
final uiTimersEnabledProvider = Provider<bool>((ref) => true);

/// Directory for downloaded content (images). Null = memory only (tests).
final cacheDirectoryProvider = Provider<Directory?>((ref) => null);

class GameConfigController extends Notifier<GameConfig> {
  @override
  GameConfig build() => const GameConfig();

  /// Apply a Remote Config / JSON override on top of the defaults.
  void applyJson(Map<String, dynamic> json) => state = GameConfig.fromJson(json);
  void set(GameConfig config) => state = config;
}

final gameConfigProvider = NotifierProvider<GameConfigController, GameConfig>(GameConfigController.new);

final analyticsProvider = Provider<Analytics>(
  (ref) => ref.watch(appConfigProvider).analyticsLogging ? LoggingAnalytics() : const NoopAnalytics(),
);

final settingsRepositoryProvider =
    Provider<SettingsRepository>((ref) => JsonSettingsRepository(ref.watch(jsonStoreProvider)));
final walletRepositoryProvider = Provider<WalletRepository>((ref) => JsonWalletRepository(ref.watch(jsonStoreProvider)));
final progressRepositoryProvider =
    Provider<ProgressRepository>((ref) => JsonProgressRepository(ref.watch(jsonStoreProvider)));
final dailyRepositoryProvider = Provider<DailyRepository>((ref) => JsonDailyRepository(ref.watch(jsonStoreProvider)));
final metaRepositoryProvider = Provider<MetaRepository>((ref) => JsonMetaRepository(ref.watch(jsonStoreProvider)));

final adsServiceProvider = Provider<AdsService>((ref) {
  final config = ref.watch(appConfigProvider);
  if (!config.adsEnabled) return const DisabledAdsService();
  return AdMobAdsService(
    appConfig: config,
    gameConfig: ref.watch(gameConfigProvider),
    store: ref.watch(jsonStoreProvider),
    clock: ref.watch(clockProvider),
    analytics: ref.watch(analyticsProvider),
  );
});

final storeServiceProvider = Provider<StoreService>((ref) {
  final config = ref.watch(appConfigProvider);
  if (!config.iapEnabled) return const DisabledStoreService();
  return RevenueCatStoreService(appConfig: config, analytics: ref.watch(analyticsProvider));
});

final cloudSyncProvider = Provider<CloudSync>((ref) => ref.watch(bootstrapProvider).cloudSync);

final soundsProvider = Provider<Sounds>((ref) => const NoSounds());

/// Content repository per puzzle language. Bundled assets first, CDN second.
final contentRepositoryProvider = Provider.family<ContentRepository, String>((ref, lang) {
  final config = ref.watch(appConfigProvider);
  return ContentRepository(
    lang: lang,
    bundled: const AssetContentSource(),
    cdn: config.cdnEnabled ? HttpContentSource(config.cdnBaseUrl) : null,
    cache: ref.watch(jsonStoreProvider),
  );
});

/// Whether a puzzle language has any content (bundled or via manifest).
final languageHasContentProvider = FutureProvider.family<bool, String>(
  (ref, lang) => ref.watch(contentRepositoryProvider(lang)).hasContent(),
);

/// Picture-clue images per puzzle language (bundled → file cache → CDN).
final clueImageStoreProvider = Provider.family<ClueImageStore, String>((ref, lang) {
  final repo = ref.watch(contentRepositoryProvider(lang));
  final store = ClueImageStore(bundled: repo.bundled, cdn: repo.cdn, cacheDir: ref.watch(cacheDirectoryProvider));
  ref.onDispose(store.dispose);
  return store;
});

/// Player feedback; Firestore only when cloud sync is on, otherwise reports
/// wait in the on-device outbox.
final feedbackServiceProvider = Provider<FeedbackService>((ref) {
  final cloud = ref.watch(cloudSyncProvider);
  if (!cloud.enabled) return const DisabledFeedbackService();
  return FirestoreFeedbackService(uid: cloud.userId);
});

final feedbackControllerProvider =
    Provider<FeedbackController>((ref) => FeedbackController(ref.watch(feedbackServiceProvider), ref.watch(jsonStoreProvider)));

/// Google / Apple sign-in and usernames; needs cloud sync (Firebase) on.
final accountServiceProvider = Provider<AccountService>((ref) {
  final cloud = ref.watch(cloudSyncProvider);
  if (!cloud.enabled) return const DisabledAccountService();
  final clientId = ref.watch(appConfigProvider).googleServerClientId;
  return FirebaseAccountService(googleServerClientId: clientId.isEmpty ? null : clientId);
});

/// The stores' own rating dialog (Play In-App Review / StoreKit).
final reviewServiceProvider = Provider<ReviewService>((ref) => InAppReviewService(appStoreId: ref.watch(appConfigProvider).appStoreId));

/// Hard-daily leaderboard; Firestore only when cloud sync is on.
final leaderboardServiceProvider = Provider<LeaderboardService>((ref) {
  final cloud = ref.watch(cloudSyncProvider);
  if (!cloud.enabled) return const DisabledLeaderboardService();
  return FirestoreLeaderboardService(uid: cloud.userId);
});
