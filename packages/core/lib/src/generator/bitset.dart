import 'dart:typed_data';

/// Fixed-size bitset over word indices.
class Bitset {
  Bitset(this.length) : _w = Uint32List((length + 31) >> 5);
  Bitset._(this.length, this._w);

  factory Bitset.full(int length) {
    final b = Bitset(length);
    for (var i = 0; i < b._w.length; i++) {
      b._w[i] = 0xFFFFFFFF;
    }
    b._trim();
    return b;
  }

  final int length;
  final Uint32List _w;

  /// Number of 32-bit words: the cost of one pass over the set.
  int get wordCount => _w.length;

  void _trim() {
    final rem = length & 31;
    if (rem != 0 && _w.isNotEmpty) _w[_w.length - 1] &= (1 << rem) - 1;
  }

  static int _pop(int v) {
    v = v - ((v >> 1) & 0x55555555);
    v = (v & 0x33333333) + ((v >> 2) & 0x33333333);
    return (((v + (v >> 4)) & 0x0F0F0F0F) * 0x01010101 & 0xFFFFFFFF) >> 24;
  }

  bool get(int i) => (_w[i >> 5] >> (i & 31)) & 1 == 1;
  void set(int i) => _w[i >> 5] |= 1 << (i & 31);
  void clear(int i) => _w[i >> 5] &= ~(1 << (i & 31));

  void clearAll() {
    for (var i = 0; i < _w.length; i++) {
      _w[i] = 0;
    }
  }

  Bitset copy() => Bitset._(length, Uint32List.fromList(_w));

  Bitset and(Bitset o) {
    final r = Bitset(length);
    for (var i = 0; i < _w.length; i++) {
      r._w[i] = _w[i] & o._w[i];
    }
    return r;
  }

  /// `this ∖ o` as a new set.
  Bitset andNot(Bitset o) {
    final r = Bitset(length);
    for (var i = 0; i < _w.length; i++) {
      r._w[i] = _w[i] & ~o._w[i];
    }
    return r;
  }

  void andInPlace(Bitset o) {
    for (var i = 0; i < _w.length; i++) {
      _w[i] &= o._w[i];
    }
  }

  void andNotInPlace(Bitset o) {
    for (var i = 0; i < _w.length; i++) {
      _w[i] &= ~o._w[i];
    }
  }

  void orInPlace(Bitset o) {
    for (var i = 0; i < _w.length; i++) {
      _w[i] |= o._w[i];
    }
  }

  bool get isEmpty {
    for (final v in _w) {
      if (v != 0) return false;
    }
    return true;
  }

  int get cardinality {
    var n = 0;
    for (final v in _w) {
      n += _pop(v);
    }
    return n;
  }

  /// `|this ∖ not|` without materialising the difference.
  int cardinalityAndNot(Bitset not) {
    var n = 0;
    for (var i = 0; i < _w.length; i++) {
      n += _pop(_w[i] & ~not._w[i]);
    }
    return n;
  }

  /// `|this ∩ and ∖ not|` in one pass.
  int cardinalityAndAndNot(Bitset and, Bitset not) {
    var n = 0;
    for (var i = 0; i < _w.length; i++) {
      n += _pop(_w[i] & and._w[i] & ~not._w[i]);
    }
    return n;
  }

  /// First set bit at or after [from], or -1.
  int nextSetBit(int from) {
    if (from >= length) return -1;
    var wi = from >> 5;
    var word = _w[wi] & (~0 << (from & 31)) & 0xFFFFFFFF;
    while (true) {
      if (word != 0) {
        final idx = (wi << 5) + (word & -word).bitLength - 1;
        return idx < length ? idx : -1;
      }
      wi++;
      if (wi >= _w.length) return -1;
      word = _w[wi];
    }
  }

  void forEachSet(void Function(int i) f) {
    var i = nextSetBit(0);
    while (i >= 0) {
      f(i);
      i = nextSetBit(i + 1);
    }
  }

  /// Calls [f] for each member of `this ∖ not`, in increasing order.
  void forEachSetAndNot(Bitset not, void Function(int i) f) {
    for (var wi = 0; wi < _w.length; wi++) {
      var word = _w[wi] & ~not._w[wi];
      while (word != 0) {
        final low = word & -word;
        f((wi << 5) + low.bitLength - 1);
        word ^= low;
      }
    }
  }

  List<int> toList() {
    final out = <int>[];
    forEachSet(out.add);
    return out;
  }
}
