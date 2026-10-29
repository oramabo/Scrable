import 'package:chetz_app/core/content/content_source.dart';
import 'package:chetz_app/core/storage/json_store.dart';
import 'package:chetz_app/features/puzzle/application/puzzle_controller.dart';
import 'package:chetz_app/features/puzzle/presentation/keyboard/puzzle_keyboard.dart';
import 'package:chetz_app/features/puzzle/presentation/puzzle_screen.dart';
import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

/// Regression: autosave used to run from the controller's `onDispose`, where
/// Riverpod forbids using `ref` ("Cannot use Ref or modify other providers
/// inside life-cycles/selectors"), so the final save failed silently.
void main() {
  late MapContentSource content;
  setUpAll(() async => content = await loadBundledContent());

  const id = 'he-l1-p01-04';

  testWidgets('leaving the screen flushes the autosave without touching Ref', (tester) async {
    usePhoneSurface(tester);
    final log = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) log.add(message);
    };

    final store = MemoryJsonStore();
    await tester.pumpWidget(wrapScreen(const PuzzleScreen(puzzleId: id), overrides: testOverrides(content: content, store: store)));
    await pumpUntilFound(tester, find.byType(PuzzleKeyboard));
    final container = ProviderScope.containerOf(tester.element(find.byType(PuzzleScreen)));
    final controller = container.read(puzzleSessionProvider(id).notifier);
    final session = container.read(puzzleSessionProvider(id)).requireValue;
    final cell = session.selection!.cell;
    final symbol = session.puzzle.solution[cell];
    controller.typeSymbol(symbol);
    await tester.pump(); // debounce (500 ms) has NOT elapsed: the save is pending

    // Dispose the screen (and the autoDispose controller) immediately.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    debugPrint = original;
    expect(log.where((m) => m.contains('progress save failed')), isEmpty, reason: 'no Ref use inside onDispose');
    expect(log.where((m) => m.contains('Cannot use Ref')), isEmpty);
    final saved = await store.read('progress/$id');
    expect(saved, isNotNull, reason: 'the pending autosave was flushed on dispose');
    final progress = PuzzleProgress.fromJson(saved!);
    expect(progress.entry(cell).symbol, symbol);
  });

  testWidgets('completing a puzzle and disposing the screen saves the completed state cleanly', (tester) async {
    usePhoneSurface(tester);
    final log = <String>[];
    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) log.add(message);
    };

    final store = MemoryJsonStore();
    const pid = 'he-l1-p01-05';
    await tester.pumpWidget(wrapScreen(const PuzzleScreen(puzzleId: pid), overrides: testOverrides(content: content, store: store)));
    await pumpUntilFound(tester, find.byType(PuzzleKeyboard));
    final container = ProviderScope.containerOf(tester.element(find.byType(PuzzleScreen)));
    final controller = container.read(puzzleSessionProvider(pid).notifier);
    var session = container.read(puzzleSessionProvider(pid)).requireValue;
    for (final i in session.puzzle.letterCellIndices) {
      if (container.read(puzzleSessionProvider(pid)).requireValue.progress.entry(i).isLocked) continue;
      controller.tapCell(i);
      controller.typeSymbol(session.puzzle.solution[i]);
    }
    session = container.read(puzzleSessionProvider(pid)).requireValue;
    expect(session.isComplete, isTrue);
    await tester.pump();
    // Dispose mid-celebration, before the completion sheet appears.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));

    debugPrint = original;
    expect(log.where((m) => m.contains('progress save failed')), isEmpty);
    expect(log.where((m) => m.contains('Cannot use Ref')), isEmpty);
    final saved = PuzzleProgress.fromJson((await store.read('progress/$pid'))!);
    expect(saved.completed, isTrue);
    expect(saved.stars, greaterThan(0));
  });
}
