import 'package:chetz_app/core/content/content_source.dart';
import 'package:chetz_app/core/providers.dart';
import 'package:chetz_app/features/leaderboard/leaderboard_screen.dart';
import 'package:chetz_app/features/leaderboard/leaderboard_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  testWidgets('disabled service shows a friendly empty state', (tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(wrapScreen(
      const LeaderboardScreen(lang: 'he', date: '2026-10-29'),
      overrides: testOverrides(content: MapContentSource()),
    ));
    await tester.pumpAndSettle();
    expect(find.text('לוח התוצאות זמין כשמחוברים לחשבון ולרשת'), findsOneWidget);
  });

  testWidgets('top entries and the player rank render', (tester) async {
    usePhoneSurface(tester);
    final page = LeaderboardPage(
      entries: [
        const LeaderboardEntry(uid: 'a', score: 100, elapsedMs: 95000, displayName: 'דנה', rank: 1),
        const LeaderboardEntry(uid: 'b', score: 120, elapsedMs: 118000, displayName: 'יוסי', rank: 2, hints: 1),
        const LeaderboardEntry(uid: 'c', score: 200, elapsedMs: 200000, rank: 3),
      ],
      me: const LeaderboardEntry(uid: 'me', score: 900, elapsedMs: 880000, displayName: 'אני-בדיקה', rank: 57),
      total: 120,
    );
    await tester.pumpWidget(wrapScreen(
      const LeaderboardScreen(lang: 'he', date: '2026-10-29'),
      overrides: testOverrides(
        content: MapContentSource(),
        extra: [leaderboardServiceProvider.overrideWithValue(FakeLeaderboardService(page: page))],
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('לוח התוצאות'), findsWidgets);
    expect(find.text('דנה'), findsOneWidget);
    expect(find.text('יוסי'), findsOneWidget);
    expect(find.text('פותר/ת'), findsOneWidget, reason: 'anonymous entry gets the default name');
    expect(find.textContaining('אני-בדיקה'), findsOneWidget);
    expect(find.textContaining('מקום 57'), findsOneWidget);
    expect(find.textContaining('מתוך 120'), findsOneWidget);
    expect(find.text('1:35'), findsOneWidget);
  });

  testWidgets('empty board', (tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(wrapScreen(
      const LeaderboardScreen(lang: 'he', date: '2026-10-29'),
      overrides: testOverrides(
        content: MapContentSource(),
        extra: [leaderboardServiceProvider.overrideWithValue(FakeLeaderboardService(page: const LeaderboardPage(entries: [])))],
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('עוד אין תוצאות ליום זה'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });
}
