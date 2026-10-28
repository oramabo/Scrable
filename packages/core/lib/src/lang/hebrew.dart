import 'language_profile.dart';

/// Hebrew: 22 base letters plus five geresh letters that occupy one cell.
class HebrewProfile extends LanguageProfile {
  const HebrewProfile();

  static const String letters = 'אבגדהוזחטיכלמנסעפצקרשת';
  static const int baseCount = 22;

  /// Geresh symbols: index 22..26 -> ג׳ ז׳ צ׳ ת׳ ד׳
  static const List<String> gereshBases = ['ג', 'ז', 'צ', 'ת', 'ד'];
  static const String geresh = '׳';

  static const Map<String, String> _finalToBase = {
    'ך': 'כ',
    'ם': 'מ',
    'ן': 'נ',
    'ף': 'פ',
    'ץ': 'צ',
  };
  static const Map<String, String> _baseToFinal = {
    'כ': 'ך',
    'מ': 'ם',
    'נ': 'ן',
    'פ': 'ף',
    'צ': 'ץ',
  };
  static const Set<int> _gereshMarks = {0x05F3, 0x27, 0x2019, 0x00B4, 0x02BC, 0x2032};
  static const Set<int> _gershayimMarks = {0x05F4, 0x22, 0x201C, 0x201D};

  static const List<String> _names = [
    'אלף', 'בית', 'גימל', 'דלת', 'הא', 'וו', 'זין', 'חית', 'טית', 'יוד', 'כף',
    'למד', 'מם', 'נון', 'סמך', 'עין', 'פא', 'צדי', 'קוף', 'ריש', 'שין', 'תו',
    "ג'ימל", "ז'ין", "צ'די", "ת'ו", "ד'לת",
  ];

  @override
  String get code => 'he';
  @override
  String get nativeName => 'עברית';
  @override
  ReadingDirection get direction => ReadingDirection.rtl;
  @override
  int get alphabetSize => 27;

  static int? symbolOfLetter(String ch) {
    final i = letters.indexOf(ch);
    return i < 0 ? null : i;
  }

  @override
  String symbolToDisplay(int symbol) {
    if (symbol < baseCount) return letters[symbol];
    return gereshBases[symbol - baseCount] + geresh;
  }

  @override
  String symbolToFinalDisplay(int symbol) {
    if (symbol >= baseCount) return symbolToDisplay(symbol);
    final ch = letters[symbol];
    return _baseToFinal[ch] ?? ch;
  }

  @override
  bool hasFinalForm(int symbol) =>
      symbol < baseCount && _baseToFinal.containsKey(letters[symbol]);

  @override
  int baseSymbol(int symbol) {
    if (symbol < baseCount) return symbol;
    return letters.indexOf(gereshBases[symbol - baseCount]);
  }

  @override
  List<int>? normalize(String text) {
    final s = stripCombiningMarks(text);
    final out = <int>[];
    var prevWasLetter = false;
    for (final rune in s.runes) {
      final ch = String.fromCharCode(rune);
      if (letters.contains(ch)) {
        out.add(letters.indexOf(ch));
        prevWasLetter = true;
      } else if (_finalToBase.containsKey(ch)) {
        out.add(letters.indexOf(_finalToBase[ch]!));
        prevWasLetter = true;
      } else if (_gereshMarks.contains(rune)) {
        if (prevWasLetter && out.isNotEmpty) {
          final last = out.last;
          if (last < baseCount) {
            final gi = gereshBases.indexOf(letters[last]);
            if (gi >= 0) out[out.length - 1] = baseCount + gi;
          }
        }
        prevWasLetter = false;
      } else if (_gershayimMarks.contains(rune) ||
          ch == ' ' ||
          ch == '-' ||
          ch == '־' ||
          ch == ' ' ||
          ch == '.') {
        prevWasLetter = false;
      } else {
        return null;
      }
    }
    return out.isEmpty ? null : out;
  }

  @override
  List<KeyboardLayout> get keyboardLayouts => const [
        // Alphabetical: friendlier for older players. Rows in reading order.
        KeyboardLayout(id: 'alphabetical', rows: [
          [KeyboardKey(0), KeyboardKey(1), KeyboardKey(2), KeyboardKey(3), KeyboardKey(4), KeyboardKey(5), KeyboardKey(6), KeyboardKey(7)],
          [KeyboardKey(8), KeyboardKey(9), KeyboardKey(10), KeyboardKey(11), KeyboardKey(12), KeyboardKey(13), KeyboardKey(14), KeyboardKey(15)],
          [KeyboardKey(16), KeyboardKey(17), KeyboardKey(18), KeyboardKey(19), KeyboardKey(20), KeyboardKey(21)],
        ]),
        // Standard Israeli layout; final-form keys emit the base letter.
        KeyboardLayout(id: 'standard', rows: [
          [KeyboardKey(18), KeyboardKey(19), KeyboardKey(0), KeyboardKey(8), KeyboardKey(5), KeyboardKey(13, finalForm: true), KeyboardKey(12, finalForm: true), KeyboardKey(16)],
          [KeyboardKey(20), KeyboardKey(3), KeyboardKey(2), KeyboardKey(10), KeyboardKey(15), KeyboardKey(9), KeyboardKey(7), KeyboardKey(11), KeyboardKey(10, finalForm: true), KeyboardKey(16, finalForm: true)],
          [KeyboardKey(6), KeyboardKey(14), KeyboardKey(1), KeyboardKey(4), KeyboardKey(13), KeyboardKey(12), KeyboardKey(17), KeyboardKey(21), KeyboardKey(17, finalForm: true)],
        ]),
      ];

  @override
  double symbolAdvanceEm(int symbol) {
    // Noto Sans Hebrew advances are fairly uniform; narrow letters: י ו ז ן.
    const narrow = {9, 5, 6}; // י ו ז
    if (symbol >= baseCount) return 0.62;
    return narrow.contains(symbol) ? 0.32 : 0.56;
  }

  @override
  double charAdvanceEm(String char) {
    if (char == ' ') return 0.26;
    final sym = symbolOfLetter(char);
    if (sym != null) return symbolAdvanceEm(sym);
    if (_finalToBase.containsKey(char)) return 0.52;
    if (_gereshMarks.contains(char.runes.first)) return 0.2;
    if (_gershayimMarks.contains(char.runes.first)) return 0.3;
    if (RegExp(r'[0-9]').hasMatch(char)) return 0.55;
    return 0.4;
  }

  @override
  String symbolName(int symbol) => _names[symbol];

  @override
  String multiWordSuffix(int wordCount) =>
      wordCount == 2 ? '(2 מילים)' : '($wordCount מילים)';
}
