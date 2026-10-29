import 'package:chetz_app/core/content/content_source.dart';
import 'package:chetz_app/core/storage/json_store.dart';
import 'package:chetz_app/features/puzzle/application/progress_providers.dart';
import 'package:chetz_app/features/puzzle/application/puzzle_controller.dart';
import 'package:chetz_app/features/puzzle/presentation/keyboard/puzzle_keyboard.dart';
import 'package:chetz_app/features/puzzle/presentation/puzzle_screen.dart';
import 'package:chetz_app/features/puzzle/presentation/sheets/completion_sheet.dart';
import 'package:chetz_app/features/wallet/ledger.dart';
import 'package:chetz_app/features/wallet/wallet_controller.dart';
import 'package:chetz_core/chetz_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  late MapContentSource content;

  setUpAll(() async {
    content = await loadBundledContent();
  });

  const puzzleId = 'he-l1-p01-02';

  testWidgets('filling the solution completes the puzzle, shows the sheet and pays coins', (tester) async {
    usePhoneSurface(tester);
    final store = MemoryJsonStore();
    await tester.pumpWidget(
      wrapScreen(const PuzzleScreen(puzzleId: puzzleId), overrides: testOverrides(content: content, store: store)),
    );
    await pumpUntilFound(tester, find.byType(PuzzleKeyboard));
    final container = ProviderScope.containerOf(tester.element(find.byType(PuzzleScreen)));
    final controller = container.read(puzzleSessionProvider(puzzleId).notifier);
    var session = container.read(puzzleSessionProvider(puzzleId)).requireValue;
    final puzzle = session.puzzle;
    expect(container.read(balanceProvider), testStartingWallet);

    // Fill every letter cell through the controller.
    for (final i in puzzle.letterCellIndices) {
      if (session.progress.entry(i).isLocked) continue;
      controller.tapCell(i);
      controller.typeSymbol(puzzle.solution[i]);
      session = container.read(puzzleSessionProvider(puzzleId)).requireValue;
      if (session.isComplete) break;
    }
    await tester.pump();
    session = container.read(puzzleSessionProvider(puzzleId)).requireValue;
    expect(session.isComplete, isTrue);
    expect(session.progress.completed, isTrue);
    expect(session.progress.stars, 3, reason: 'no hints, under par, normal mode');
    expect(session.completion, isNotNull);
    expect(session.completion!.learned.length, 3);
    expect(session.completion!.coinsEarned, 30, reason: 'L1 reward 20 + 50% three-star bonus');

    // Wallet credited once, idempotently.
    final ledger = container.read(walletProvider);
    expect(ledger.balance, testStartingWallet + 30);
    expect(ledger.hasEntry(LedgerEntryType.earnComplete, puzzleId), isTrue);

    // Completion sheet appears after the frame.
    await tester.pumpAndSettle();
    expect(find.byType(CompletionSheet), findsOneWidget);
    expect(find.text('כל הכבוד!'), findsOneWidget);
    expect(find.text('התשחץ הבא'), findsOneWidget, reason: 'pack has a next puzzle');
    for (final w in session.completion!.learned) {
      expect(find.text(w.answer), findsOneWidget);
    }

    // Progress and index were persisted.
    final saved = await store.read('progress/$puzzleId');
    expect(saved?['completed'], isTrue);
    expect(container.read(progressSummariesProvider)[puzzleId]?.completed, isTrue);
    expect(container.read(progressSummariesProvider)[puzzleId]?.stars, 3);

    // Typing after completion is ignored and the keyboard is disabled.
    controller.typeSymbol(0);
    expect(container.read(puzzleSessionProvider(puzzleId)).requireValue.progress.completed, isTrue);
  });

  testWidgets('relaxed mode marks letters immediately and caps stars at 2', (tester) async {
    usePhoneSurface(tester);
    const id = 'he-l1-p01-03';
    await tester.pumpWidget(wrapScreen(const PuzzleScreen(puzzleId: id), overrides: testOverrides(content: content)));
    await pumpUntilFound(tester, find.byType(PuzzleKeyboard));
    final container = ProviderScope.containerOf(tester.element(find.byType(PuzzleScreen)));
    final controller = container.read(puzzleSessionProvider(id).notifier);
    expect(controller.setMode(PlayMode.relaxed), isTrue);
    var session = container.read(puzzleSessionProvider(id)).requireValue;
    final puzzle = session.puzzle;
    final first = session.selection!.cell;
    controller.typeSymbol((puzzle.solution[first] + 1) % 22);
    session = container.read(puzzleSessionProvider(id)).requireValue;
    expect(session.progress.entry(first).status, CellStatus.markedWrong);
    expect(session.progress.wrongEntries, 1);
    controller.tapCell(first);
    controller.typeSymbol(puzzle.solution[first]);
    session = container.read(puzzleSessionProvider(id)).requireValue;
    expect(session.progress.entry(first).status, CellStatus.confirmedCorrect);
    expect(controller.setMode(PlayMode.normal), isFalse, reason: 'mode locked once letters are entered');

    for (final i in puzzle.letterCellIndices) {
      if (container.read(puzzleSessionProvider(id)).requireValue.progress.entry(i).isLocked) continue;
      controller.tapCell(i);
      controller.typeSymbol(puzzle.solution[i]);
    }
    await tester.pump();
    session = container.read(puzzleSessionProvider(id)).requireValue;
    expect(session.isComplete, isTrue);
    expect(session.progress.stars, 2);
    await tester.pumpAndSettle();
    expect(find.byType(CompletionSheet), findsOneWidget);
  });
}
