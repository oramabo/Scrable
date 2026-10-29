import 'dart:async';

import 'package:chetz_app/app.dart';
import 'package:chetz_app/core/content/content_source.dart';
import 'package:chetz_app/core/router.dart';
import 'package:chetz_app/core/storage/json_store.dart';
import 'package:chetz_app/features/home/home_shell.dart';
import 'package:chetz_app/features/packs/packs_providers.dart';
import 'package:chetz_app/features/puzzle/application/puzzle_controller.dart';
import 'package:chetz_app/features/puzzle/presentation/keyboard/puzzle_keyboard.dart';
import 'package:chetz_app/features/puzzle/presentation/puzzle_screen.dart';
import 'package:chetz_app/features/random/random_puzzle_generator.dart';
import 'package:chetz_app/features/settings/settings_controller.dart';
import 'package:chetz_app/features/settings/settings_model.dart';
import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  late MapContentSource content;
  final cache = <String, MapContentSource>{};

  setUpAll(() async {
    content = await loadBundledContent();
    cache['en'] = await loadBundledContent(lang: 'en');
    cache['he+device'] = await loadBundledContent(device: true);
  });

  // Content is read from disk in setUpAll only (never inside FakeAsync).
  Future<MapContentSource> loadBundledContentOnce(String lang, {bool device = false}) async => cache[device ? '$lang+device' : lang]!;

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
    expect(find.textContaining('Coming soon'), findsNothing, reason: 'English puzzles are bundled');
    expect(find.text('Start your first puzzle'), findsOneWidget, reason: 'empty continue → single primary CTA');
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('Daily Arrowword'), 200, scrollable: list);
    expect(find.textContaining('Resets in '), findsWidgets, reason: 'locale-aware countdown ("in 12 h")');
    expect(find.textContaining('h 00m'), findsNothing);
  });

  testWidgets('greeting carries the player name; the first-puzzle CTA opens pack 1 puzzle 1', (tester) async {
    usePhoneSurface(tester);
    HomeTab.debugResetLoginBonus();
    final store = MemoryJsonStore();
    await store.write('profile', {'displayName': 'דנה', 'avatarId': 'fox', 'updatedAt': 1});
    await tester.pumpWidget(
      ProviderScope(
        overrides: testOverrides(content: content, store: store, settings: const AppSettings(onboardingDone: true, tutorialDone: true)),
        child: const ChetzApp(),
      ),
    );
    await pumpUntilFound(tester, find.byType(HomeTab));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('שלום, דנה!'), findsOneWidget);
    expect(find.textContaining('בעוד'), findsWidgets, reason: 'Hebrew countdown ("בעוד 12 שעות")');
    expect(find.textContaining('12h'), findsNothing);
    // Login bonus toast is a readable one-liner (explicit colours), not an empty bar.
    expect(find.textContaining('בונוס יומי: +10 מטבעות'), findsOneWidget);
    await tester.tap(find.text('התחילו את התשחץ הראשון'));
    await tester.pumpAndSettle();
    expect(find.byType(PuzzleScreen), findsOneWidget);
    expect(tester.widget<PuzzleScreen>(find.byType(PuzzleScreen)).puzzleId, 'he-l1-p01-01');
  });

  testWidgets('switching the puzzle language to English swaps the catalogue while the UI stays Hebrew/RTL', (tester) async {
    usePhoneSurface(tester);
    final en = await loadBundledContentOnce('en');
    final merged = MapContentSource({...content.docs, ...en.docs});
    await tester.pumpWidget(
      ProviderScope(
        overrides: testOverrides(content: merged, settings: const AppSettings(onboardingDone: true, tutorialDone: true)),
        child: const ChetzApp(),
      ),
    );
    await pumpUntilFound(tester, find.byType(HomeTab));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.descendant(of: find.byType(SegmentedButton<String>), matching: find.text('English')));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeTab)));
    expect(container.read(settingsProvider).puzzleLang, 'en');
    expect(container.read(settingsProvider).uiLang, 'he');
    expect(Directionality.of(tester.element(find.byType(HomeTab))), TextDirection.rtl);
    final packs = await container.read(packsProvider.future);
    expect(packs.every((p) => p.id.startsWith('en-')), isTrue, reason: 'English catalogue');
    expect(find.text('English: בקרוב'), findsNothing);
    await tester.tap(find.text('התחילו את התשחץ הראשון'));
    await tester.pumpAndSettle();
    await pumpUntilFound(tester, find.byType(PuzzleKeyboard));
    final screen = tester.widget<PuzzleScreen>(find.byType(PuzzleScreen));
    expect(screen.puzzleId, 'en-l1-p01-01');
    // Grid + keyboard follow the puzzle language (LTR) inside the RTL chrome.
    expect(Directionality.of(tester.element(find.byType(PuzzleKeyboard))), TextDirection.ltr);
    expect(find.text('A→Z'), findsNothing); // cycler only appears when one cell is left
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

  testWidgets('random puzzle shows a progress dialog while generating and a toast when it fails', (tester) async {
    usePhoneSurface(tester);
    final slow = _SlowGenerator();
    await tester.pumpWidget(
      ProviderScope(
        overrides: testOverrides(content: content, generator: slow, settings: const AppSettings(onboardingDone: true, tutorialDone: true)),
        child: const ChetzApp(),
      ),
    );
    await pumpUntilFound(tester, find.byType(HomeTab));
    await tester.pump(const Duration(milliseconds: 300));
    final list = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.textContaining('עונה 1'), 200, scrollable: list);
    await tester.ensureVisible(find.text('תשחץ אקראי'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('תשחץ אקראי'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('רמה 3 ·').last);
    await settle(tester);
    expect(find.text('מכינים תשחץ…'), findsOneWidget, reason: 'progress dialog while the generator runs');
    expect(slow.requests.single, (lang: 'he', level: 3));
    slow.fail(const RandomPuzzleException('boom'));
    await tester.pumpAndSettle();
    expect(find.text('מכינים תשחץ…'), findsNothing);
    expect(find.textContaining('לא הצלחנו להכין תשחץ'), findsOneWidget);
    expect(find.byType(PuzzleScreen), findsNothing);
  });

  testWidgets('random puzzle: level sheet → on-device generation → unranked puzzle, listed under "random"', (tester) async {
    usePhoneSurface(tester);
    final withDevice = await loadBundledContentOnce('he', device: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: testOverrides(content: withDevice, settings: const AppSettings(onboardingDone: true, tutorialDone: true)),
        child: const ChetzApp(),
      ),
    );
    await pumpUntilFound(tester, find.byType(HomeTab));
    await tester.pump(const Duration(milliseconds: 300));
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
    expect(find.byType(PuzzleScreen), findsOneWidget);
    final screen = tester.widget<PuzzleScreen>(find.byType(PuzzleScreen));
    expect(screen.puzzleId, startsWith('he-random-'));
    await pumpUntilFound(tester, find.byType(PuzzleKeyboard));
    expect(find.text('תשחץ אקראי · מתחילים'), findsOneWidget);
    // Back home: the "random" section lists it.
    final container = ProviderScope.containerOf(tester.element(find.byType(PuzzleScreen)));
    await container.read(puzzleSessionProvider(screen.puzzleId).notifier).flush();
    container.read(routerProvider).go('/');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('אקראיים'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('אקראיים'), findsOneWidget);
    expect(find.textContaining('לא מדורג'), findsWidgets);
  });
}

/// A generator that stays busy until the test completes or fails it.
class _SlowGenerator implements RandomPuzzleGenerator {
  final requests = <({String lang, int level})>[];
  Completer<Puzzle>? _pending;

  @override
  Future<Puzzle> generate({required String lang, required int level, String? seed, String? id}) {
    requests.add((lang: lang, level: level));
    return (_pending = Completer<Puzzle>()).future;
  }

  void fail(Object error) => _pending?.completeError(error);

  @override
  void dispose() {}
}
