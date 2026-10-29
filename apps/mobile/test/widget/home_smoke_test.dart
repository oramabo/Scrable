import 'package:chetz_app/app.dart';
import 'package:chetz_app/core/content/content_source.dart';
import 'package:chetz_app/features/home/home_shell.dart';
import 'package:chetz_app/features/settings/settings_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  late MapContentSource content;

  setUpAll(() async {
    content = await loadBundledContent();
  });

  Future<void> pumpApp(WidgetTester tester, String uiLang) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: testOverrides(
          content: content,
          settings: AppSettings(uiLang: uiLang, onboardingDone: true, tutorialDone: true),
        ),
        child: const ChetzApp(),
      ),
    );
    await pumpUntilFound(tester, find.byType(HomeTab));
    await tester.pump(const Duration(milliseconds: 300));
  }

  testWidgets('home renders in Hebrew (RTL) with the UX §3/§6 surfaces', (tester) async {
    await pumpApp(tester, 'he');
    expect(find.text('חץ'), findsWidgets);
    expect(find.text('שלום!'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
    // Four tabs: Play · Daily · Together · Me.
    for (final tab in ['משחק', 'יומי', 'מולטי', 'אני']) {
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)), findsOneWidget);
    }
    expect(Directionality.of(tester.element(find.byType(HomeTab))), TextDirection.rtl);
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('התשחץ היומי'), 200, scrollable: list);
    expect(find.text('האתגר היומי'), findsWidgets);
    await tester.scrollUntilVisible(find.byType(MissionsStrip), 200, scrollable: list);
    expect(find.text('משימות'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('רמה 1 · מתחילים'), 200, scrollable: list);
    expect(find.textContaining('רמה 1'), findsWidgets);
    await tester.scrollUntilVisible(find.text('תשחץ אקראי'), 200, scrollable: list);
    await tester.scrollUntilVisible(find.textContaining('עונה 1'), 200, scrollable: list);
    expect(find.textContaining('עונה 1'), findsOneWidget, reason: 'season teaser placeholder');
  });

  testWidgets('home renders in English (LTR) with Hebrew puzzle content', (tester) async {
    await pumpApp(tester, 'en');
    expect(find.text('Chetz'), findsWidgets);
    expect(find.text('Hello!'), findsOneWidget);
    for (final tab in ['Play', 'Daily', 'Together', 'Me']) {
      expect(find.descendant(of: find.byType(NavigationBar), matching: find.text(tab)), findsOneWidget);
    }
    expect(Directionality.of(tester.element(find.byType(HomeTab))), TextDirection.ltr);
    expect(find.textContaining('Coming soon'), findsWidgets, reason: 'English puzzles missing in the test content');
  });

  testWidgets('bottom navigation switches tabs; Me opens settings', (tester) async {
    await pumpApp(tester, 'he');
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('יומי')));
    await tester.pumpAndSettle();
    expect(find.text('תשחצים יומיים'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('מולטי')));
    await tester.pumpAndSettle();
    expect(find.text('משחק משותף'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('אני')));
    await tester.pumpAndSettle();
    expect(find.text('פותר/ת'), findsOneWidget, reason: 'default display name');
    expect(find.textContaining('טירון'), findsWidgets, reason: 'starting rank');
    await tester.tap(find.byTooltip('הגדרות'));
    await tester.pumpAndSettle();
    expect(find.text('שפת הממשק'), findsOneWidget);
  });

  testWidgets('random puzzle button opens the level sheet and starts a puzzle', (tester) async {
    await pumpApp(tester, 'he');
    final list = find.byType(Scrollable).first;
    // Scroll past the button so it is not under the navigation bar.
    await tester.scrollUntilVisible(find.textContaining('עונה 1'), 200, scrollable: list);
    await tester.ensureVisible(find.text('תשחץ אקראי'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('תשחץ אקראי'));
    await tester.pumpAndSettle();
    expect(find.text('בחירת רמה'), findsOneWidget);
    await tester.tap(find.textContaining('רמה 1 ·').last);
    await tester.pumpAndSettle();
    expect(find.text('בחירת רמה'), findsNothing);
  });
}
