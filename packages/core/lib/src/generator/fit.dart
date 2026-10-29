import '../lang/language_profile.dart';
import '../model/geometry.dart';

/// Decides whether a clue fits in a cell and how to break it into lines.
///
/// Budgets are expressed in `em` of the clue font. The app renders in-cell
/// clues at a fixed size relative to the cell, so the budget is independent
/// of the device; the admin re-measures with the real font.
class FitModel {
  const FitModel(this.lang, {
    this.fullLines = 3,
    this.fullEmPerLine = 4.3,
    this.halfLines = 2,
    this.halfEmPerLine = 4.7,
  });

  final LanguageProfile lang;
  final int fullLines;
  final double fullEmPerLine;
  final int halfLines;
  final double halfEmPerLine;

  double widthEm(String text) {
    var w = 0.0;
    for (final ch in text.split('')) {
      w += lang.charAdvanceEm(ch);
    }
    return w;
  }

  /// Greedy line breaking on spaces; returns `null` when the text does not fit.
  List<String>? breakLines(String text, SlotPos pos) {
    final maxLines = pos == SlotPos.full ? fullLines : halfLines;
    final budget = pos == SlotPos.full ? fullEmPerLine : halfEmPerLine;
    final tokens = text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    if (tokens.isEmpty) return null;
    final lines = <String>[];
    var current = '';
    for (final tok in tokens) {
      if (widthEm(tok) > budget) {
        // allow breaking at a hyphen/maqaf
        final parts = tok.split(RegExp('[-־]'));
        if (parts.length > 1 && parts.every((p) => widthEm('$p-') <= budget)) {
          for (var i = 0; i < parts.length; i++) {
            final piece = i < parts.length - 1 ? '${parts[i]}-' : parts[i];
            final candidate = current.isEmpty ? piece : '$current $piece';
            if (widthEm(candidate) <= budget && i == 0) {
              current = candidate;
            } else {
              if (current.isNotEmpty) lines.add(current);
              current = piece;
            }
          }
          continue;
        }
        return null;
      }
      final candidate = current.isEmpty ? tok : '$current $tok';
      if (widthEm(candidate) <= budget) {
        current = candidate;
      } else {
        lines.add(current);
        current = tok;
      }
      if (lines.length > maxLines) return null;
    }
    if (current.isNotEmpty) lines.add(current);
    if (lines.length > maxLines) return null;
    return lines;
  }

  bool fits(String text, SlotPos pos) => breakLines(text, pos) != null;
}
