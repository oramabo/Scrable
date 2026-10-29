import 'english.dart';
import 'hebrew.dart';
import 'language_profile.dart';

/// Registry of supported puzzle languages.
class Languages {
  static const HebrewProfile he = HebrewProfile();
  static const EnglishProfile en = EnglishProfile();

  static const List<LanguageProfile> all = [he, en];

  static LanguageProfile byCode(String code) {
    switch (code) {
      case 'he':
        return he;
      case 'en':
        return en;
    }
    throw ArgumentError.value(code, 'code', 'unsupported language');
  }
}
