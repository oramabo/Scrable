import 'dart:convert';
import 'dart:io';

import 'package:chetz_app/core/config/app_config.dart';
import 'package:chetz_app/core/content/content_repository.dart';
import 'package:chetz_app/core/content/content_source.dart';
import 'package:chetz_app/core/l10n/l10n.dart';
import 'package:chetz_app/core/providers.dart';
import 'package:chetz_app/core/storage/json_store.dart';
import 'package:chetz_app/core/util/clock.dart';
import 'package:chetz_app/features/daily/daily_history.dart';
import 'package:chetz_app/features/puzzle/application/puzzle_controller.dart';
import 'package:chetz_app/features/settings/settings_model.dart';
import 'package:chetz_app/features/wallet/ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Reads the bundled Hebrew content from disk (the test cwd is the package
/// root) into an in-memory content source, so widget tests never touch
/// rootBundle's asynchronous asset channel.
Future<MapContentSource> loadBundledContent({String lang = 'he'}) async {
  final root = Directory.current.path;
  final docs = <String, String>{};
  Future<void> add(String assetPath) async {
    final f = File('$root/$assetPath');
    if (await f.exists()) docs[assetPath] = await f.readAsString();
  }

  await add('assets/puzzles/$lang/index.json');
  await add('assets/puzzles/$lang/manifests/packs.json');
  await add('assets/puzzles/$lang/manifests/daily.json');
  final indexText = docs['assets/puzzles/$lang/index.json'];
  if (indexText != null) {
    final index = jsonDecode(indexText) as Map<String, dynamic>;
    for (final section in ['puzzles', 'packs', 'dailies']) {
      final m = index[section];
      if (m is Map) {
        for (final path in m.values) {
          await add(path as String);
        }
      }
    }
  }
  return MapContentSource(docs);
}

const testStartingWallet = 200;

/// Provider overrides for a fully offline test app.
List<Override> testOverrides({
  required MapContentSource content,
  AppSettings settings = const AppSettings(onboardingDone: true, tutorialDone: true),
  MemoryJsonStore? store,
  Clock? clock,
  DailyHistory? dailyHistory,
}) {
  final s = store ?? MemoryJsonStore();
  final c = clock ?? FixedClock(DateTime(2026, 10, 28, 12));
  final bootstrap = AppBootstrap(
    settings: settings,
    ledger: Ledger.initial(startingWallet: testStartingWallet, now: c.nowMs),
    dailyHistory: dailyHistory ?? DailyHistory(),
    summaries: const {},
  );
  return [
    appConfigProvider.overrideWithValue(const AppConfig()),
    jsonStoreProvider.overrideWithValue(s),
    bootstrapProvider.overrideWithValue(bootstrap),
    clockProvider.overrideWithValue(c),
    puzzleTimerEnabledProvider.overrideWithValue(false),
    contentRepositoryProvider.overrideWith(
      (ref, lang) => ContentRepository(lang: lang, bundled: content, cache: s),
    ),
  ];
}

Widget wrapScreen(Widget home, {required List<Override> overrides, String uiLang = 'he'}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      locale: Locale(uiLang),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    ),
  );
}

/// Pumps frames until [finder] matches or [timeout] of fake time passes.
Future<void> pumpUntilFound(WidgetTester tester, Finder finder, {Duration timeout = const Duration(seconds: 10)}) async {
  var elapsed = Duration.zero;
  const step = Duration(milliseconds: 50);
  while (elapsed < timeout) {
    await tester.pump(step);
    elapsed += step;
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

/// Phone-sized test surface.
void usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}
