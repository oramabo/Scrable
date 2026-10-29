import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Deterministic xoshiro128** generator seeded from bytes. Used everywhere in
/// the generator so a puzzle is reproducible from its seed.
class SeededRandom {
  SeededRandom.fromBytes(List<int> bytes) {
    final h = sha256.convert(bytes).bytes;
    final bd = ByteData.sublistView(Uint8List.fromList(h));
    for (var i = 0; i < 4; i++) {
      _s[i] = bd.getUint32(i * 4, Endian.little);
    }
    if (_s.every((v) => v == 0)) _s[0] = 1;
  }

  factory SeededRandom.fromString(String seed) => SeededRandom.fromBytes(utf8.encode(seed));

  /// Sub-stream for an attempt or component, independent of the parent.
  SeededRandom fork(String label) => SeededRandom.fromString('${stateHex()}|$label');

  final Uint32List _s = Uint32List(4);

  static int _rotl(int x, int k) => ((x << k) | (x >> (32 - k))) & 0xFFFFFFFF;

  int nextUint32() {
    final result = (_rotl((_s[1] * 5) & 0xFFFFFFFF, 7) * 9) & 0xFFFFFFFF;
    final t = (_s[1] << 9) & 0xFFFFFFFF;
    _s[2] ^= _s[0];
    _s[3] ^= _s[1];
    _s[1] ^= _s[2];
    _s[0] ^= _s[3];
    _s[2] ^= t;
    _s[3] = _rotl(_s[3], 11);
    return result;
  }

  /// Uniform integer in `[0, max)`.
  int nextInt(int max) {
    if (max <= 0) throw ArgumentError.value(max, 'max');
    return nextUint32() % max;
  }

  /// Uniform double in `[0, 1)`.
  double nextDouble() => nextUint32() / 4294967296.0;

  bool nextBool() => nextUint32() & 1 == 1;

  void shuffle<T>(List<T> list) {
    for (var i = list.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final t = list[i];
      list[i] = list[j];
      list[j] = t;
    }
  }

  T pick<T>(List<T> list) => list[nextInt(list.length)];

  String stateHex() => _s.map((v) => v.toRadixString(16).padLeft(8, '0')).join();
}

/// Seeds for dailies and packs. The daily secret keeps outsiders from
/// pre-computing future puzzles; packs are seeded from their identity.
class Seeds {
  static String daily({required String secret, required String lang, required String date, required String variant}) {
    final mac = Hmac(sha256, utf8.encode(secret));
    return mac.convert(utf8.encode('$lang|$date|$variant')).toString().substring(0, 32);
  }

  static String pack({required String lang, required int level, required int pack, required int index, String salt = ''}) =>
      sha256.convert(utf8.encode('$lang|L$level|P$pack|#$index|$salt')).toString().substring(0, 32);
}
