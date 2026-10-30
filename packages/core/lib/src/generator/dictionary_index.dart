import 'bitset.dart';
import 'lexicon.dart';

/// Pattern index: for each word length, a bitset per (position, symbol).
class DictionaryIndex {
  DictionaryIndex(this.lexicon, {this.minLen = 2, this.maxLen = 14}) : _base = lexicon.lang.alphabetSize + 1 {
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

  /// Per length: entries that spell the same letters as another entry (a word
  /// and a proper noun, an abbreviation), mapped to all of them. Placing one
  /// marks them all used, so no answer repeats in a grid.
  late final Map<int, Map<int, List<int>>> twins = {
    for (final entry in byLen.entries) entry.key: _twinsOf(entry.value),
  };

  static Map<int, List<int>> _twinsOf(List<LexWord> words) {
    final bySpelling = <String, List<int>>{};
    for (var i = 0; i < words.length; i++) {
      bySpelling.putIfAbsent(words[i].symbols.join(','), () => []).add(i);
    }
    return {
      for (final ids in bySpelling.values)
        if (ids.length > 1)
          for (final i in ids) i: ids,
    };
  }

  /// Pattern lookups, keyed by length then by the pattern packed in base
  /// [_base] (symbol + 1, so the wildcard is 0): up to [_packedMaxLen]
  /// positions fit a 63-bit int. Longer patterns use string keys.
  final Map<int, Map<int, Bitset>> _cache = {};
  final Map<String, Bitset> _longCache = {};
  final int _base;
  int _cached = 0;
  static const int _cacheLimit = 60000;
  static const int _packedMaxLen = 13;

  int count(int len) => byLen[len]?.length ?? 0;

  /// Per symbol, the words of [len] with it at [pos]. Not to be mutated.
  List<Bitset> symbolBitsets(int len, int pos) => _index[len]![pos];

  /// Words matching [pattern] (`-1` = any symbol). The result must not be
  /// mutated.
  Bitset lookup(List<int> pattern) {
    final len = pattern.length;
    if (len <= _packedMaxLen) {
      var key = 0;
      for (final sym in pattern) {
        key = key * _base + sym + 1;
      }
      final byKey = _cache.putIfAbsent(len, () => {});
      final cached = byKey[key];
      if (cached != null) return cached;
      final result = _compute(pattern);
      _evictIfFull();
      byKey[key] = result;
      _cached++;
      return result;
    }
    final key = '$len:${pattern.join(',')}';
    final cached = _longCache[key];
    if (cached != null) return cached;
    final result = _compute(pattern);
    _evictIfFull();
    _longCache[key] = result;
    _cached++;
    return result;
  }

  void _evictIfFull() {
    if (_cached < _cacheLimit) return;
    _cache.clear();
    _longCache.clear();
    _cached = 0;
  }

  Bitset _compute(List<int> pattern) {
    final len = pattern.length;
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
    return result ?? Bitset.full(count(len));
  }

  /// Number of words with [symbol] at [pos] for words of [len].
  int countAt(int len, int pos, int symbol) {
    final c = letterCount[len];
    if (c == null || pos >= len) return 0;
    return c[pos][symbol];
  }
}
