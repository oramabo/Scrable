import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/remote_game_config.dart';
import 'core/l10n/l10n.dart';
import 'core/providers.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'features/daily/daily_controller.dart';
import 'features/settings/settings_controller.dart';
import 'features/wallet/wallet_controller.dart';

/// Root widget: theme + locale from settings, go_router, text scaling.
class ChetzApp extends ConsumerWidget {
  const ChetzApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);
    final light = AppTheme.build(brightness: Brightness.light, highContrast: settings.highContrast, uiLang: settings.uiLang);
    final dark = AppTheme.build(brightness: Brightness.dark, highContrast: settings.highContrast, uiLang: settings.uiLang);

    return MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: light,
      darkTheme: dark,
      themeMode: settings.themeMode,
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

/// One-time startup side effects after the first frame: session counter,
/// ads consent + init, store init, cloud ledger sync, remote config.
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
    if (state == AppLifecycleState.resumed) ref.read(refreshTodayProvider.notifier).bump();
  }

  Future<void> _run() async {
    if (_ran || !mounted) return;
    _ran = true;
    final config = ref.read(appConfigProvider);
    ref.read(settingsProvider.notifier).markSession(ref.read(clockProvider).nowMs);

    final cloud = ref.read(cloudSyncProvider);
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
      final remote = await fetchRemoteGameConfig();
      if (remote != null && mounted) ref.read(gameConfigProvider.notifier).applyJson(remote);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
