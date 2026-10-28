import 'bitset.dart';
import 'lexicon.dart';

/// Pattern index: for each word length, a bitset per (position, symbol).
class DictionaryIndex {
  DictionaryIndex(this.lexicon, {this.minLen = 2, this.maxLen = 14}) {
    final alphabet = lexicon.lang.alphabetSize;
    for (var len = minLen; len <= maxLen; len++) {
      byLen[len] = [];
    }
    for (final w in lexicon.words) {
      if (w.length < minLen || w.length > maxLen) continue;
      if (w.status == 'retired' || w.blocked) continue;
      w.dictIndex = byLen[w.length]!.length;
      byLen[w.length]!.add(w);
    }
    for (var len = minLen; len <= maxLen; len++) {
      final words = byLen[len]!;
      final n = words.length;
      final table = List.generate(len, (_) => List.generate(alphabet, (_) => Bitset(n)));
      final counts = List.generate(len, (_) => List<int>.filled(alphabet, 0));
      for (var i = 0; i < n; i++) {
        final s = words[i].symbols;
        for (var p = 0; p < len; p++) {
          table[p][s[p]].set(i);
          counts[p][s[p]]++;
        }
      }
      _index[len] = table;
      letterCount[len] = counts;
    }
  }

  final Lexicon lexicon;
  final int minLen;
  final int maxLen;

  /// Words per length, in dictionary order (dictIndex = position).
  final Map<int, List<LexWord>> byLen = {};
  final Map<int, List<List<Bitset>>> _index = {};

  /// letterCount[len][pos][symbol]: how many words have symbol at pos.
  final Map<int, List<List<int>>> letterCount = {};

  final Map<String, Bitset> _cache = {};
  static const int _cacheLimit = 60000;

  int count(int len) => byLen[len]?.length ?? 0;

  /// Words matching [pattern] (`-1` = any symbol). The result must not be
  /// mutated.
  Bitset lookup(List<int> pattern) {
    final len = pattern.length;
    final key = '$len:${pattern.join(',')}';
    final cached = _cache[key];
    if (cached != null) return cached;
    final n = count(len);
    Bitset? result;
    final table = _index[len];
    if (table != null) {
      for (var p = 0; p < len; p++) {
        final sym = pattern[p];
        if (sym < 0) continue;
        final bits = table[p][sym];
        if (result == null) {
          result = bits.copy();
        } else {
          result.andInPlace(bits);
        }
        if (result.isEmpty) break;
      }
    }
    result ??= Bitset.full(n);
    if (_cache.length >= _cacheLimit) _cache.clear();
    _cache[key] = result;
    return result;
  }

  /// Number of words with [symbol] at [pos] for words of [len].
  int countAt(int len, int pos, int symbol) {
    final c = letterCount[len];
    if (c == null || pos >= len) return 0;
    return c[pos][symbol];
  }
}
