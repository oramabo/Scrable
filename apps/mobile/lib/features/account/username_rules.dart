/// Client copy of functions/src/lib/username.ts, for instant feedback while
/// typing; the `claimUsername` callable has the final word.
abstract final class UsernameRules {
  static const minLength = 3;
  static const maxLength = 20;

  static final _pattern = RegExp(r'^[A-Za-z0-9א-ת](?:[A-Za-z0-9א-ת]|[_.](?=[A-Za-z0-9א-ת]))*$');

  static const _reserved = ['admin', 'administrator', 'moderator', 'support', 'system', 'official', 'chetz', 'player', 'חץ', 'מנהל', 'מנהלת', 'תמיכה', 'שחקן'];
  static const _finalToRegular = {'ך': 'כ', 'ם': 'מ', 'ן': 'נ', 'ף': 'פ', 'ץ': 'צ'};

  static String key(String name) =>
      name.toLowerCase().split('').map((ch) => _finalToRegular[ch] ?? ch).join().replaceAll(RegExp('[_.]'), '');

  /// `length`, `characters`, `reserved`, or null when the name may be claimed.
  static String? problem(String name) {
    if (name.length < minLength || name.length > maxLength) return 'length';
    if (!_pattern.hasMatch(name)) return 'characters';
    final k = key(name);
    if (_reserved.any((r) => key(r) == k)) return 'reserved';
    return null;
  }
}
