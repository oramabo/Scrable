/// Language layer: everything the engine, generator and renderer need to know
/// about a puzzle language. Adding a language means adding a profile here plus
/// content; no engine code changes.
library;

/// Reading direction of the grid. Column 0 is always the first column in
/// reading direction, so the generator never thinks about left or right.
enum ReadingDirection { rtl, ltr }

/// Describes one puzzle language.
abstract class LanguageProfile {
  const LanguageProfile();

  /// BCP-47 code, e.g. `he`, `en`.
  String get code;

  /// Human readable name in the language itself.
  String get nativeName;

  ReadingDirection get direction;

  /// Number of symbols in the alphabet used by the grid (not the number of
  /// Unicode letters: Hebrew has 22 letters but 27 symbols because the geresh
  /// letters occupy a single cell).
  int get alphabetSize;

  /// Display string for a symbol in regular (non-final) form.
  String symbolToDisplay(int symbol);

  /// Display string for a symbol at the end of a word (Hebrew final forms).
  String symbolToFinalDisplay(int symbol) => symbolToDisplay(symbol);

  /// Whether [symbol] has a distinct final form.
  bool hasFinalForm(int symbol) => false;

  /// Base symbol for a geresh/variant symbol (Hebrew: ג׳ -> ג). Returns
  /// [symbol] itself when it has no base.
  int baseSymbol(int symbol) => symbol;

  /// Whether [symbol] is a variant (e.g. a geresh letter) of another symbol.
  bool isVariantSymbol(int symbol) => baseSymbol(symbol) != symbol;

  /// The variant symbol of a base letter (ג → ג׳), or `null` when none exists.
  int? variantOf(int base) {
    for (var s = 0; s < alphabetSize; s++) {
      if (s != base && baseSymbol(s) == base) return s;
    }
    return null;
  }

  /// Normalises free text into grid symbols. Returns `null` when the text
  /// contains characters that cannot live in a grid of this language.
  List<int>? normalize(String text);

  /// Normalised string form (one display char per symbol, regular forms) used
  /// as the canonical key of a word.
  String canonicalKey(List<int> symbols) =>
      symbols.map(symbolToDisplay).join();

  /// Keyboard rows for the in-app keyboard, as symbol ids. The first layout is
  /// the default.
  List<KeyboardLayout> get keyboardLayouts;

  /// Approximate advance width of one symbol in `em` for the clue font; used
  /// by the fit model before the real text layout runs in the app.
  double symbolAdvanceEm(int symbol) => 0.55;

  /// Advance width of an arbitrary clue character in `em`.
  double charAdvanceEm(String char);

  /// Letter name for screen readers (e.g. "אלף", "A").
  String symbolName(int symbol);

  /// Suffix appended to clues of multi-word answers, e.g. "(2 מילים)".
  String multiWordSuffix(int wordCount);
}

class KeyboardLayout {
  const KeyboardLayout({required this.id, required this.rows});
  final String id;

  /// Rows of keys in the order they should be displayed along the reading
  /// direction.
  final List<List<KeyboardKey>> rows;
}

/// One key of the in-app keyboard. A key always emits [symbol]; [finalForm]
/// only changes the glyph shown on the key (Hebrew ך ם ן ף ץ keys of the
/// standard layout).
class KeyboardKey {
  const KeyboardKey(this.symbol, {this.finalForm = false});
  final int symbol;
  final bool finalForm;
}

/// Shared helpers.
String stripCombiningMarks(String s) {
  final buf = StringBuffer();
  for (final rune in s.runes) {
    // Hebrew points/cantillation and general combining marks.
    final isHebrewMark = rune >= 0x0591 && rune <= 0x05C7;
    final isCombining = rune >= 0x0300 && rune <= 0x036F;
    if (!isHebrewMark && !isCombining) buf.writeCharCode(rune);
  }
  return buf.toString();
}
