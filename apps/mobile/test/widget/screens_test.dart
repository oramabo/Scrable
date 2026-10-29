import 'package:chetz_app/app.dart';
import 'package:chetz_app/core/content/content_source.dart';
import 'package:chetz_app/core/util/clock.dart';
import 'package:chetz_app/features/meta/achievements_screen.dart';
import 'package:chetz_app/features/meta/game_events_controller.dart';
import 'package:chetz_app/features/meta/meta_state.dart';
import 'package:chetz_app/features/meta/missions_section.dart';
import 'package:chetz_app/features/profile/profile_controller.dart';
import 'package:chetz_app/features/profile/profile_screen.dart';
import 'package:chetz_app/features/puzzle/application/puzzle_controller.dart';
import 'package:chetz_app/features/puzzle/presentation/puzzle_screen.dart';
import 'package:chetz_app/features/settings/settings_controller.dart';
import 'package:chetz_app/features/settings/settings_model.dart';
import 'package:chetz_app/features/settings/theme/color_picker.dart';
import 'package:chetz_app/features/settings/theme/custom_theme.dart';
import 'package:chetz_app/features/settings/theme/theme_screen.dart';
import 'package:chetz_app/features/together/together_screen.dart';
import 'package:chetz_app/features/wallet/wallet_controller.dart';
import 'package:chetz_core/chetz_core.dart';
import 'package:chetz_core/meta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  late MapContentSource content;
  setUpAll(() async => content = await loadBundledContent());

  testWidgets('achievements screen shows all 32 achievements grouped by tier with progress', (tester) async {
    usePhoneSurface(tester);
    const stats = PlayerStats(puzzlesCompleted: 12, perfectPuzzles: 1, wordsSolved: 120);
    await tester.pumpWidget(wrapScreen(
      const AchievementsScreen(),
      overrides: testOverrides(content: content, meta: const MetaState(stats: stats)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('הישגים'), findsOneWidget);
    final unlocked = Achievements.all.where((a) => a.isUnlocked(stats)).length;
    expect(find.text('$unlocked/32 הישגים הושגו'), findsOneWidget);
    final list = find.byType(Scrollable).first;
    expect(find.text('ארד'), findsOneWidget);
    expect(find.text('צעד ראשון'), findsOneWidget);
    for (final tier in ['כסף', 'זהב', 'פלטינה']) {
      await tester.scrollUntilVisible(find.text(tier), 300, scrollable: list);
      expect(find.text(tier), findsOneWidget);
      if (tier == 'כסף') {
        await tester.scrollUntilVisible(find.textContaining('12/50'), 300, scrollable: list);
        expect(find.textContaining('12/50'), findsOneWidget, reason: 'solver_50 progress');
      }
    }
    await tester.scrollUntilVisible(find.text('מאסטר'), 300, scrollable: list);
    expect(find.text('מאסטר'), findsOneWidget);
  });

  testWidgets('missions section claims a finished mission once', (tester) async {
    usePhoneSurface(tester);
    final clock = FixedClock(DateTime(2026, 10, 29, 12));
    await tester.pumpWidget(wrapScreen(
      const Scaffold(body: SingleChildScrollView(child: MissionsSection())),
      overrides: testOverrides(content: content, clock: clock),
    ));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(MissionsSection)));
    final set = container.read(missionsProvider);
    expect(find.text('משימות'), findsOneWidget);
    expect(find.textContaining('מתאפס בעוד'), findsNWidgets(2));
    final mission = set.daily.first;
    // Complete the mission through events.
    final events = container.read(metaProvider.notifier);
    for (var i = 0; i < 30 && !container.read(metaProvider).countersFor(mission).isDone(mission); i++) {
      switch (mission.template.kind) {
        case MissionKind.useAlphabetCycler:
          events.recordCyclerUsed();
        case MissionKind.shareResult:
          events.recordShared();
        case MissionKind.earnCoins:
          events.recordCoinsEarned(100);
        case MissionKind.solveWords:
          events.recordWordSolved('he');
        default:
          events.record(GameEvent.puzzleCompleted(
            timestampMs: clock.nowMs,
            lang: 'he',
            puzzleId: 'p$i',
            level: 4,
            mode: PlayMode.newspaper,
            elapsedMs: 1000,
            parMs: 5 * 60000,
            hintsUsed: 0,
            wordsSolved: 0,
            isDaily: true,
            dailyVariant: i.isEven ? 'easy' : 'hard',
            dailyDate: '2026-10-29',
          ));
      }
    }
    expect(container.read(metaProvider).canClaim(mission), isTrue);
    await tester.pumpAndSettle();
    final before = container.read(balanceProvider);
    await tester.tap(find.textContaining('קבלת הפרס').first);
    await tester.pumpAndSettle();
    expect(container.read(balanceProvider), before + mission.reward);
    expect(container.read(metaProvider).isClaimed(mission), isTrue);
    expect(find.textContaining('קבלת הפרס'), findsNothing, reason: 'claimed missions show a check instead of the button');
  });

  testWidgets('profile: default name/avatar, rename and avatar picker', (tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(wrapScreen(const ProfileTab(), overrides: testOverrides(content: content)));
    await tester.pumpAndSettle();
    expect(find.text('פותר/ת'), findsOneWidget);
    expect(find.textContaining('טירון'), findsOneWidget);
    await tester.tap(find.byTooltip('שינוי שם'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'דנה');
    await tester.tap(find.text('שמירה'));
    await tester.pumpAndSettle();
    expect(find.text('דנה'), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.byType(ProfileTab)));
    expect(container.read(profileProvider).displayName, 'דנה');
    await tester.tap(find.byType(AvatarView).first);
    await tester.pumpAndSettle();
    expect(find.text('בחירת אווטאר'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('ינשוף'));
    await tester.pumpAndSettle();
    expect(container.read(profileProvider).avatarId, 'owl');
    await tester.scrollUntilVisible(find.text('התחברות לסנכרון'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('סנכרון בענן זמין בגרסה עם Firebase. ההתקדמות נשמרת במכשיר.'), findsOneWidget);
  });

  testWidgets('theme screen: custom palette with live preview and contrast warnings', (tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(wrapScreen(const ThemeScreen(), overrides: testOverrides(content: content)));
    await tester.pumpAndSettle();
    expect(find.text('מותאם אישית'), findsOneWidget);
    await tester.tap(find.text('מותאם אישית'));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(ThemeScreen)));
    expect(container.read(settingsProvider).useCustomTheme, isTrue);
    expect(find.textContaining('ניגודיות תקינה'), findsNWidgets(3), reason: 'defaults are readable');
    await tester.scrollUntilVisible(find.text('הדגשת המילה הפעילה'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.byType(ColorPickerField), findsNWidgets(3));
    await tester.scrollUntilVisible(find.text('מותאם אישית'), -300, scrollable: find.byType(Scrollable).first);

    // A dark highlight under black text drops below 4.5:1: the palette is refused.
    container.read(settingsProvider.notifier).update(
          (s) => s.copyWith(customTheme: s.customTheme.copyWith(background: const Color(0xFFFFFFFF), highlight: const Color(0xFF333333))),
        );
    await tester.pumpAndSettle();
    expect(find.textContaining('ניגודיות נמוכה'), findsWidgets);
    expect(find.textContaining('לא מופעל'), findsOneWidget);
    expect(ContrastReport.of(container.read(settingsProvider).customTheme).isApplicable, isFalse);

    // Palette swatch inside a picker changes the colour.
    await tester.tap(find.text('צבע רקע'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('#FFFFFF'));
    await tester.pumpAndSettle();
    expect(container.read(settingsProvider).customTheme.background, const Color(0xFFFFFFFF));
  });

  testWidgets('together tab is a placeholder with a leaderboard entry', (tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(wrapScreen(const TogetherTab(), overrides: testOverrides(content: content)));
    await tester.pumpAndSettle();
    expect(find.text('משחק משותף'), findsOneWidget);
    expect(find.text('לוח התוצאות'), findsOneWidget);
    expect(find.text('דו-קרב'), findsOneWidget);
  });

  testWidgets('FTUE: name screen → tutorial puzzle with coach marks; first completion pays the bonus', (tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: testOverrides(content: content, settings: const AppSettings()),
      child: const ChetzApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('איך נקרא לך?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'רון');
    await tester.tap(find.text('יאללה, מתחילים'));
    await pumpUntilFound(tester, find.byType(PuzzleScreen));
    await tester.pump(const Duration(milliseconds: 200));
    final container = ProviderScope.containerOf(tester.element(find.byType(PuzzleScreen)));
    expect(container.read(settingsProvider).onboardingDone, isTrue);
    expect(container.read(profileProvider).displayName, 'רון');
    final session = container.read(puzzleSessionProvider(tutorialPuzzleIdFor('he'))).requireValue;
    expect(session.puzzle.kind, PuzzleKind.tutorial);
    expect(session.isTutorial, isTrue);
    expect(find.text('לחצו על תא כדי לבחור מילה'), findsOneWidget, reason: 'first coach mark');
  });
}
