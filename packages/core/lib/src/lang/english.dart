import 'language_profile.dart';

/// English: 26 upper-case letters; apostrophes, hyphens, spaces and
/// diacritics are dropped for matching.
class EnglishProfile extends LanguageProfile {
  const EnglishProfile();

  static const String letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  static const Map<String, String> _fold = {
    'À': 'A', 'Á': 'A', 'Â': 'A', 'Ä': 'A', 'Ã': 'A', 'Å': 'A', 'Æ': 'AE',
    'Ç': 'C', 'È': 'E', 'É': 'E', 'Ê': 'E', 'Ë': 'E', 'Ì': 'I', 'Í': 'I',
    'Î': 'I', 'Ï': 'I', 'Ñ': 'N', 'Ò': 'O', 'Ó': 'O', 'Ô': 'O', 'Ö': 'O',
    'Õ': 'O', 'Ø': 'O', 'Œ': 'OE', 'Ù': 'U', 'Ú': 'U', 'Û': 'U', 'Ü': 'U',
    'Ý': 'Y', 'Ÿ': 'Y', 'ß': 'SS',
  };

  @override
  String get code => 'en';
  @override
  String get nativeName => 'English';
  @override
  ReadingDirection get direction => ReadingDirection.ltr;
  @override
  int get alphabetSize => 26;

  @override
  String symbolToDisplay(int symbol) => letters[symbol];

  @override
  List<int>? normalize(String text) {
    final s = stripCombiningMarks(text).toUpperCase();
    final out = <int>[];
    for (final rune in s.runes) {
      var ch = String.fromCharCode(rune);
      ch = _fold[ch] ?? ch;
      for (final c in ch.split('')) {
        final i = letters.indexOf(c);
        if (i >= 0) {
          out.add(i);
        } else if (c == ' ' ||
            c == '-' ||
            c == "'" ||
            c == '’' ||
            c == '.' ||
            c == ' ') {
          // separators are dropped
        } else {
          return null;
        }
      }
    }
    return out.isEmpty ? null : out;
  }

  static List<KeyboardKey> _row(String keys) =>
      [for (final k in keys.split('')) KeyboardKey(letters.indexOf(k))];

  @override
  List<KeyboardLayout> get keyboardLayouts => [
        KeyboardLayout(id: 'qwerty', rows: [_row('QWERTYUIOP'), _row('ASDFGHJKL'), _row('ZXCVBNM')]),
        KeyboardLayout(id: 'abc', rows: [_row('ABCDEFGHI'), _row('JKLMNOPQR'), _row('STUVWXYZ')]),
      ];

  @override
  double symbolAdvanceEm(int symbol) {
    const narrow = {8, 9, 11}; // I J L
    const wide = {12, 22}; // M W
    if (narrow.contains(symbol)) return 0.3;
    if (wide.contains(symbol)) return 0.85;
    return 0.62;
  }

  @override
  double charAdvanceEm(String char) {
    if (char == ' ') return 0.25;
    final upper = char.toUpperCase();
    final i = letters.indexOf(upper);
    if (i >= 0) {
      // lower-case letters are narrower than capitals
      return char == upper ? symbolAdvanceEm(i) : symbolAdvanceEm(i) * 0.82;
    }
    return 0.35;
  }

  @override
  String symbolName(int symbol) => letters[symbol];

  @override
  String multiWordSuffix(int wordCount) => '($wordCount words)';
}
