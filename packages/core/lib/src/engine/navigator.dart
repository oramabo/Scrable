import '../model/geometry.dart';
import '../model/puzzle.dart';
import 'progress.dart';

/// The player's current selection.
class Selection {
  const Selection({required this.wordId, required this.cell});
  final String wordId;
  final int cell;

  @override
  bool operator ==(Object other) => other is Selection && other.wordId == wordId && other.cell == cell;
  @override
  int get hashCode => Object.hash(wordId, cell);
}

/// Pure navigation rules: which word becomes active, where the cursor goes
/// after typing, next/previous word. No UI, no side effects.
class PuzzleNavigator {
  PuzzleNavigator(this.puzzle, {this.skipFilled = true, this.autoNextWord = true});

  final Puzzle puzzle;

  /// Jump over filled cells while advancing.
  final bool skipFilled;

  /// Jump to the next incomplete word when the current one is finished.
  final bool autoNextWord;

  /// Words in reading order: across words top-to-bottom then down words.
  late final List<PuzzleWord> readingOrder = () {
    final across = puzzle.words.where((w) => w.dir == Dir.across).toList()
      ..sort((a, b) => a.start.r != b.start.r ? a.start.r - b.start.r : a.start.c - b.start.c);
    final down = puzzle.words.where((w) => w.dir == Dir.down).toList()
      ..sort((a, b) => a.start.c != b.start.c ? a.start.c - b.start.c : a.start.r - b.start.r);
    return [...across, ...down];
  }();

  PuzzleWord word(String id) => puzzle.wordById[id]!;

  /// Selecting a letter cell. Tapping the current cursor cell toggles
  /// direction when the cell has two words; tapping another cell of the
  /// selected word keeps the word and only moves the cursor.
  Selection? tapCell(int cell, Selection? current, PuzzleProgress progress) {
    if (puzzle.shape.kinds[cell] != CellKind.letter) return current;
    final across = puzzle.index.acrossOf[cell];
    final down = puzzle.index.downOf[cell];
    if (across == null && down == null) return current;
    if (current != null && current.cell != cell && (current.wordId == across || current.wordId == down)) {
      return Selection(wordId: current.wordId, cell: cell);
    }
    if (across == null) return Selection(wordId: down!, cell: cell);
    if (down == null) return Selection(wordId: across, cell: cell);

    if (current != null && current.cell == cell) {
      // toggle direction
      final other = current.wordId == across ? down : across;
      return Selection(wordId: other, cell: cell);
    }
    // Keep the current direction when the cell has a word in it.
    if (current != null) {
      final curDir = word(current.wordId).dir;
      final sameDirWord = curDir == Dir.across ? across : down;
      final sameDirDone = _isWordFilled(word(sameDirWord), progress);
      final otherWord = curDir == Dir.across ? down : across;
      if (!sameDirDone || _isWordFilled(word(otherWord), progress)) {
        return Selection(wordId: sameDirWord, cell: cell);
      }
      return Selection(wordId: otherWord, cell: cell);
    }
    // Default: across unless it is already complete and down is not.
    if (_isWordFilled(word(across), progress) && !_isWordFilled(word(down), progress)) {
      return Selection(wordId: down, cell: cell);
    }
    return Selection(wordId: across, cell: cell);
  }

  /// Selecting a word from its clue: first empty cell, else first cell.
  Selection selectWord(String wordId, PuzzleProgress progress) {
    final w = word(wordId);
    for (final p in w.cells) {
      final i = puzzle.shape.indexOf(p);
      if (progress.entry(i).isEmpty) return Selection(wordId: wordId, cell: i);
    }
    return Selection(wordId: wordId, cell: puzzle.shape.indexOf(w.start));
  }

  /// Cursor position after a letter was typed into [sel.cell].
  Selection afterType(Selection sel, PuzzleProgress progress) {
    final w = word(sel.wordId);
    final cells = w.cells.map(puzzle.shape.indexOf).toList();
    final k = cells.indexOf(sel.cell);
    for (var i = k + 1; i < cells.length; i++) {
      if (!skipFilled || progress.entry(cells[i]).isEmpty) {
        return Selection(wordId: sel.wordId, cell: cells[i]);
      }
    }
    // Word finished (or only filled cells remain).
    if (autoNextWord) {
      final next = nextIncompleteWord(sel.wordId, progress);
      if (next != null) return selectWord(next.id, progress);
    }
    return sel;
  }

  /// Target of a backspace: the cursor cell itself when it holds an unlocked
  /// letter, otherwise the previous cell of the word.
  Selection backspaceTarget(Selection sel, PuzzleProgress progress) {
    final e = progress.entry(sel.cell);
    if (!e.isEmpty && !e.isLocked) return sel;
    final w = word(sel.wordId);
    final cells = w.cells.map(puzzle.shape.indexOf).toList();
    final k = cells.indexOf(sel.cell);
    for (var i = k - 1; i >= 0; i--) {
      if (!progress.entry(cells[i]).isLocked) return Selection(wordId: sel.wordId, cell: cells[i]);
    }
    return sel;
  }

  PuzzleWord? nextIncompleteWord(String fromId, PuzzleProgress progress) {
    final order = readingOrder;
    final start = order.indexWhere((w) => w.id == fromId);
    for (var step = 1; step <= order.length; step++) {
      final w = order[(start + step) % order.length];
      if (w.id != fromId && !_isWordFilled(w, progress)) return w;
    }
    return null;
  }

  Selection nextWord(Selection sel, PuzzleProgress progress) {
    final order = readingOrder;
    final i = order.indexWhere((w) => w.id == sel.wordId);
    return selectWord(order[(i + 1) % order.length].id, progress);
  }

  Selection prevWord(Selection sel, PuzzleProgress progress) {
    final order = readingOrder;
    final i = order.indexWhere((w) => w.id == sel.wordId);
    return selectWord(order[(i - 1 + order.length) % order.length].id, progress);
  }

  /// The other word through the cursor cell, if any.
  String? crossingWord(Selection sel) {
    final a = puzzle.index.acrossOf[sel.cell];
    final d = puzzle.index.downOf[sel.cell];
    if (a == null || d == null) return null;
    return sel.wordId == a ? d : a;
  }

  bool _isWordFilled(PuzzleWord w, PuzzleProgress progress) =>
      w.cells.every((p) => !progress.entry(puzzle.shape.indexOf(p)).isEmpty);
}
