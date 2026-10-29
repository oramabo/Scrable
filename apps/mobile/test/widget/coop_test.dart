import 'package:chetz_app/app.dart';
import 'package:chetz_app/core/content/content_source.dart';
import 'package:chetz_app/core/util/clock.dart';
import 'package:chetz_app/features/meta/game_events_controller.dart';
import 'package:chetz_app/features/puzzle/application/puzzle_controller.dart';
import 'package:chetz_app/features/puzzle/presentation/grid/puzzle_grid.dart';
import 'package:chetz_app/features/puzzle/presentation/keyboard/puzzle_keyboard.dart';
import 'package:chetz_app/features/puzzle/presentation/puzzle_screen.dart';
import 'package:chetz_app/features/settings/settings_model.dart';
import 'package:chetz_app/features/sync/cloud_sync.dart';
import 'package:chetz_app/features/together/coop_screens.dart';
import 'package:chetz_app/features/together/multiplayer_models.dart';
import 'package:chetz_app/features/together/multiplayer_service.dart';
import 'package:chetz_app/features/together/versus_widgets.dart';
import 'package:chetz_core/meta.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

/// Co-op room with simulated members (FakeMultiplayerService): create → join →
/// start → shared grid (remote letters merged, own letters written, cursors)
/// → host finishes → rewards for all.
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
    await tester.tap(find.text('פתרון משותף'));
    await settle(tester);
    expect(find.byType(CoopScreen), findsOneWidget);
    return (fake, clock);
  }

  testWidgets('host creates a room, a friend joins, letters are shared both ways, host finishes', (tester) async {
    final (fake, clock) = await pumpApp(tester);
    await tester.tap(find.text('פתיחת חדר'));
    await settle(tester);
    expect(find.text('בחירת תשחץ לחדר'), findsOneWidget);
    await tester.tap(find.textContaining('רמה 1 ·').last);
    await settle(tester);
    expect(find.text('אין תשחץ פנוי ברמה זו כרגע'), findsNothing, reason: 'a pack puzzle of level 1 is picked for the room');
    expect(find.text('לא הצלחנו להתחבר למשחק. נסו שוב.'), findsNothing);
    expect(find.byType(RoomLobbyScreen), findsOneWidget);
    final room = fake.rooms.values.single;
    expect(find.text(room.code!), findsOneWidget);
    expect(find.text('1/4 שחקנים'), findsOneWidget);

    fake.simulateMemberJoin(room.id, memberUid: 'rival', name: 'נועה');
    await settle(tester);
    expect(find.text('2/4 שחקנים'), findsOneWidget);
    expect(find.text('נועה'), findsOneWidget);
    expect(fake.rooms[room.id]!.members['rival']!.color, 1, reason: 'second member gets the second colour');

    await tester.tap(find.text('התחלה!'));
    await settle(tester);
    expect(fake.rooms[room.id]!.status, RoomStatus.running);
    await pumpUntilFound(tester, find.byType(PuzzleKeyboard));
    expect(find.byType(CoopBar), findsOneWidget);
    final screen = tester.widget<PuzzleScreen>(find.byType(PuzzleScreen));
    expect(screen.roomId, room.id);
    final sessionId = screen.sessionId;
    final container = ProviderScope.containerOf(tester.element(find.byType(PuzzleScreen)));
    final controller = container.read(puzzleSessionProvider(sessionId).notifier);
    final puzzle = container.read(puzzleSessionProvider(sessionId)).requireValue.puzzle;
    final cells = puzzle.letterCellIndices;

    // A remote letter lands in our grid, tinted with the member's colour.
    final remoteCell = cells.last;
    fake.simulateRemoteCell(room.id, remoteCell, puzzle.solution[remoteCell]);
    await tester.pump();
    await tester.pump();
    expect(container.read(puzzleSessionProvider(sessionId)).requireValue.progress.entry(remoteCell).symbol, puzzle.solution[remoteCell]);
    final grid = tester.widget<PuzzleGrid>(find.byType(PuzzleGrid));
    expect(grid.remoteTints.keys, contains(remoteCell));
    expect(fake.calls.where((c) => c == 'writeCell'), isEmpty, reason: 'remote letters are not echoed back');

    // Our own letter is written to cells/{index}; the cursor is published.
    final mine = cells.first;
    controller.tapCell(mine);
    controller.typeSymbol(puzzle.solution[mine]);
    await tester.pump();
    expect(fake.cells[room.id]![mine]?.symbol, puzzle.solution[mine]);
    expect(fake.cells[room.id]![mine]?.by, 'me');
    expect(fake.rooms[room.id]!.members['me']!.cursor, isNotNull);

    // Another member's cursor is drawn.
    fake.simulateRemoteCursor(room.id, cells[1]);
    await tester.pump();
    await tester.pump();
    expect(tester.widget<PuzzleGrid>(find.byType(PuzzleGrid)).remoteCursors.keys, contains(cells[1]));

    // Fill the rest together (half remote, half local).
    var k = 0;
    for (final i in cells) {
      if (container.read(puzzleSessionProvider(sessionId)).requireValue.progress.entry(i).isLocked) continue;
      if ((k++).isEven) {
        fake.simulateRemoteCell(room.id, i, puzzle.solution[i]);
      } else {
        controller.tapCell(i);
        controller.typeSymbol(puzzle.solution[i]);
      }
      clock.advance(const Duration(seconds: 2));
      await tester.pump();
    }
    expect(container.read(puzzleSessionProvider(sessionId)).requireValue.isComplete, isTrue);
    await tester.pump();
    expect(find.text('כל הכבוד'), findsNothing, reason: 'no solo sheet in co-op');
    expect(find.text('הרשת מלאה — המארח יכול לסיים'), findsOneWidget);
    await tester.tap(find.text('סיימנו'));
    await settle(tester);
    expect(fake.calls, contains('finishCoopRoom'));
    expect(find.text('התשחץ הושלם יחד!'), findsOneWidget);
    expect(find.text('פרס לכל אחד: +25 מטבעות · +30 XP'), findsOneWidget);
    expect(container.read(xpProvider), XpCurve.coopXp);
    await tester.tap(find.text('משחק משותף'));
    await settle(tester);
    expect(find.byType(PuzzleScreen), findsNothing);
  });

  testWidgets('guest joins by code, waits for the host, leaves with confirmation', (tester) async {
    final (fake, _) = await pumpApp(tester);
    final hosted = fake.simulateHostedRoom(code: 'JOIN42');
    await tester.tap(find.text('הצטרפות לחדר'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'join-42');
    await tester.tap(find.text('הצטרפות'));
    await settle(tester);
    expect(find.byType(RoomLobbyScreen), findsOneWidget);
    expect(find.text('מחכים שהמארח יתחיל'), findsOneWidget);
    expect(fake.rooms[hosted.id]!.members.containsKey('me'), isTrue);

    fake.simulateHostStartRoom(hosted.id);
    await settle(tester);
    await pumpUntilFound(tester, find.byType(PuzzleKeyboard));
    expect(find.text('סיימנו'), findsNothing, reason: 'only the host finishes');
    await tester.tap(find.byTooltip('חזרה'));
    await settle(tester);
    expect(find.text('לצאת מהחדר? אפשר לחזור עם הקוד.'), findsOneWidget);
    await tester.tap(find.text('יציאה'));
    await settle(tester);
    expect(fake.calls, contains('leaveCoopRoom'));
    expect(fake.rooms[hosted.id]!.members.containsKey('me'), isFalse);
    expect(find.text('משחק משותף'), findsOneWidget);
  });
}
