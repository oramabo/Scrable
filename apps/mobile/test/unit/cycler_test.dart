import 'package:chetz_app/core/content/content_source.dart';
import 'package:chetz_app/features/meta/game_events_controller.dart';
import 'package:chetz_app/features/puzzle/application/alphabet_cycler.dart';
import 'package:chetz_app/features/puzzle/application/puzzle_controller.dart';
import 'package:chetz_app/features/puzzle/application/puzzle_session.dart';
import 'package:chetz_core/chetz_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  late MapContentSource content;
  setUpAll(() async => content = await loadBundledContent());

  group('AlphabetCycler rules', () {
    test('alphabet order skips geresh variants (Hebrew) and wraps', () {
      final he = AlphabetCycler.alphabet(Languages.he);
      expect(he.length, 22);
      expect(he.first, 0);
      expect(AlphabetCycler.next(Languages.he, null), 0);
      expect(AlphabetCycler.next(Languages.he, 0), 1);
      expect(AlphabetCycler.next(Languages.he, 21), 0);
      // From a geresh variant, continue after its base letter.
      expect(AlphabetCycler.next(Languages.he, 22), Languages.he.baseSymbol(22) + 1);
      expect(AlphabetCycler.alphabet(Languages.en).length, 26);
      expect(AlphabetCycler.next(Languages.en, 25), 0);
    });
  });

  group('cycler in a session', () {
    const id = 'he-l1-p01-01';

    Future<(ProviderContainer, PuzzleController, PuzzleSession)> load() async {
      final container = ProviderContainer(overrides: testOverrides(content: content));
      addTearDown(container.dispose);
      final sub = container.listen(puzzleSessionProvider(id), (_, _) {});
      addTearDown(sub.close);
      final session = await container.read(puzzleSessionProvider(id).future);
      return (container, container.read(puzzleSessionProvider(id).notifier), session);
    }

    test('target appears only when one cell of the word is left', () async {
      final (container, controller, s0) = await load();
      final word = s0.activeWord!;
      final cells = word.cells.map(s0.puzzle.shape.indexOf).toList();
      expect(controller.cyclerTarget(), isNull, reason: 'empty word: more than one cell left');
      for (final c in cells.take(cells.length - 1)) {
        controller.tapCell(c);
        controller.typeSymbol(s0.puzzle.solution[c]);
      }
      final s1 = container.read(puzzleSessionProvider(id)).requireValue;
      expect(s1.selection!.wordId, word.id);
      expect(controller.cyclerTarget(), cells.last);
      expect(AlphabetCycler.targetCell(s1.puzzle, word, s1.progress), cells.last);
    });

    test('cycling writes pencil previews in alphabet order without evaluating; confirm locks in', () async {
      final (container, controller, s0) = await load();
      final word = s0.activeWord!;
      final cells = word.cells.map(s0.puzzle.shape.indexOf).toList();
      for (final c in cells.take(cells.length - 1)) {
        controller.tapCell(c);
        controller.typeSymbol(s0.puzzle.solution[c]);
      }
      final target = cells.last;
      final usesBefore = container.read(playerStatsProvider).alphabetCyclerUses;

      controller.cycleNext();
      var s = container.read(puzzleSessionProvider(id)).requireValue;
      expect(s.isCycling, isTrue);
      expect(s.cyclerCell, target);
      expect(s.progress.entry(target).symbol, 0, reason: 'א first');
      expect(s.progress.entry(target).pencil, isTrue);
      expect(s.progress.entry(target).status, CellStatus.filled, reason: 'no evaluation while cycling');
      expect(s.feedback?.kind, isNot(FeedbackKind.wordWrong));
      expect(container.read(playerStatsProvider).alphabetCyclerUses, usesBefore + 1, reason: 'one event per cycling session');

      controller.cycleNext();
      controller.cycleNext();
      s = container.read(puzzleSessionProvider(id)).requireValue;
      expect(s.progress.entry(target).symbol, 2);
      expect(container.read(playerStatsProvider).alphabetCyclerUses, usesBefore + 1);

      // Run until the solution letter, then confirm → normal-mode evaluation.
      final solution = s.puzzle.solution[target];
      var guard = 0;
      while (container.read(puzzleSessionProvider(id)).requireValue.cyclerSymbol != solution && guard++ < 30) {
        controller.cycleNext();
      }
      controller.confirmCycler();
      s = container.read(puzzleSessionProvider(id)).requireValue;
      expect(s.isCycling, isFalse);
      expect(s.progress.entry(target).pencil, isFalse);
      expect(s.progress.entry(target).status, CellStatus.confirmedCorrect);
      expect(s.feedback?.kind, FeedbackKind.wordCorrect);
    });

    test('tapping the cycler cell confirms; a normal key press types over the preview; cancel restores', () async {
      final (container, controller, s0) = await load();
      final word = s0.activeWord!;
      final cells = word.cells.map(s0.puzzle.shape.indexOf).toList();
      for (final c in cells.take(cells.length - 1)) {
        controller.tapCell(c);
        controller.typeSymbol(s0.puzzle.solution[c]);
      }
      final target = cells.last;
      controller.cycleNext();
      controller.cancelCycler();
      var s = container.read(puzzleSessionProvider(id)).requireValue;
      expect(s.isCycling, isFalse);
      expect(s.progress.entry(target).isEmpty, isTrue, reason: 'preview removed');

      controller.cycleNext();
      controller.tapCell(target);
      s = container.read(puzzleSessionProvider(id)).requireValue;
      expect(s.isCycling, isFalse);
      expect(s.progress.entry(target).symbol, 0);
      expect(s.progress.entry(target).pencil, isFalse, reason: 'tap on the cell locks the letter');

      // Reset the cell and type a normal key while cycling.
      controller.tapCell(target);
      controller.backspace();
      controller.cycleNext();
      controller.typeSymbol(s0.puzzle.solution[target]);
      s = container.read(puzzleSessionProvider(id)).requireValue;
      expect(s.isCycling, isFalse);
      expect(s.progress.entry(target).symbol, s0.puzzle.solution[target]);
    });

    test('relaxed mode: previews are not checked until confirmed', () async {
      final (container, controller, s0) = await load();
      controller.setMode(PlayMode.relaxed);
      final word = s0.activeWord!;
      final cells = word.cells.map(s0.puzzle.shape.indexOf).toList();
      for (final c in cells.take(cells.length - 1)) {
        controller.tapCell(c);
        controller.typeSymbol(s0.puzzle.solution[c]);
      }
      final target = cells.last;
      controller.cycleNext();
      var s = container.read(puzzleSessionProvider(id)).requireValue;
      expect(s.progress.entry(target).status, CellStatus.filled);
      expect(s.progress.wrongEntries, 0);
      controller.confirmCycler();
      s = container.read(puzzleSessionProvider(id)).requireValue;
      expect(s.progress.entry(target).status, anyOf(CellStatus.confirmedCorrect, CellStatus.markedWrong));
    });
  });
}
