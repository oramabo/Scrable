import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/config/game_config.dart';
import 'core/providers.dart';
import 'core/storage/json_store.dart';
import 'core/util/clock.dart';
import 'features/notifications/notifications_controller.dart';
import 'features/notifications/notifications_service.dart';
import 'features/sync/cloud_sync.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  final docs = await getApplicationDocumentsDirectory();
  final store = FileJsonStore(Directory('${docs.path}/chetz'));
  const clock = SystemClock();

  // Firebase only when the flag is on AND the platform config files exist;
  // any failure falls back to the disabled implementation.
  CloudSync cloud = const DisabledCloudSync();
  if (config.firebaseEnabled) {
    try {
      await Firebase.initializeApp();
      final sync = FirebaseCloudSync();
      await sync.initialize();
      cloud = sync;
    } catch (e) {
      debugPrint('Firebase disabled: $e');
    }
  }

  final bootstrap = await AppBootstrap.load(store: store, gameConfig: const GameConfig(), clock: clock, cloudSync: cloud);
  _registerFontLicenses();

  runApp(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        jsonStoreProvider.overrideWithValue(store),
        bootstrapProvider.overrideWithValue(bootstrap),
        notificationsServiceProvider.overrideWithValue(LocalNotificationsService()),
      ],
      child: const ChetzApp(),
    ),
  );
}

void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Noto Sans Hebrew'], await rootBundle.loadString('assets/fonts/OFL-NotoSansHebrew.txt'));
    yield LicenseEntryWithLineBreaks(['Inter'], await rootBundle.loadString('assets/fonts/OFL-Inter.txt'));
  });
}
