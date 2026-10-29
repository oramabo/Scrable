import 'package:chetz_app/app.dart';
import 'package:chetz_app/core/content/content_source.dart';
import 'package:chetz_app/core/l10n/l10n.dart';
import 'package:chetz_app/core/theme/app_theme.dart';
import 'package:chetz_app/features/home/home_shell.dart';
import 'package:chetz_app/features/meta/achievements_screen.dart';
import 'package:chetz_app/features/meta/meta_state.dart';
import 'package:chetz_app/features/profile/profile_screen.dart';
import 'package:chetz_app/features/puzzle/application/puzzle_controller.dart';
import 'package:chetz_app/features/puzzle/presentation/keyboard/puzzle_keyboard.dart';
import 'package:chetz_app/features/puzzle/presentation/puzzle_screen.dart';
import 'package:chetz_app/features/puzzle/presentation/sheets/completion_sheet.dart';
import 'package:chetz_app/features/season/season_screen.dart';
import 'package:chetz_app/features/settings/settings_model.dart';
import 'package:chetz_app/features/settings/theme/theme_screen.dart';
import 'package:chetz_app/features/sync/cloud_sync.dart';
import 'package:chetz_app/features/together/coop_screens.dart';
import 'package:chetz_app/features/together/multiplayer_service.dart';
import 'package:chetz_app/features/together/versus_screens.dart';
import 'package:chetz_core/meta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

/// UI review screenshots (390×844, light + dark), written to
/// test/screenshots/goldens/*.png. They never fail on pixel differences: the
/// PNGs are regenerated on every run so the UI can be reviewed as images.
void main() {
  late MapContentSource content;
  late MapContentSource contentEn;
  final written = <String>[];

  setUpAll(() async {
    await loadRealFonts();
    content = await loadBundledContent();
    contentEn = await loadBundledContent(lang: 'en');
  });

  tearDownAll(() {
    // ignore: avoid_print
    print('screenshots written:\n${written.join('\n')}');
  });

  const demoStats = PlayerStats(
    puzzlesCompleted: 23,
    perfectPuzzles: 6,
    dailiesCompleted: 9,
    hardDailiesCompleted: 2,
    wordsSolved: 410,
    hintsUsed: 11,
    coinsEarned: 1260,
    currentStreak: 4,
    bestStreak: 9,
    lastDailyDate: '2026-10-28',
    languages: {'he'},
    completionsByLevel: {1: 15, 2: 6, 3: 2},
    loginDays: 12,
  );

  Widget boundary(GlobalKey key, Widget child) => RepaintBoundary(key: key, child: child);

  Future<void> shoot(WidgetTester tester, GlobalKey key, String name) async {
    written.add(await captureScreenshot(tester, key, name));
  }

  Widget app({required String uiLang, required ThemeMode mode, GlobalKey? key}) => ProviderScope(
        overrides: testOverrides(
          content: content,
          settings: AppSettings(uiLang: uiLang, onboardingDone: true, tutorialDone: true, themeMode: mode),
          meta: const MetaState(stats: demoStats),
        ),
        child: boundary(key ?? GlobalKey(), const ChetzApp()),
      );

  Widget screen(Widget home,
          {required String uiLang,
          required Brightness brightness,
          required GlobalKey key,
          MetaState meta = const MetaState(stats: demoStats),
          FakeMultiplayerService? multiplayer}) =>
      ProviderScope(
        overrides: testOverrides(
          content: content,
          settings: AppSettings(uiLang: uiLang, onboardingDone: true, tutorialDone: true),
          meta: meta,
          cloudSync: multiplayer == null ? const DisabledCloudSync() : FakeCloudSync(),
          multiplayer: multiplayer,
        ),
        child: boundary(
          key,
          MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: Locale(uiLang),
            theme: AppTheme.build(brightness: brightness, highContrast: false, uiLang: uiLang),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: home,
          ),
        ),
      );

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    final suffix = mode.name;

    testWidgets('home he $suffix', (tester) async {
      useReviewSurface(tester);
      final key = GlobalKey();
      await tester.pumpWidget(app(uiLang: 'he', mode: mode, key: key));
      await pumpUntilFound(tester, find.byType(HomeTab));
      await tester.pump(const Duration(milliseconds: 400));
      await shoot(tester, key, 'home_he_$suffix');
      // Missions strip: scroll it into view and shoot again.
      await tester.scrollUntilVisible(find.byType(MissionsStrip), 200, scrollable: find.byType(Scrollable).first);
      await tester.pump(const Duration(milliseconds: 200));
      await shoot(tester, key, 'home_missions_he_$suffix');
    });

    testWidgets('home en $suffix', (tester) async {
      useReviewSurface(tester);
      final key = GlobalKey();
      await tester.pumpWidget(app(uiLang: 'en', mode: mode, key: key));
      await pumpUntilFound(tester, find.byType(HomeTab));
      await tester.pump(const Duration(milliseconds: 400));
      await shoot(tester, key, 'home_en_$suffix');
    });

    for (final lang in ['he', 'en']) {
      testWidgets('solving $lang mid-puzzle $suffix', (tester) async {
        useReviewSurface(tester);
        final key = GlobalKey();
        final brightness = mode == ThemeMode.dark ? Brightness.dark : Brightness.light;
        final id = '$lang-l1-p01-02';
        final source = lang == 'he' ? content : contentEn;
        await tester.pumpWidget(ProviderScope(
          overrides: testOverrides(
            content: source,
            settings: AppSettings(uiLang: lang, puzzleLang: lang, onboardingDone: true, tutorialDone: true),
            meta: const MetaState(stats: demoStats),
          ),
          child: boundary(
            key,
            MaterialApp(
              debugShowCheckedModeBanner: false,
              locale: Locale(lang),
              theme: AppTheme.build(brightness: brightness, highContrast: false, uiLang: lang),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: PuzzleScreen(puzzleId: id),
            ),
          ),
        ));
        await pumpUntilFound(tester, find.byType(PuzzleKeyboard));
        final container = ProviderScope.containerOf(tester.element(find.byType(PuzzleScreen)));
        final controller = container.read(puzzleSessionProvider(id).notifier);
        final session = container.read(puzzleSessionProvider(id)).requireValue;
        // Fill the first two words fully and leave the third with one letter.
        final order = session.puzzle.words.take(3).toList();
        for (var w = 0; w < order.length; w++) {
          final cells = order[w].cells.map(session.puzzle.shape.indexOf).toList();
          final count = w == 2 ? cells.length - 1 : cells.length;
          for (final c in cells.take(count)) {
            controller.tapCell(c);
            controller.typeSymbol(session.puzzle.solution[c]);
          }
        }
        await tester.pump(const Duration(milliseconds: 800));
        await shoot(tester, key, 'solving_${lang}_$suffix');
      });
    }

    testWidgets('completion sheet $suffix', (tester) async {
      useReviewSurface(tester);
      final key = GlobalKey();
      final brightness = mode == ThemeMode.dark ? Brightness.dark : Brightness.light;
      const id = 'he-l1-p01-03';
      await tester.pumpWidget(screen(const PuzzleScreen(puzzleId: id), uiLang: 'he', brightness: brightness, key: key));
      await pumpUntilFound(tester, find.byType(PuzzleKeyboard));
      final container = ProviderScope.containerOf(tester.element(find.byType(PuzzleScreen)));
      final controller = container.read(puzzleSessionProvider(id).notifier);
      final session = container.read(puzzleSessionProvider(id)).requireValue;
      for (final i in session.puzzle.letterCellIndices) {
        if (container.read(puzzleSessionProvider(id)).requireValue.progress.entry(i).isLocked) continue;
        controller.tapCell(i);
        controller.typeSymbol(session.puzzle.solution[i]);
      }
      await tester.pumpAndSettle();
      expect(find.byType(CompletionSheet), findsOneWidget);
      await shoot(tester, key, 'completion_he_$suffix');
    });

    testWidgets('achievements $suffix', (tester) async {
      useReviewSurface(tester);
      final key = GlobalKey();
      final brightness = mode == ThemeMode.dark ? Brightness.dark : Brightness.light;
      await tester.pumpWidget(screen(const AchievementsScreen(), uiLang: 'he', brightness: brightness, key: key));
      await tester.pumpAndSettle();
      await shoot(tester, key, 'achievements_he_$suffix');
    });

    testWidgets('profile $suffix', (tester) async {
      useReviewSurface(tester);
      final key = GlobalKey();
      final brightness = mode == ThemeMode.dark ? Brightness.dark : Brightness.light;
      await tester.pumpWidget(screen(const ProfileTab(), uiLang: 'he', brightness: brightness, key: key));
      await tester.pumpAndSettle();
      await shoot(tester, key, 'profile_he_$suffix');
    });

    testWidgets('season pass $suffix', (tester) async {
      useReviewSurface(tester);
      final key = GlobalKey();
      final brightness = mode == ThemeMode.dark ? Brightness.dark : Brightness.light;
      const meta = MetaState(stats: demoStats, xp: 640, seasonPoints: {'2026-S1': 265}, claimedSeasonTiers: {'season:2026-S1:tier:1'}, trophies: 180);
      await tester.pumpWidget(screen(const SeasonScreen(), uiLang: 'he', brightness: brightness, key: key, meta: meta));
      await tester.pumpAndSettle();
      await shoot(tester, key, 'season_pass_he_$suffix');
    });

    testWidgets('random puzzle level sheet $suffix', (tester) async {
      useReviewSurface(tester);
      final key = GlobalKey();
      await tester.pumpWidget(app(uiLang: 'he', mode: mode, key: key));
      await pumpUntilFound(tester, find.byType(HomeTab));
      await tester.pump(const Duration(milliseconds: 400));
      final list = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(find.textContaining('עונה 1'), 200, scrollable: list);
      await tester.ensureVisible(find.text('תשחץ אקראי'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('תשחץ אקראי'));
      await tester.pumpAndSettle();
      await shoot(tester, key, 'random_level_sheet_he_$suffix');
    });

    testWidgets('versus lobby (fake backend) $suffix', (tester) async {
      useReviewSurface(tester);
      final key = GlobalKey();
      final brightness = mode == ThemeMode.dark ? Brightness.dark : Brightness.light;
      final fake = FakeMultiplayerService();
      final match = await fake.createMatch(lang: 'he', level: 2);
      fake.simulateOpponentJoin(match.id);
      await tester.pumpWidget(screen(MatchLobbyScreen(matchId: match.id), uiLang: 'he', brightness: brightness, key: key, multiplayer: fake));
      await tester.pumpAndSettle();
      await shoot(tester, key, 'versus_lobby_he_$suffix');
    });

    testWidgets('co-op room (fake backend) $suffix', (tester) async {
      useReviewSurface(tester);
      final key = GlobalKey();
      final brightness = mode == ThemeMode.dark ? Brightness.dark : Brightness.light;
      final fake = FakeMultiplayerService();
      final room = await fake.createCoopRoom(lang: 'he', puzzleId: 'he-l1-p01-02');
      fake.simulateMemberJoin(room.id, memberUid: 'u2', name: 'נועה');
      fake.simulateMemberJoin(room.id, memberUid: 'u3', name: 'יוסי');
      await tester.pumpWidget(screen(RoomLobbyScreen(roomId: room.id), uiLang: 'he', brightness: brightness, key: key, multiplayer: fake));
      await tester.pumpAndSettle();
      await shoot(tester, key, 'coop_room_he_$suffix');
    });

    testWidgets('theme picker $suffix', (tester) async {
      useReviewSurface(tester);
      final key = GlobalKey();
      final brightness = mode == ThemeMode.dark ? Brightness.dark : Brightness.light;
      await tester.pumpWidget(ProviderScope(
        overrides: testOverrides(
          content: content,
          settings: const AppSettings(onboardingDone: true, tutorialDone: true, useCustomTheme: true),
          meta: const MetaState(stats: demoStats),
        ),
        child: boundary(
          key,
          MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('he'),
            theme: AppTheme.build(brightness: brightness, highContrast: false, uiLang: 'he'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ThemeScreen(),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('צבע ראשי'));
      await tester.pumpAndSettle();
      await shoot(tester, key, 'theme_picker_he_$suffix');
    });
  }
}
