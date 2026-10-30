import 'package:chetz_app/core/config/game_config.dart';
import 'package:chetz_app/core/content/content_source.dart';
import 'package:chetz_app/features/puzzle/application/puzzle_controller.dart';
import 'package:chetz_app/features/puzzle/presentation/clue_bar.dart';
import 'package:chetz_app/features/puzzle/presentation/keyboard/puzzle_keyboard.dart';
import 'package:chetz_app/features/puzzle/presentation/keyboard/system_keyboard_input.dart';
import 'package:chetz_app/features/settings/settings_model.dart';
import 'package:chetz_app/features/puzzle/presentation/puzzle_screen.dart';
import 'package:chetz_core/chetz_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  late MapContentSource content;

  setUpAll(() async {
    content = await loadBundledContent();
  });

  const puzzleId = tutorialPuzzleId; // he-l1-p01-01, bundled

  Future<ProviderContainer> pumpPuzzle(WidgetTester tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(wrapScreen(const PuzzleScreen(puzzleId: puzzleId), overrides: testOverrides(content: content)));
    await pumpUntilFound(tester, find.byType(PuzzleKeyboard));
    return ProviderScope.containerOf(tester.element(find.byType(PuzzleScreen)));
  }

  testWidgets('loads the bundled puzzle and shows the active clue', (tester) async {
    final container = await pumpPuzzle(tester);
    final session = container.read(puzzleSessionProvider(puzzleId)).requireValue;
    expect(session.puzzle.id, puzzleId);
    expect(session.puzzle.lang, 'he');
    final word = session.activeWord!;
    expect(find.text(session.puzzle.clueTextOf(word.id)), findsWidgets);
    // The word preview shows one box per cell of the word.
    expect(find.descendant(of: find.byType(WordPreview), matching: find.byType(AnimatedContainer)), findsNWidgets(word.len));
    // The grid, clue bar and keyboard are RTL for Hebrew puzzles.
    expect(Directionality.of(tester.element(find.byType(PuzzleKeyboard))), TextDirection.rtl);
  });

  testWidgets('typing through the keyboard fills the grid and advances the cursor', (tester) async {
    final semantics = tester.ensureSemantics();
    final container = await pumpPuzzle(tester);
    var session = container.read(puzzleSessionProvider(puzzleId)).requireValue;
    final sel = session.selection!;
    final word = session.puzzle.wordById[sel.wordId]!;
    final firstCell = sel.cell;
    final symbol = session.puzzle.solution[firstCell];
    final label = session.lang.symbolToDisplay(symbol);

    await tester.tap(find.descendant(of: find.byType(PuzzleKeyboard), matching: find.text(label)));
    await tester.pump();

    session = container.read(puzzleSessionProvider(puzzleId)).requireValue;
    expect(session.progress.entry(firstCell).symbol, symbol);
    expect(session.progress.entry(firstCell).status, CellStatus.filled, reason: 'normal mode: no per-letter feedback');
    expect(session.selection!.cell, isNot(firstCell));
    expect(session.selection!.wordId, word.id);
    // The clue bar's word preview now starts with the letter.
    final pattern = session.patternOf(word);
    expect(pattern.split(' ').first, session.displayAt(firstCell));
    expect(find.descendant(of: find.byType(WordPreview), matching: find.text(label)), findsWidgets);

    // Tapping a preview box moves the cursor inside the same word.
    await tester.tap(find.descendant(of: find.byType(WordPreview), matching: find.byKey(ValueKey(firstCell))));
    await tester.pump();
    session = container.read(puzzleSessionProvider(puzzleId)).requireValue;
    expect(session.selection, Selection(wordId: word.id, cell: firstCell));

    // Backspace moves back and clears it.
    await tester.tap(find.bySemanticsLabel('מחיקה'));
    await tester.pump();
    session = container.read(puzzleSessionProvider(puzzleId)).requireValue;
    expect(session.progress.entry(firstCell).isEmpty, isTrue);
    expect(session.selection!.cell, firstCell);
    semantics.dispose();
  });

  testWidgets('completing a word in normal mode confirms it; a wrong word is not pinpointed', (tester) async {
    final container = await pumpPuzzle(tester);
    final controller = container.read(puzzleSessionProvider(puzzleId).notifier);
    var session = container.read(puzzleSessionProvider(puzzleId)).requireValue;
    final word = session.activeWord!;
    final cells = word.cells.map(session.puzzle.shape.indexOf).toList();

    // Wrong: type a letter different from the solution in the first cell, then the right ones.
    final wrongSymbol = (session.puzzle.solution[cells.first] + 1) % 22;
    controller.typeSymbol(wrongSymbol);
    for (final c in cells.skip(1)) {
      controller.typeSymbol(session.puzzle.solution[c]);
    }
    await tester.pump();
    session = container.read(puzzleSessionProvider(puzzleId)).requireValue;
    expect(session.feedback?.wordId, word.id);
    expect(session.progress.entry(cells.first).status, CellStatus.filled, reason: 'no pinpointing');

    // Fix it.
    controller.clearWord(word.id);
    controller.selectWord(word.id);
    for (final c in cells) {
      controller.typeSymbol(session.puzzle.solution[c]);
    }
    await tester.pump();
    session = container.read(puzzleSessionProvider(puzzleId)).requireValue;
    for (final c in cells) {
      expect(session.progress.entry(c).status, CellStatus.confirmedCorrect);
      expect(session.progress.entry(c).isLocked, isTrue);
    }
    // Auto-advanced to another incomplete word.
    expect(session.selection!.wordId, isNot(word.id));
  });

  testWidgets('a free hint reveals the cursor letter without spending coins', (tester) async {
    final container = await pumpPuzzle(tester);
    final controller = container.read(puzzleSessionProvider(puzzleId).notifier);
    final before = container.read(puzzleSessionProvider(puzzleId)).requireValue;
    final cell = before.selection!.cell;
    final result = await controller.useHint(HintType.revealLetter);
    await tester.pump();
    expect(result.applied, isTrue);
    expect(result.usedFreeHint, isTrue);
    final after = container.read(puzzleSessionProvider(puzzleId)).requireValue;
    expect(after.progress.entry(cell).status, CellStatus.revealed);
    expect(after.progress.entry(cell).symbol, before.puzzle.solution[cell]);
    expect(after.progress.lettersRevealed, 1);
  });

  testWidgets('phone keyboard: letters and backspace arrive through the hidden field; action keys sit above it', (tester) async {
    usePhoneSurface(tester);
    await tester.pumpWidget(wrapScreen(
      const PuzzleScreen(puzzleId: puzzleId),
      overrides: testOverrides(content: content, settings: const AppSettings(onboardingDone: true, tutorialDone: true)),
    ));
    await pumpUntilFound(tester, find.byType(SystemKeyboardInput));
    expect(find.byType(PuzzleKeyboard), findsNothing);
    expect(find.byType(PuzzleActionRow), findsOneWidget);
    expect(find.bySemanticsLabel('מחיקה'), findsNothing, reason: 'the phone keyboard has its own backspace');

    final container = ProviderScope.containerOf(tester.element(find.byType(PuzzleScreen)));
    var session = container.read(puzzleSessionProvider(puzzleId)).requireValue;
    final firstCell = session.selection!.cell;
    final symbol = session.puzzle.solution[firstCell];
    final field = find.descendant(of: find.byType(SystemKeyboardInput), matching: find.byType(TextField));

    await tester.enterText(field, '​${session.lang.symbolToDisplay(symbol)}');
    await tester.pump();
    session = container.read(puzzleSessionProvider(puzzleId)).requireValue;
    expect(session.progress.entry(firstCell).symbol, symbol);
    expect(session.selection!.cell, isNot(firstCell));

    await tester.enterText(field, '');
    await tester.pump();
    session = container.read(puzzleSessionProvider(puzzleId)).requireValue;
    expect(session.progress.entry(firstCell).isEmpty, isTrue);
    expect(session.selection!.cell, firstCell);
  });
}
