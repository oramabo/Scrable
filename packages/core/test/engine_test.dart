import 'package:chetz_core/chetz_core.dart';
import 'package:test/test.dart';

/// 4x4 Hebrew puzzle built by hand:
///   row0: C C C C
///   row1: C ש ל ם   (a01: שלם? we use שלג) -> across word "שלג" (c1..c3)
///   row2: C מ ו ג   -> "מוג"
///   row3: C ש ה ר   -> "שהר" (nonsense but fine for engine tests)
/// down words: d01 "שמש" (col1), d02 "לוה" (col2), d03 "גגר" (col3)
Puzzle buildPuzzle() {
  const he = HebrewProfile();
  final shape = GridShape.fromRows(['CCCC', 'CLLL', 'CLLL', 'CLLL']);
  final rows = ['שלג', 'מוג', 'שהר'];
  final solution = List<int>.filled(16, -1);
  for (var r = 1; r <= 3; r++) {
    for (var c = 1; c <= 3; c++) {
      solution[shape.index(r, c)] = he.normalize(rows[r - 1][c - 1])!.first;
    }
  }
  final words = <PuzzleWord>[
    for (var r = 1; r <= 3; r++)
      PuzzleWord(id: 'a0$r', dir: Dir.across, start: Pos(r, 1), len: 3, clueCell: Pos(r, 0), arrow: Arrow.a),
    for (var c = 1; c <= 3; c++)
      PuzzleWord(id: 'd0$c', dir: Dir.down, start: Pos(1, c), len: 3, clueCell: Pos(0, c), arrow: Arrow.d),
  ];
  final clueCells = <ClueCell>[
    for (var r = 1; r <= 3; r++)
      ClueCell(pos: Pos(r, 0), slots: [ClueSlot(pos: SlotPos.full, wordId: 'a0$r', arrow: Arrow.a, text: 'across $r', lines: ['across $r'])]),
    for (var c = 1; c <= 3; c++)
      ClueCell(pos: Pos(0, c), slots: [ClueSlot(pos: SlotPos.full, wordId: 'd0$c', arrow: Arrow.d, text: 'down $c', lines: ['down $c'])]),
  ];
  return Puzzle(
    id: 'he-test',
    lang: 'he',
    kind: PuzzleKind.tutorial,
    level: 1,
    shape: shape,
    clueCells: clueCells,
    words: words,
    solution: solution,
    difficulty: const PuzzleDifficulty(score: 10, band: 'starter'),
  );
}

void main() {
  const he = HebrewProfile();
  final puzzle = buildPuzzle();
  int sym(String ch) => he.normalize(ch)!.first;

  group('codec', () {
    test('round-trips with obfuscated and plain solutions and keeps checksum', () {
      const codec = PuzzleCodec();
      final stamped = codec.withChecksum(puzzle);
      for (final obfuscate in [true, false]) {
        final text = codec.encode(stamped, obfuscate: obfuscate);
        final back = codec.decode(text);
        expect(back.solution, puzzle.solution);
        expect(back.words.length, 6);
        expect(back.clueCells.length, 6);
        expect(codec.verifyChecksum(back), isTrue, reason: 'obfuscate=$obfuscate');
        expect(back.meta.checksum, stamped.meta.checksum);
      }
    });
    test('obfuscated data does not contain the symbols in clear', () {
      const codec = PuzzleCodec();
      final json = codec.toJson(puzzle);
      expect((json['solution'] as Map)['enc'], 'xor1');
      expect(json['layout'], ['CCCC', 'CLLL', 'CLLL', 'CLLL']);
    });
  });

  group('final letters', () {
    test('across wins: last cell of an across word shows the final form', () {
      final mask = FinalLetterPolicy.mask(puzzle);
      final shape = puzzle.shape;
      expect(mask[shape.index(1, 3)], isTrue); // end of row word
      expect(mask[shape.index(1, 1)], isFalse);
      expect(mask[shape.index(3, 1)], isFalse); // last of down d01 but first of across a03: across wins
      expect(mask[shape.index(3, 3)], isTrue); // last of a03 and of d03
      expect(mask[shape.index(2, 3)], isTrue); // end of across a02 even though mid-column
      expect(FinalLetterPolicy.display(he, sym('מ'), true), 'ם');
      expect(FinalLetterPolicy.display(he, sym('מ'), false), 'מ');
    });
  });

  group('navigator', () {
    final nav = PuzzleNavigator(puzzle);
    final fresh = PuzzleProgress.fresh(puzzleId: puzzle.id, puzzleVersion: 1, shape: puzzle.shape);
    test('tap selects across first, second tap toggles to down', () {
      final cell = puzzle.shape.index(2, 2);
      final s1 = nav.tapCell(cell, null, fresh)!;
      expect(s1.wordId, 'a02');
      final s2 = nav.tapCell(cell, s1, fresh)!;
      expect(s2.wordId, 'd02');
      expect(nav.crossingWord(s2), 'a02');
    });
    test('typing advances along the word and jumps to the next incomplete word', () {
      final start = nav.selectWord('a01', fresh);
      expect(start.cell, puzzle.shape.index(1, 1));
      final next = nav.afterType(start, fresh);
      expect(next.cell, puzzle.shape.index(1, 2));
      final last = Selection(wordId: 'a01', cell: puzzle.shape.index(1, 3));
      final jumped = nav.afterType(last, fresh);
      expect(jumped.wordId, 'a02');
    });
    test('backspace targets the previous cell when the cursor cell is empty', () {
      final sel = Selection(wordId: 'a01', cell: puzzle.shape.index(1, 2));
      expect(nav.backspaceTarget(sel, fresh).cell, puzzle.shape.index(1, 1));
    });
    test('reading order lists across words before down words', () {
      expect(nav.readingOrder.map((w) => w.id).toList(), ['a01', 'a02', 'a03', 'd01', 'd02', 'd03']);
    });
  });

  group('checker', () {
    final checker = PuzzleChecker(puzzle, he);
    final fresh = PuzzleProgress.fresh(puzzleId: puzzle.id, puzzleVersion: 1, shape: puzzle.shape);

    test('relaxed mode marks letters immediately', () {
      final p = fresh.copyWith(mode: PlayMode.relaxed);
      final cell = puzzle.shape.index(1, 1);
      final ok = checker.type(cell, sym('ש'), p, now: 1);
      expect(ok.entry(cell).status, CellStatus.confirmedCorrect);
      final bad = checker.type(cell, sym('ב'), p, now: 1);
      expect(bad.entry(cell).status, CellStatus.markedWrong);
      expect(bad.wrongEntries, 1);
    });

    test('final letters are accepted as base letters', () {
      final cell = puzzle.shape.index(1, 3); // ג at end of שלג
      expect(checker.symbolMatches(sym('ג'), puzzle.solution[cell]), isTrue);
      final cellM = puzzle.shape.index(2, 1); // מ
      expect(checker.symbolMatches(he.normalize('ם')!.first, puzzle.solution[cellM]), isTrue);
    });

    test('evaluateWord confirms a correct word and rejects a wrong one', () {
      var p = fresh;
      final w = puzzle.wordById['a01']!;
      for (final (k, ch) in 'שלג'.split('').indexed) {
        p = checker.type(puzzle.shape.indexOf(w.cellAt(k)), sym(ch), p, now: 1);
      }
      final (confirmed, ok) = checker.evaluateWord(w, p, now: 2);
      expect(ok, isTrue);
      expect(confirmed.entry(puzzle.shape.index(1, 2)).status, CellStatus.confirmedCorrect);

      var q = fresh;
      for (final (k, ch) in 'שלב'.split('').indexed) {
        q = checker.type(puzzle.shape.indexOf(w.cellAt(k)), sym(ch), q, now: 1);
      }
      final (_, ok2) = checker.evaluateWord(w, q, now: 2);
      expect(ok2, isFalse);
    });

    test('reveal, check and completion', () {
      var p = fresh;
      final cell = puzzle.shape.index(1, 1);
      p = checker.revealLetter(cell, p, now: 1);
      expect(p.entry(cell).status, CellStatus.revealed);
      expect(p.lettersRevealed, 1);
      // typing over a revealed cell is ignored
      expect(checker.type(cell, sym('ב'), p, now: 2).entry(cell).symbol, puzzle.solution[cell]);
      p = checker.revealWord(puzzle.wordById['d02']!, p, now: 3);
      expect(p.wordsRevealed, 1);
      // fill the rest correctly
      for (var i = 0; i < 16; i++) {
        if (puzzle.shape.kinds[i] == CellKind.letter && p.entry(i).isEmpty) {
          p = checker.type(i, puzzle.solution[i], p, now: 4);
        }
      }
      expect(checker.isComplete(p), isTrue);
      final res = checker.check(p, now: 5);
      expect(res.wrongCells, isEmpty);
      expect(res.progress.checksUsed, 1);
    });

    test('smart letter prefers a cell whose crossing word is unsolved', () {
      final cell = checker.smartLetterCell(puzzle.wordById['a01']!, fresh);
      expect(cell, isNotNull);
      expect(puzzle.index.isChecked(cell!), isTrue);
    });

    test('stars', () {
      final done = fresh.copyWith(completed: true, elapsedMs: 100000);
      expect(PuzzleChecker.starsFor(done, parMs: 300000), 3);
      expect(PuzzleChecker.starsFor(done.copyWith(lettersRevealed: 1), parMs: 300000), 2);
      expect(PuzzleChecker.starsFor(done.copyWith(lettersRevealed: 5), parMs: 300000), 1);
      expect(PuzzleChecker.starsFor(done.copyWith(mode: PlayMode.relaxed), parMs: 300000), 2);
    });
  });

  group('progress', () {
    test('json round trip and merge keeps the newer cell and sticky completion', () {
      final shape = puzzle.shape;
      final a = PuzzleProgress.fresh(puzzleId: 'x', puzzleVersion: 1, shape: shape, now: 1)
          .withCell(shape.index(1, 1), const CellEntry(symbol: 3, status: CellStatus.filled, updatedAt: 10), now: 10)
          .copyWith(elapsedMs: 500);
      final b = PuzzleProgress.fresh(puzzleId: 'x', puzzleVersion: 1, shape: shape, now: 1)
          .withCell(shape.index(1, 1), const CellEntry(symbol: 4, status: CellStatus.filled, updatedAt: 20), now: 20)
          .copyWith(completed: true, completedAt: 30, elapsedMs: 300);
      final m = PuzzleProgress.merge(a, b);
      expect(m.entry(shape.index(1, 1)).symbol, 4);
      expect(m.completed, isTrue);
      expect(m.elapsedMs, 500);
      final back = PuzzleProgress.fromJson(m.toJson());
      expect(back.cells.length, 16);
      expect(back.entry(shape.index(1, 1)).symbol, 4);
      expect(back.cells[0], isNull);
    });
  });
}
