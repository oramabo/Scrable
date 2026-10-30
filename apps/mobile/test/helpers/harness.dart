import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chetz_app/core/config/app_config.dart';
import 'package:chetz_app/core/content/content_repository.dart';
import 'package:chetz_app/core/content/content_source.dart';
import 'package:chetz_app/core/l10n/l10n.dart';
import 'package:chetz_app/core/providers.dart';
import 'package:chetz_app/core/storage/json_store.dart';
import 'package:chetz_app/core/util/clock.dart';
import 'package:chetz_app/core/util/feedback.dart';
import 'package:chetz_app/features/feedback/review_service.dart';
import 'package:chetz_app/features/daily/daily_history.dart';
import 'package:chetz_app/features/meta/meta_state.dart';
import 'package:chetz_app/features/notifications/notifications_controller.dart';
import 'package:chetz_app/features/notifications/notifications_service.dart';
import 'package:chetz_app/features/puzzle/application/puzzle_controller.dart';
import 'package:chetz_app/features/random/random_puzzle_generator.dart';
import 'package:chetz_app/features/random/random_puzzle_providers.dart';
import 'package:chetz_app/features/settings/settings_controller.dart';
import 'package:chetz_app/features/settings/settings_model.dart';
import 'package:chetz_app/features/sync/cloud_sync.dart';
import 'package:chetz_app/features/together/multiplayer_providers.dart';
import 'package:chetz_app/features/together/multiplayer_service.dart';
import 'package:chetz_app/features/wallet/ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// Reads the bundled content from disk (the test cwd is the package root) into
/// an in-memory content source, so widget tests never touch rootBundle's
/// asynchronous asset channel. [device] also loads the gzipped device
/// lexicon / templates (random puzzles).
Future<MapContentSource> loadBundledContent({String lang = 'he', bool device = false}) async {
  final root = Directory.current.path;
  final docs = <String, String>{};
  final binaries = <String, Uint8List>{};
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
    final dev = index['device'];
    if (device && dev is Map) {
      for (final path in dev.values) {
        final f = File('$root/$path');
        if (await f.exists()) binaries[path as String] = await f.readAsBytes();
      }
    }
  }
  return MapContentSource(docs, binaries);
}

/// An in-process random-puzzle generator over [content]'s device data (no
/// isolates: widget tests run under FakeAsync).
RandomPuzzleGenerator inProcessGenerator(MapContentSource content, {int Function()? now}) => DeviceRandomPuzzleGenerator(
      inProcess: true,
      now: now,
      dataFor: (lang) => loadDeviceData(ContentRepository(lang: lang, bundled: content)),
    );

/// A content source holding only the picture-clue fixture puzzle `he-pic-01`
/// and its tiny PNG (test/fixtures).
Future<MapContentSource> loadPictureFixture() async {
  final root = Directory.current.path;
  final puzzle = await File('$root/test/fixtures/picture_puzzle.json').readAsString();
  final png = await File('$root/test/fixtures/images/test.png').readAsBytes();
  return MapContentSource(
    {
      'assets/puzzles/he/index.json': jsonEncode({
        'lang': 'he',
        'puzzles': {'he-pic-01': 'assets/puzzles/he/packs/pic/01.json'},
        'packs': {},
        'dailies': {},
      }),
      'assets/puzzles/he/packs/pic/01.json': puzzle,
    },
    {'assets/puzzles/he/images/test.png': Uint8List.fromList(png)},
  );
}

const testStartingWallet = 200;

/// Provider overrides for a fully offline test app.
List<Override> testOverrides({
  required MapContentSource content,
  AppSettings settings = const AppSettings(onboardingDone: true, tutorialDone: true, systemKeyboard: false),
  MemoryJsonStore? store,
  Clock? clock,
  DailyHistory? dailyHistory,
  MetaState meta = const MetaState(),
  Ledger? ledger,
  CloudSync cloudSync = const DisabledCloudSync(),
  MultiplayerService? multiplayer,
  NotificationsService? notifications,
  RandomPuzzleGenerator? generator,
  ReviewService? review,
  List<Override> extra = const [],
}) {
  final s = store ?? MemoryJsonStore();
  final c = clock ?? FixedClock(DateTime(2026, 10, 28, 12));
  final bootstrap = AppBootstrap(
    settings: settings,
    ledger: ledger ?? Ledger.initial(startingWallet: testStartingWallet, now: c.nowMs),
    dailyHistory: dailyHistory ?? DailyHistory(),
    summaries: const {},
    meta: meta,
    cloudSync: cloudSync,
  );
  return [
    appConfigProvider.overrideWithValue(const AppConfig()),
    jsonStoreProvider.overrideWithValue(s),
    bootstrapProvider.overrideWithValue(bootstrap),
    clockProvider.overrideWithValue(c),
    puzzleTimerEnabledProvider.overrideWithValue(false),
    uiTimersEnabledProvider.overrideWithValue(false),
    hapticsProvider.overrideWithValue(const NoHaptics()),
    contentRepositoryProvider.overrideWith(
      (ref, lang) => ContentRepository(lang: lang, bundled: content, cache: s),
    ),
    multiplayerServiceProvider.overrideWithValue(multiplayer ?? const DisabledMultiplayerService()),
    notificationsServiceProvider.overrideWithValue(notifications ?? const DisabledNotificationsService()),
    randomPuzzleGeneratorProvider.overrideWithValue(generator ?? inProcessGenerator(content, now: () => c.nowMs)),
    reviewServiceProvider.overrideWithValue(review ?? FakeReviewService(available: false)),
    ...extra,
  ];
}

Widget wrapScreen(Widget home, {required List<Override> overrides, String uiLang = 'he', ThemeData? theme}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: Locale(uiLang),
      theme: theme,
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

/// Pumps a fixed amount of fake time in short frames: use instead of
/// `pumpAndSettle` on screens with an indeterminate progress indicator
/// (lobbies waiting for a player), which never settles.
Future<void> settle(WidgetTester tester, {Duration total = const Duration(milliseconds: 600)}) async {
  const step = Duration(milliseconds: 100);
  var elapsed = Duration.zero;
  while (elapsed < total) {
    await tester.pump(step);
    elapsed += step;
  }
}

/// Phone-sized test surface (360×760 logical).
void usePhoneSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1080, 2280);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// 390×844 logical (UX review size).
void useReviewSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(390 * 3, 844 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

bool _fontsLoaded = false;

/// Loads the real UI fonts (and Material icons) so screenshots are readable
/// instead of Ahem boxes. Call from setUpAll.
Future<void> loadRealFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  final root = Directory.current.path;
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      final f = File(p);
      if (!f.existsSync()) continue;
      final bytes = f.readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('NotoSansHebrew', [
    '$root/assets/fonts/NotoSansHebrew-Regular.ttf',
    '$root/assets/fonts/NotoSansHebrew-Medium.ttf',
    '$root/assets/fonts/NotoSansHebrew-SemiBold.ttf',
    '$root/assets/fonts/NotoSansHebrew-Bold.ttf',
  ]);
  await load('Inter', [
    '$root/assets/fonts/Inter-Regular.ttf',
    '$root/assets/fonts/Inter-Medium.ttf',
    '$root/assets/fonts/Inter-SemiBold.ttf',
    '$root/assets/fonts/Inter-Bold.ttf',
  ]);
  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
  await load('MaterialIcons', ['$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
}

/// Captures the widget under [key] into `test/screenshots/goldens/<name>.png`.
Future<String> captureScreenshot(WidgetTester tester, GlobalKey key, String name, {double pixelRatio = 1.5}) async {
  final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
  final path = '${Directory.current.path}/test/screenshots/goldens/$name.png';
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
  });
  return path;
}
