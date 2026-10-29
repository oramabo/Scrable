import 'package:chetz_app/app.dart';
import 'package:chetz_app/core/content/content_source.dart';
import 'package:chetz_app/core/util/clock.dart';
import 'package:chetz_app/features/meta/game_events_controller.dart';
import 'package:chetz_app/features/puzzle/application/puzzle_controller.dart';
import 'package:chetz_app/features/puzzle/presentation/keyboard/puzzle_keyboard.dart';
import 'package:chetz_app/features/puzzle/presentation/puzzle_screen.dart';
import 'package:chetz_app/features/settings/settings_model.dart';
import 'package:chetz_app/features/sync/cloud_sync.dart';
import 'package:chetz_app/features/together/multiplayer_models.dart';
import 'package:chetz_app/features/together/multiplayer_service.dart';
import 'package:chetz_app/features/together/versus_screens.dart';
import 'package:chetz_app/features/together/versus_session.dart';
import 'package:chetz_app/features/together/versus_widgets.dart';
import 'package:chetz_core/meta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

/// Versus against a simulated opponent (FakeMultiplayerService): invite →
/// lobby → start → dual progress bar → finish → result sheet → rematch.
void main() {
  late MapContentSource content;
  setUpAll(() async => content = await loadBundledContent());

  Future<(FakeMultiplayerService, FixedClock)> pumpApp(WidgetTester tester) async {
    usePhoneSurface(tester);
    final clock = FixedClock(DateTime(2026, 10, 28, 12));
    final fake = FakeMultiplayerService(now: () => clock.nowMs);
    await tester.pumpWidget(ProviderScope(
      overrides: testOverrides(
        content: content,
        clock: clock,
        cloudSync: FakeCloudSync(),
        multiplayer: fake,
        settings: const AppSettings(onboardingDone: true, tutorialDone: true),
      ),
      child: const ChetzApp(),
    ));
    await settle(tester);
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('מולטי')));
    await settle(tester);
    return (fake, clock);
  }

  testWidgets('host invites, opponent joins, race runs with live progress, host wins and can rematch', (tester) async {
    final (fake, clock) = await pumpApp(tester);
    expect(find.text('משחק משותף'), findsOneWidget);
    await tester.tap(find.text('דו-קרב'));
    await settle(tester);
    expect(find.byType(VersusScreen), findsOneWidget);
    expect(find.text('מצא יריב'), findsOneWidget);

    await tester.tap(find.text('הזמן חבר'));
    await settle(tester);
    expect(find.byType(MatchLobbyScreen), findsOneWidget);
    expect(fake.calls, contains('createMatch'));
    final match = fake.matches.values.single;
    expect(find.text(match.inviteCode!), findsOneWidget, reason: 'invite code with copy/share');
    expect(find.text('מחכים שחבר יצטרף'), findsOneWidget);

    fake.simulateOpponentJoin(match.id);
    await settle(tester);
    expect(find.text('נועה'), findsOneWidget);
    expect(find.text('התחלה!'), findsOneWidget);
    await tester.tap(find.text('התחלה!'));
    await settle(tester);
    expect(fake.matches[match.id]!.status, MatchStatus.running);

    // The lobby opened the puzzle in a versus session.
    await pumpUntilFound(tester, find.byType(PuzzleKeyboard));
    expect(find.byType(VersusBar), findsOneWidget);
    final screen = tester.widget<PuzzleScreen>(find.byType(PuzzleScreen));
    expect(screen.matchId, match.id);
    final sessionId = screen.sessionId;
    expect(sessionId, '${match.puzzleId}?match=${match.id}');

    fake.simulateOpponentProgress(match.id, 0.4);
    await tester.pump();
    expect(find.text('40%'), findsOneWidget, reason: 'opponent progress from players.{uid}.progress');

    // Solve through the controller; progress reports are throttled to ≥ 1 s.
    final container = ProviderScope.containerOf(tester.element(find.byType(PuzzleScreen)));
    final controller = container.read(puzzleSessionProvider(sessionId).notifier);
    final session = container.read(puzzleSessionProvider(sessionId)).requireValue;
    final puzzle = session.puzzle;
    var typed = 0;
    for (final i in puzzle.letterCellIndices) {
      if (container.read(puzzleSessionProvider(sessionId)).requireValue.progress.entry(i).isLocked) continue;
      controller.tapCell(i);
      controller.typeSymbol(puzzle.solution[i]);
      typed++;
      if (typed % 3 == 0) clock.advance(const Duration(seconds: 2));
      await tester.pump();
    }
    expect(container.read(puzzleSessionProvider(sessionId)).requireValue.isComplete, isTrue);
    await tester.pump();
    await tester.pump();
    expect(fake.calls, contains('finishMatch'));
    expect(fake.calls.where((c) => c == 'reportProgress').length, lessThan(typed), reason: 'throttled');
    expect(fake.matches[match.id]!.players['me']!.finished, isTrue);
    expect(find.text('סיימתם! מחכים ליריב…'), findsOneWidget);
    expect(find.text('כל הכבוד'), findsNothing, reason: 'no solo completion sheet in a match');
    // No local coins for a multiplayer solve: the server pays.
    expect(container.read(metaProvider).stats.puzzlesCompleted, 1);

    fake.simulateOpponentFinish(match.id, elapsedMs: 99999);
    await settle(tester);
    expect(find.text('ניצחון!'), findsOneWidget);
    final me = fake.matches[match.id]!.players['me']!;
    expect(me.result, MatchResult.win);
    expect(find.text('${signedDelta(me.trophyDelta)} גביעים'), findsOneWidget);
    expect(find.textContaining('+40 מטבעות'), findsOneWidget, reason: 'server rewards');
    // Local progression mirrors the result once.
    expect(container.read(metaProvider).trophies, me.trophyDelta);
    expect(container.read(xpProvider), XpCurve.matchWinXp);

    await tester.tap(find.text('משחק חוזר'));
    await settle(tester);
    expect(find.byType(MatchLobbyScreen), findsOneWidget);
    expect(fake.matches.length, 2);
  });

  testWidgets('guest joins with a code, readies up and loses when finishing second', (tester) async {
    final (fake, clock) = await pumpApp(tester);
    final hosted = fake.simulateHostedMatch(code: 'ZZZ999');
    await tester.tap(find.text('דו-קרב'));
    await settle(tester);
    await tester.tap(find.text('הצטרף עם קוד'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'zzz 999');
    await tester.tap(find.text('הצטרפות'));
    await settle(tester);
    expect(find.byType(MatchLobbyScreen), findsOneWidget);
    expect(fake.matches[hosted.id]!.status, MatchStatus.ready);
    expect(find.text('מוכן/ה'), findsOneWidget);
    await tester.tap(find.text('מוכן/ה'));
    await settle(tester);
    expect(find.text('מוכנים · מחכים למארח'), findsOneWidget);

    fake.simulateHostStart(hosted.id);
    await settle(tester);
    await pumpUntilFound(tester, find.byType(PuzzleKeyboard));
    final sessionId = tester.widget<PuzzleScreen>(find.byType(PuzzleScreen)).sessionId;
    final container = ProviderScope.containerOf(tester.element(find.byType(PuzzleScreen)));

    // Opponent finishes first; then we finish → loss.
    clock.advance(const Duration(seconds: 30));
    fake.simulateOpponentFinish(hosted.id);
    await tester.pump();
    await tester.pump();
    expect(container.read(versusSessionProvider(sessionId)).match!.players['rival']!.finished, isTrue);
    expect(find.text('100%'), findsOneWidget, reason: 'opponent at 100% on the dual bar');
    clock.advance(const Duration(seconds: 30));
    final controller = container.read(puzzleSessionProvider(sessionId).notifier);
    final puzzle = container.read(puzzleSessionProvider(sessionId)).requireValue.puzzle;
    for (final i in puzzle.letterCellIndices) {
      if (container.read(puzzleSessionProvider(sessionId)).requireValue.progress.entry(i).isLocked) continue;
      controller.tapCell(i);
      controller.typeSymbol(puzzle.solution[i]);
    }
    await settle(tester);
    expect(find.text('הפעם לא'), findsOneWidget);
    expect(fake.matches[hosted.id]!.players['me']!.result, MatchResult.loss);
    expect(container.read(xpProvider), XpCurve.matchLossXp);
    await tester.tap(find.text('משחק משותף'));
    await settle(tester);
    expect(find.byType(VersusScreen), findsNothing);
  });

  testWidgets('leaving a running match asks for confirmation and forfeits', (tester) async {
    final (fake, _) = await pumpApp(tester);
    fake.autoMatch = true;
    await tester.tap(find.text('דו-קרב'));
    await settle(tester);
    await tester.tap(find.text('מצא יריב'));
    await settle(tester);
    expect(find.byType(MatchLobbyScreen), findsOneWidget);
    final match = fake.matches.values.single;
    expect(match.mode, 'random');
    fake.simulateHostStart(match.id);
    await settle(tester);
    await pumpUntilFound(tester, find.byType(PuzzleKeyboard));
    await tester.tap(find.byTooltip('חזרה'));
    await settle(tester);
    expect(find.text('לצאת מהמשחק?'), findsOneWidget);
    await tester.tap(find.text('יציאה'));
    await settle(tester);
    expect(fake.calls, contains('leaveMatch'));
    expect(fake.matches[match.id]!.players['me']!.result, MatchResult.forfeit);
    expect(find.byType(PuzzleScreen), findsNothing);
    expect(find.text('ניצחון!'), findsNothing);
    expect(find.text('משחק משותף'), findsWidgets);
  });

  testWidgets('trophy leaderboard groups entries by league and marks me', (tester) async {
    final (fake, _) = await pumpApp(tester);
    fake.board = const TrophyBoard(
      entries: [
        TrophyEntry(uid: 'a', displayName: 'אלון', trophies: 1600, rank: 1),
        TrophyEntry(uid: 'me', displayName: 'את/ה', trophies: 520, rank: 2),
        TrophyEntry(uid: 'b', displayName: 'בר', trophies: 30, rank: 3),
      ],
      me: TrophyEntry(uid: 'me', displayName: 'את/ה', trophies: 520, rank: 2),
    );
    await tester.tap(find.text('לוח הגביעים'));
    await settle(tester);
    expect(find.text('יהלום'), findsOneWidget);
    expect(find.text('זהב'), findsOneWidget);
    expect(find.text('עץ'), findsOneWidget);
    expect(find.textContaining('מקום 2'), findsOneWidget);
    expect(find.textContaining('את/ה · את/ה'), findsOneWidget);
  });
}
