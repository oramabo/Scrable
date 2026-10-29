import 'dart:ui' as ui;

import 'package:chetz_app/core/content/clue_image_store.dart';
import 'package:chetz_app/core/content/content_source.dart';
import 'package:chetz_app/core/providers.dart';
import 'package:chetz_app/features/meta/image_credits.dart';
import 'package:chetz_app/features/puzzle/application/puzzle_controller.dart';
import 'package:chetz_app/features/puzzle/presentation/keyboard/puzzle_keyboard.dart';
import 'package:chetz_app/features/puzzle/presentation/picture_clue.dart';
import 'package:chetz_app/features/puzzle/presentation/puzzle_screen.dart';
import 'package:chetz_app/features/settings/about_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  late MapContentSource content;
  setUpAll(() async => content = await loadPictureFixture());

  const id = 'he-pic-01';

  /// The engine decoder needs the real event loop; the widget test injects a
  /// synchronous decoder (a 16×16 teal square) so everything resolves inside
  /// FakeAsync. Byte resolution (bundled → cache → CDN) is still exercised.
  Future<ui.Image> fakeDecode(Uint8List bytes) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 16, 16), Paint()..color = const Color(0xFF1F8A8A));
    return recorder.endRecording().toImageSync(16, 16);
  }

  Future<ClueImageStore> primedStore(WidgetTester tester) async {
    final store = ClueImageStore(bundled: content, decode: fakeDecode);
    final image = store.image('he', 'images/test.png');
    await tester.pump();
    expect(await image, isNotNull);
    return store;
  }

  testWidgets('picture clue: image resolves from bundled assets, shows in the clue bar, credits are collected', (tester) async {
    usePhoneSurface(tester);
    final store = await primedStore(tester);
    final overrides = testOverrides(content: content, extra: [clueImageStoreProvider.overrideWith((ref, lang) => store)]);
    await tester.pumpWidget(wrapScreen(const PuzzleScreen(puzzleId: id), overrides: overrides));
    await pumpUntilFound(tester, find.byType(PuzzleKeyboard));
    final container = ProviderScope.containerOf(tester.element(find.byType(PuzzleScreen)));
    final controller = container.read(puzzleSessionProvider(id).notifier);
    final session = container.read(puzzleSessionProvider(id)).requireValue;

    // The fixture has exactly one picture slot.
    final slot = session.puzzle.clueCells.expand((c) => c.slots).firstWhere((s) => s.isPicture);
    expect(slot.lines, isEmpty);
    expect(slot.image!.src, 'images/test.png');

    expect(store.imageIfLoaded('he', 'images/test.png'), isNotNull);
    expect(store.imageIfLoaded('he', 'images/test.png')!.width, 16);
    expect(store.bytesIfLoaded('he', 'images/test.png'), isNotNull);
    expect(store.isMissing('he', 'images/nope.png'), isFalse);
    final missing = store.bytes('he', 'images/nope.png');
    await tester.pump();
    expect(await missing, isNull);
    expect(store.isMissing('he', 'images/nope.png'), isTrue, reason: 'missing images fall back to the text hint');

    // Select the picture word: the clue bar shows the picture plus the hint.
    controller.selectWord(slot.wordId);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(PictureClueImage), findsOneWidget);
    expect(find.text('תמונה לדוגמה'), findsWidgets);

    // Credits were collected when the puzzle loaded.
    final credits = container.read(imageCreditsProvider);
    expect(credits.length, 1);
    expect(credits.single.credit, 'Test Author');
    expect(credits.single.license, 'CC0');
    expect(credits.single.puzzleId, id);
  });

  testWidgets('About lists image credits of puzzles seen', (tester) async {
    usePhoneSurface(tester);
    final store = await primedStore(tester);
    final overrides = testOverrides(content: content, extra: [clueImageStoreProvider.overrideWith((ref, lang) => store)]);
    await tester.pumpWidget(wrapScreen(const PuzzleScreen(puzzleId: id), overrides: overrides));
    await pumpUntilFound(tester, find.byType(PuzzleKeyboard));
    final container = ProviderScope.containerOf(tester.element(find.byType(PuzzleScreen)));
    expect(container.read(imageCreditsProvider), isNotEmpty);
    // Navigate to About inside the same app (same ProviderScope).
    Navigator.of(tester.element(find.byType(PuzzleScreen))).push(MaterialPageRoute<void>(builder: (_) => const AboutScreen()));
    await tester.pumpAndSettle();
    expect(find.text('קרדיט תמונות'), findsOneWidget);
    expect(find.text('Test Author · CC0'), findsOneWidget);
  });
}
