import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/remote_game_config.dart';
import 'core/l10n/l10n.dart';
import 'core/providers.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'features/daily/daily_controller.dart';
import 'features/meta/game_events_controller.dart';
import 'features/notifications/notifications_controller.dart';
import 'features/settings/settings_controller.dart';
import 'features/settings/theme/custom_theme.dart';
import 'features/wallet/wallet_controller.dart';

/// Messenger above every route (achievement toasts, cross-screen notices).
final rootScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Root widget: theme + locale from settings, go_router, text scaling.
class ChetzApp extends ConsumerWidget {
  const ChetzApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);
    final custom = settings.useCustomTheme && ContrastReport.of(settings.customTheme).isApplicable ? settings.customTheme : null;
    final light = AppTheme.build(
      brightness: Brightness.light,
      highContrast: settings.highContrast,
      uiLang: settings.uiLang,
      custom: custom,
    );
    final dark = AppTheme.build(
      brightness: Brightness.dark,
      highContrast: settings.highContrast,
      uiLang: settings.uiLang,
      custom: custom,
    );

    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: rootScaffoldMessengerKey,
      routerConfig: router,
      theme: light,
      darkTheme: dark,
      // A custom palette decides its own brightness.
      themeMode: custom != null ? (custom.brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light) : settings.themeMode,
      locale: settings.uiLocale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final system = mq.textScaler.scale(1);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(system * settings.textScale)),
          child: _Startup(child: child ?? const SizedBox.shrink()),
        );
      },
    );
  }
}

/// One-time startup side effects after the first frame (session counter, ads
/// consent + init, store init, cloud ledger sync, remote config) and the
/// achievement-unlock toast.
class _Startup extends ConsumerStatefulWidget {
  const _Startup({required this.child});
  final Widget child;

  @override
  ConsumerState<_Startup> createState() => _StartupState();
}

class _StartupState extends ConsumerState<_Startup> with WidgetsBindingObserver {
  static bool _ran = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(refreshTodayProvider.notifier).bump();
      _rescheduleNotifications();
    }
  }

  Future<void> _run() async {
    if (_ran || !mounted) return;
    _ran = true;
    final config = ref.read(appConfigProvider);
    ref.read(settingsProvider.notifier).markSession(ref.read(clockProvider).nowMs);

    final cloud = ref.read(cloudSyncProvider);
    unawaited(ref.read(feedbackControllerProvider).flush());
    final store = ref.read(storeServiceProvider);
    unawaited(store.initialize(appUserId: cloud.userId));

    if (config.adsEnabled) {
      final ads = ref.read(adsServiceProvider);
      await ads.initialize();
      ref.read(settingsProvider.notifier).setAdConsentDone();
      // The first session never shows interstitials (§4.3).
      if (ref.read(settingsProvider).sessionCount > 1) await ads.markFirstSessionOver();
    }

    if (cloud.enabled) {
      unawaited(ref.read(walletProvider.notifier).syncWithCloud());
      // Server-side progression (xp / trophies / season points) wins over the local mirror.
      unawaited(cloud.pullMeta().then((meta) {
        if (meta != null && mounted) ref.read(metaProvider.notifier).applyServerMeta(meta);
      }));
      final remote = await fetchRemoteGameConfig();
      if (remote != null && mounted) ref.read(gameConfigProvider.notifier).applyJson(remote);
    }
    if (mounted) _rescheduleNotifications();
  }

  void _rescheduleNotifications() {
    final settings = ref.read(settingsProvider);
    if (!settings.notificationsDailyReady && !settings.notificationsStreak) return;
    final l10n = AppLocalizations.of(context);
    unawaited(ref.read(notificationsProvider.notifier).reschedule(l10n));
  }

  void _showUnlocks(BuildContext context) {
    final meta = ref.read(metaProvider);
    if (meta.pendingUnlocks.isEmpty) return;
    final l10n = context.l10n;
    final lang = ref.read(settingsProvider).uiLang;
    final messenger = rootScaffoldMessengerKey.currentState;
    for (final a in meta.pendingUnlocks) {
      messenger?.showSnackBar(SnackBar(
        content: Text(l10n.achievementUnlockedToast(a.title(lang), a.rewardCoins)),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(label: l10n.viewAchievements, onPressed: () => ref.read(routerProvider).push(Routes.achievements)),
      ));
    }
    ref.read(metaProvider.notifier).consumeUnlocks();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(metaProvider.select((m) => m.unlockSeq), (prev, next) {
      if (prev != next) WidgetsBinding.instance.addPostFrameCallback((_) => _showUnlocks(context));
    });
    // A completed daily clears today's streak-at-risk reminder.
    ref.listen(dailyHistoryProvider, (prev, next) {
      if (prev != next) _rescheduleNotifications();
    });
    return widget.child;
  }
}
