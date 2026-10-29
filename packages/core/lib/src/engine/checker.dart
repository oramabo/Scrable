import '../lang/language_profile.dart';
import '../model/geometry.dart';
import '../model/puzzle.dart';
import 'progress.dart';

/// Result of a check action.
class CheckResult {
  const CheckResult({required this.progress, required this.wrongCells, required this.correctCells});
  final PuzzleProgress progress;
  final List<int> wrongCells;
  final List<int> correctCells;
}

/// Checking, revealing and completion logic. Pure functions over
/// [PuzzleProgress]; coin costs live in the app's wallet layer.
class PuzzleChecker {
  PuzzleChecker(this.puzzle, this.lang, {this.lenientVariants = true});

  final Puzzle puzzle;
  final LanguageProfile lang;

  /// Accept a base letter where the solution has a variant symbol (ג for ג׳).
  final bool lenientVariants;

  bool symbolMatches(int typed, int expected) {
    if (typed == expected) return true;
    return lenientVariants && lang.baseSymbol(expected) == typed;
  }

  bool isCellCorrect(int cell, PuzzleProgress progress) {
    final e = progress.entry(cell);
    if (e.symbol == null) return false;
    return symbolMatches(e.symbol!, puzzle.solution[cell]);
  }

  bool isWordFilled(PuzzleWord w, PuzzleProgress progress) =>
      w.cells.every((p) => !progress.entry(puzzle.shape.indexOf(p)).isEmpty);

  bool isWordCorrect(PuzzleWord w, PuzzleProgress progress) =>
      w.cells.every((p) => isCellCorrect(puzzle.shape.indexOf(p), progress));

  bool isComplete(PuzzleProgress progress) {
    for (var i = 0; i < puzzle.shape.cellCount; i++) {
      if (puzzle.shape.kinds[i] == CellKind.letter && !isCellCorrect(i, progress)) return false;
    }
    return true;
  }

  /// Type a symbol into a cell, applying the play mode's immediate feedback.
  PuzzleProgress type(int cell, int symbol, PuzzleProgress progress, {required int now, bool pencil = false}) {
    final current = progress.entry(cell);
    if (current.isLocked) return progress;
    var status = CellStatus.filled;
    var wrong = progress.wrongEntries;
    if (progress.mode == PlayMode.relaxed) {
      final ok = symbolMatches(symbol, puzzle.solution[cell]);
      status = ok ? CellStatus.confirmedCorrect : CellStatus.markedWrong;
      if (!ok) wrong++;
    }
    var next = progress.withCell(cell, CellEntry(symbol: symbol, status: status, pencil: pencil, updatedAt: now), now: now);
    if (wrong != progress.wrongEntries) next = next.copyWith(wrongEntries: wrong);
    return next;
  }

  PuzzleProgress clear(int cell, PuzzleProgress progress, {required int now}) {
    final current = progress.entry(cell);
    if (current.isLocked || current.isEmpty) return progress;
    return progress.withCell(cell, CellEntry(updatedAt: now), now: now);
  }

  /// In [PlayMode.normal], called when a word becomes full: confirms correct
  /// words; returns `false` when the word is wrong (UI pulses the outline
  /// without pinpointing letters).
  (PuzzleProgress, bool) evaluateWord(PuzzleWord w, PuzzleProgress progress, {required int now}) {
    if (!isWordFilled(w, progress)) return (progress, false);
    if (!isWordCorrect(w, progress)) return (progress, false);
    var next = progress;
    for (final p in w.cells) {
      final i = puzzle.shape.indexOf(p);
      final e = next.entry(i);
      if (e.status != CellStatus.revealed) {
        next = next.withCell(i, e.copyWith(status: CellStatus.confirmedCorrect, pencil: false, updatedAt: now), now: now);
      }
    }
    return (next, true);
  }

  /// Reveal the solution letter of one cell.
  PuzzleProgress revealLetter(int cell, PuzzleProgress progress, {required int now}) {
    if (puzzle.shape.kinds[cell] != CellKind.letter) return progress;
    final e = progress.entry(cell);
    if (e.status == CellStatus.revealed) return progress;
    return progress
        .withCell(cell, CellEntry(symbol: puzzle.solution[cell], status: CellStatus.revealed, updatedAt: now), now: now)
        .copyWith(lettersRevealed: progress.lettersRevealed + 1);
  }

  /// Reveal every remaining cell of a word.
  PuzzleProgress revealWord(PuzzleWord w, PuzzleProgress progress, {required int now}) {
    var next = progress;
    for (final p in w.cells) {
      final i = puzzle.shape.indexOf(p);
      final e = next.entry(i);
      if (e.status == CellStatus.revealed || (isCellCorrect(i, next) && e.status == CellStatus.confirmedCorrect)) continue;
      next = next.withCell(i, CellEntry(symbol: puzzle.solution[i], status: CellStatus.revealed, updatedAt: now), now: now);
    }
    return next.copyWith(wordsRevealed: progress.wordsRevealed + 1);
  }

  /// The cell of [w] whose reveal helps most: an empty or wrong cell that is
  /// also part of the crossing word with the most unsolved letters.
  int? smartLetterCell(PuzzleWord w, PuzzleProgress progress) {
    int? best;
    var bestScore = -1;
    for (final p in w.cells) {
      final i = puzzle.shape.indexOf(p);
      if (isCellCorrect(i, progress)) continue;
      var score = 1;
      final other = puzzle.index.isChecked(i)
          ? (puzzle.index.acrossOf[i] == w.id ? puzzle.index.downOf[i] : puzzle.index.acrossOf[i])
          : null;
      if (other != null) {
        final ow = puzzle.wordById[other]!;
        score += 10 + ow.cells.where((q) => !isCellCorrect(puzzle.shape.indexOf(q), progress)).length;
      }
      if (score > bestScore) {
        bestScore = score;
        best = i;
      }
    }
    return best;
  }

  /// A random unsolved cell of the word (caller supplies the random index).
  int? randomLetterCell(PuzzleWord w, PuzzleProgress progress, int Function(int max) nextInt) {
    final candidates = [
      for (final p in w.cells)
        if (!isCellCorrect(puzzle.shape.indexOf(p), progress)) puzzle.shape.indexOf(p),
    ];
    if (candidates.isEmpty) return null;
    return candidates[nextInt(candidates.length)];
  }

  /// Mark wrong letters of a word (or of the whole grid when [w] is null).
  CheckResult check(PuzzleProgress progress, {PuzzleWord? w, required int now}) {
    final cells = w == null ? puzzle.letterCellIndices : w.cells.map(puzzle.shape.indexOf).toList();
    final wrong = <int>[];
    final correct = <int>[];
    var next = progress;
    for (final i in cells) {
      final e = next.entry(i);
      if (e.isEmpty) continue;
      if (isCellCorrect(i, next)) {
        correct.add(i);
        if (e.status != CellStatus.revealed) {
          next = next.withCell(i, e.copyWith(status: CellStatus.confirmedCorrect, pencil: false, updatedAt: now), now: now);
        }
      } else {
        wrong.add(i);
        next = next.withCell(i, e.copyWith(status: CellStatus.markedWrong, updatedAt: now), now: now);
      }
    }
    return CheckResult(progress: next.copyWith(checksUsed: progress.checksUsed + 1), wrongCells: wrong, correctCells: correct);
  }

  /// Reveal the first letter of every word (power-up).
  PuzzleProgress revealFirstLetters(PuzzleProgress progress, {required int now}) {
    var next = progress;
    var count = 0;
    for (final w in puzzle.words) {
      final i = puzzle.shape.indexOf(w.start);
      if (next.entry(i).status == CellStatus.revealed || isCellCorrect(i, next)) continue;
      next = next.withCell(i, CellEntry(symbol: puzzle.solution[i], status: CellStatus.revealed, updatedAt: now), now: now);
      count++;
    }
    return next.copyWith(lettersRevealed: progress.lettersRevealed + count);
  }

  /// Stars for a finished puzzle: 3 = no hints and under par in normal or
  /// newspaper mode, 2 = hints used or relaxed mode, 1 = completed.
  static int starsFor(PuzzleProgress progress, {required int parMs}) {
    if (!progress.completed) return 0;
    if (progress.mode == PlayMode.relaxed) return progress.hintsUsed == 0 ? 2 : 1;
    if (progress.hintsUsed == 0 && progress.elapsedMs <= parMs) return 3;
    if (progress.hintsUsed <= 2) return 2;
    return 1;
  }
}
