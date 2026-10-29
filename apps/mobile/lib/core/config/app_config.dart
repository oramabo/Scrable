/// Build-time switches for third-party integrations.
///
/// Everything is off by default so the app runs fully offline without
/// google-services files. Turn things on with `--dart-define`, e.g.
/// `flutter run --dart-define=CHETZ_ADS=true --dart-define=CHETZ_CDN=https://cdn.example.com/`.
class AppConfig {
  const AppConfig({
    this.adsEnabled = false,
    this.iapEnabled = false,
    this.firebaseEnabled = false,
    this.cdnBaseUrl = '',
    this.analyticsLogging = true,
    this.admobRewardedUnitId = admobTestRewardedUnitId,
    this.admobInterstitialUnitId = admobTestInterstitialUnitId,
    this.revenueCatApiKey = '',
    this.appVersion = '0.1.0',
    this.umpDebugGeography = false,
  });

  /// Reads `--dart-define` values; falls back to the offline defaults.
  factory AppConfig.fromEnvironment() => const AppConfig(
        adsEnabled: bool.fromEnvironment('CHETZ_ADS'),
        iapEnabled: bool.fromEnvironment('CHETZ_IAP'),
        firebaseEnabled: bool.fromEnvironment('CHETZ_FIREBASE'),
        cdnBaseUrl: String.fromEnvironment('CHETZ_CDN'),
        analyticsLogging: bool.fromEnvironment('CHETZ_ANALYTICS_LOG', defaultValue: true),
        admobRewardedUnitId: String.fromEnvironment('CHETZ_ADMOB_REWARDED', defaultValue: admobTestRewardedUnitId),
        admobInterstitialUnitId:
            String.fromEnvironment('CHETZ_ADMOB_INTERSTITIAL', defaultValue: admobTestInterstitialUnitId),
        revenueCatApiKey: String.fromEnvironment('CHETZ_REVENUECAT_KEY'),
        appVersion: String.fromEnvironment('CHETZ_VERSION', defaultValue: '0.1.0'),
        umpDebugGeography: bool.fromEnvironment('CHETZ_UMP_DEBUG'),
      );

  factory AppConfig.fromJson(Map<String, dynamic> j) => AppConfig(
        adsEnabled: (j['adsEnabled'] as bool?) ?? false,
        iapEnabled: (j['iapEnabled'] as bool?) ?? false,
        firebaseEnabled: (j['firebaseEnabled'] as bool?) ?? false,
        cdnBaseUrl: (j['cdnBaseUrl'] as String?) ?? '',
        analyticsLogging: (j['analyticsLogging'] as bool?) ?? true,
        admobRewardedUnitId: (j['admobRewardedUnitId'] as String?) ?? admobTestRewardedUnitId,
        admobInterstitialUnitId: (j['admobInterstitialUnitId'] as String?) ?? admobTestInterstitialUnitId,
        revenueCatApiKey: (j['revenueCatApiKey'] as String?) ?? '',
        appVersion: (j['appVersion'] as String?) ?? '0.1.0',
        umpDebugGeography: (j['umpDebugGeography'] as bool?) ?? false,
      );

  /// Google's public test ad units (Android). Replace before release.
  static const admobTestRewardedUnitId = 'ca-app-pub-3940256099942544/5224354917';
  static const admobTestInterstitialUnitId = 'ca-app-pub-3940256099942544/1033173712';

  final bool adsEnabled;
  final bool iapEnabled;
  final bool firebaseEnabled;

  /// Base URL of the content CDN (ends with `/`). Empty = offline only.
  final String cdnBaseUrl;
  final bool analyticsLogging;
  final String admobRewardedUnitId;
  final String admobInterstitialUnitId;
  final String revenueCatApiKey;
  final String appVersion;
  final bool umpDebugGeography;

  bool get cdnEnabled => cdnBaseUrl.isNotEmpty;

  AppConfig copyWith({
    bool? adsEnabled,
    bool? iapEnabled,
    bool? firebaseEnabled,
    String? cdnBaseUrl,
    bool? analyticsLogging,
  }) =>
      AppConfig(
        adsEnabled: adsEnabled ?? this.adsEnabled,
        iapEnabled: iapEnabled ?? this.iapEnabled,
        firebaseEnabled: firebaseEnabled ?? this.firebaseEnabled,
        cdnBaseUrl: cdnBaseUrl ?? this.cdnBaseUrl,
        analyticsLogging: analyticsLogging ?? this.analyticsLogging,
        admobRewardedUnitId: admobRewardedUnitId,
        admobInterstitialUnitId: admobInterstitialUnitId,
        revenueCatApiKey: revenueCatApiKey,
        appVersion: appVersion,
        umpDebugGeography: umpDebugGeography,
      );
}
