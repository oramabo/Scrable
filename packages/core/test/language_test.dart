import 'package:chetz_core/chetz_core.dart';
import 'package:test/test.dart';

void main() {
  const he = HebrewProfile();
  const en = EnglishProfile();

  group('Hebrew normalisation', () {
    test('folds final letters to base symbols', () {
      expect(he.normalize('שלום'), he.normalize('שלומ'));
      expect(he.canonicalKey(he.normalize('ארץ')!), 'ארצ');
    });
    test('fuses geresh into a single symbol and accepts variants', () {
      final a = he.normalize("ג'ינס")!;
      final b = he.normalize('ג׳ינס')!;
      expect(a, b);
      expect(a.length, 4);
      expect(a.first, HebrewProfile.baseCount + 0); // ג׳
      expect(he.symbolToDisplay(a.first), 'ג׳');
      expect(he.baseSymbol(a.first), 2);
    });
    test('drops spaces, hyphens, gershayim and niqqud', () {
      expect(he.canonicalKey(he.normalize('ים-המלח')!), 'ימהמלח');
      expect(he.canonicalKey(he.normalize('ח"כ')!), 'חכ');
      expect(he.canonicalKey(he.normalize('שָׁלוֹם')!), 'שלומ');
    });
    test('rejects foreign characters', () {
      expect(he.normalize('abc'), isNull);
      expect(he.normalize('שלום1'), isNull);
    });
    test('final display forms', () {
      final mem = he.normalize('מ')!.first;
      expect(he.hasFinalForm(mem), isTrue);
      expect(he.symbolToFinalDisplay(mem), 'ם');
      expect(he.symbolToFinalDisplay(he.normalize('א')!.first), 'א');
    });
    test('keyboard layouts cover all 22 letters', () {
      for (final layout in he.keyboardLayouts) {
        final symbols = {for (final row in layout.rows) for (final k in row) k.symbol};
        expect(symbols.length, 22, reason: layout.id);
      }
    });
  });

  group('English normalisation', () {
    test('uppercases and strips punctuation and diacritics', () {
      expect(en.canonicalKey(en.normalize("O'Neill")!), 'ONEILL');
      expect(en.canonicalKey(en.normalize('café')!), 'CAFE');
      expect(en.canonicalKey(en.normalize('ice cream')!), 'ICECREAM');
    });
    test('rejects digits', () => expect(en.normalize('R2D2'), isNull));
    test('qwerty layout has 26 keys', () {
      final symbols = {for (final row in en.keyboardLayouts.first.rows) for (final k in row) k.symbol};
      expect(symbols.length, 26);
    });
  });
}
