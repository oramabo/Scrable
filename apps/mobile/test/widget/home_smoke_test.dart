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

  testWidgets('home renders in Hebrew (RTL)', (tester) async {
    await pumpApp(tester, 'he');
    expect(find.text('חץ'), findsWidgets);
    expect(find.text('שלום!'), findsOneWidget);
    expect(find.text('התשחץ היומי'), findsWidgets);
    expect(find.text('האתגר היומי'), findsWidgets);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('הגדרות'), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(HomeTab))), TextDirection.rtl);
    // Level cards for all five levels (further down the list).
    await tester.scrollUntilVisible(find.textContaining('רמה 5'), 200, scrollable: find.byType(Scrollable).first);
    for (var l = 1; l <= 5; l++) {
      expect(find.textContaining('רמה $l'), findsWidgets);
    }
  });

  testWidgets('home renders in English (LTR) with Hebrew puzzle content', (tester) async {
    await pumpApp(tester, 'en');
    expect(find.text('Chetz'), findsWidgets);
    expect(find.text('Hello!'), findsOneWidget);
    expect(find.text('Daily Arrowword'), findsWidgets);
    expect(find.text('Daily Challenge'), findsWidgets);
    expect(find.text('Settings'), findsOneWidget);
    expect(Directionality.of(tester.element(find.byType(HomeTab))), TextDirection.ltr);
    // English puzzles have no content yet → "coming soon" marker on the switcher.
    expect(find.textContaining('Coming soon'), findsWidgets);
  });

  testWidgets('bottom navigation switches tabs', (tester) async {
    await pumpApp(tester, 'he');
    await tester.tap(find.text('הגדרות'));
    await tester.pumpAndSettle();
    expect(find.text('שפת הממשק'), findsOneWidget);
    await tester.tap(find.text('יומי'));
    await tester.pumpAndSettle();
    expect(find.text('תשחצים יומיים'), findsOneWidget);
  });
}
