import 'package:chetz_core/chetz_core.dart';

/// Pure rules for the A→Z / א→ת cycler: which cell it targets and which
/// symbol comes next in the language's alphabet order.
abstract final class AlphabetCycler {
  /// The single cell of [word] the cycler would write into, or null when the
  /// word does not qualify: exactly one empty cell, or (when nothing is
  /// empty) exactly one unlocked cell marked wrong. A cell currently holding a
  /// cycler preview ([cyclingCell]) keeps the cycler available.
  static int? targetCell(Puzzle puzzle, PuzzleWord word, PuzzleProgress progress, {int? cyclingCell}) {
    final cells = word.cells.map(puzzle.shape.indexOf).toList();
    if (cyclingCell != null && cells.contains(cyclingCell) && !progress.entry(cyclingCell).isLocked) return cyclingCell;
    final empty = <int>[];
    final wrong = <int>[];
    for (final c in cells) {
      final e = progress.entry(c);
      if (e.isLocked) continue;
      if (e.isEmpty) {
        empty.add(c);
      } else if (e.status == CellStatus.markedWrong) {
        wrong.add(c);
      }
    }
    if (empty.length == 1) return empty.single;
    if (empty.isEmpty && wrong.length == 1) return wrong.single;
    return null;
  }

  /// Base letters in alphabet order (variant symbols such as ג׳ are skipped).
  static List<int> alphabet(LanguageProfile lang) =>
      [for (var s = 0; s < lang.alphabetSize; s++) if (!lang.isVariantSymbol(s)) s];

  /// Symbol after [current] in alphabet order (wraps); the first letter when
  /// [current] is null or not a base letter.
  static int next(LanguageProfile lang, int? current) {
    final letters = alphabet(lang);
    if (current == null) return letters.first;
    final i = letters.indexOf(lang.baseSymbol(current));
    if (i < 0) return letters.first;
    return letters[(i + 1) % letters.length];
  }

  /// Interval between letters while auto-running (~4 letters / second).
  static const autoRunInterval = Duration(milliseconds: 250);
}
