import '../lang/language_profile.dart';
import '../model/geometry.dart';
import '../model/puzzle.dart';

/// Decides which cells display a final-form letter ("across wins" rule):
/// a cell shows the final form iff it is the last cell of an across word, or
/// the last cell of a down word that belongs to no across word.
class FinalLetterPolicy {
  const FinalLetterPolicy._();

  static List<bool> mask(Puzzle puzzle) {
    final shape = puzzle.shape;
    final lastOfAcross = List<bool>.filled(shape.cellCount, false);
    final lastOfDown = List<bool>.filled(shape.cellCount, false);
    for (final w in puzzle.words) {
      final last = shape.indexOf(w.cellAt(w.len - 1));
      if (w.dir == Dir.across) {
        lastOfAcross[last] = true;
      } else {
        lastOfDown[last] = true;
      }
    }
    return [
      for (var i = 0; i < shape.cellCount; i++)
        lastOfAcross[i] || (lastOfDown[i] && puzzle.index.acrossOf[i] == null),
    ];
  }

  /// Display string for [symbol] in [cell] given the mask.
  static String display(LanguageProfile lang, int symbol, bool finalPosition) =>
      finalPosition && lang.hasFinalForm(symbol) ? lang.symbolToFinalDisplay(symbol) : lang.symbolToDisplay(symbol);
}
