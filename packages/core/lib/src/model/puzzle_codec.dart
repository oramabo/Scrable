import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'geometry.dart';
import 'puzzle.dart';

/// JSON (de)serialisation of puzzles, solution obfuscation and checksums.
class PuzzleCodec {
  const PuzzleCodec({this.salt = 'chetz-v1'});

  /// Salt mixed into the solution keystream. Not a secret: it only prevents
  /// casual reading of cached files.
  final String salt;

  Map<String, dynamic> toJson(Puzzle p, {bool obfuscate = true}) {
    final letterSymbols = <int>[];
    for (var i = 0; i < p.shape.cellCount; i++) {
      if (p.shape.kinds[i] == CellKind.letter) letterSymbols.add(p.solution[i]);
    }
    final json = <String, dynamic>{
      'schemaVersion': p.schemaVersion,
      'lang': p.lang,
      'id': p.id,
      'kind': p.kind.code,
      'level': p.level,
      if (p.title != null) 'title': p.title,
      if (p.daily != null) 'daily': p.daily!.toJson(),
      if (p.pack != null) 'pack': p.pack!.toJson(),
      'grid': {'rows': p.rows, 'cols': p.cols, 'colOrigin': 'readingStart'},
      'layout': p.shape.toRows(),
      'clueCells': p.clueCells.map((c) => c.toJson()).toList(),
      'words': p.words.map((w) => w.toJson()).toList(),
      'solution': obfuscate
          ? {'enc': 'xor1', 'data': base64Encode(_xor(p.id, Uint8List.fromList(letterSymbols)))}
          : {'enc': 'plain', 'data': letterSymbols},
      'difficulty': p.difficulty.toJson(),
      'meta': p.meta.toJson(),
    };
    return json;
  }

  String encode(Puzzle p, {bool obfuscate = true, bool pretty = false}) {
    final json = toJson(p, obfuscate: obfuscate);
    return pretty ? const JsonEncoder.withIndent('  ').convert(json) : jsonEncode(json);
  }

  Puzzle fromJson(Map<String, dynamic> j) {
    final grid = j['grid'] as Map<String, dynamic>;
    final shape = GridShape.fromRows((j['layout'] as List).cast<String>());
    if (shape.rows != grid['rows'] || shape.cols != grid['cols']) {
      throw const FormatException('layout does not match grid dimensions');
    }
    final sol = j['solution'] as Map<String, dynamic>;
    final enc = sol['enc'] as String;
    List<int> letterSymbols;
    if (enc == 'plain') {
      letterSymbols = (sol['data'] as List).cast<int>();
    } else if (enc == 'xor1') {
      letterSymbols = _xor(j['id'] as String, base64Decode(sol['data'] as String));
    } else {
      throw FormatException('unknown solution encoding $enc');
    }
    final solution = List<int>.filled(shape.cellCount, -1);
    var k = 0;
    for (var i = 0; i < shape.cellCount; i++) {
      if (shape.kinds[i] == CellKind.letter) {
        if (k >= letterSymbols.length) throw const FormatException('solution too short');
        solution[i] = letterSymbols[k++];
      }
    }
    if (k != letterSymbols.length) throw const FormatException('solution too long');
    return Puzzle(
      schemaVersion: (j['schemaVersion'] as int?) ?? 1,
      id: j['id'] as String,
      lang: j['lang'] as String,
      kind: PuzzleKind.fromCode(j['kind'] as String),
      level: j['level'] as int,
      title: j['title'] as String?,
      daily: j['daily'] == null ? null : DailyInfo.fromJson(j['daily'] as Map<String, dynamic>),
      pack: j['pack'] == null ? null : PackRef.fromJson(j['pack'] as Map<String, dynamic>),
      shape: shape,
      clueCells: (j['clueCells'] as List).map((c) => ClueCell.fromJson(c as Map<String, dynamic>)).toList(),
      words: (j['words'] as List).map((w) => PuzzleWord.fromJson(w as Map<String, dynamic>)).toList(),
      solution: solution,
      difficulty: PuzzleDifficulty.fromJson(j['difficulty'] as Map<String, dynamic>),
      meta: j['meta'] == null ? const PuzzleMeta() : PuzzleMeta.fromJson(j['meta'] as Map<String, dynamic>),
    );
  }

  Puzzle decode(String source) => fromJson(jsonDecode(source) as Map<String, dynamic>);

  /// SHA-256 of the canonical JSON (sorted keys, no whitespace) with
  /// `meta.checksum` removed. Independent of solution encoding.
  String checksum(Puzzle p) {
    final json = toJson(p, obfuscate: false);
    final meta = Map<String, dynamic>.from(json['meta'] as Map);
    meta.remove('checksum');
    json['meta'] = meta;
    return 'sha256:${sha256.convert(utf8.encode(canonicalJson(json)))}';
  }

  Puzzle withChecksum(Puzzle p) => p.copyWith(meta: p.meta.copyWith(checksum: checksum(p)));

  bool verifyChecksum(Puzzle p) => p.meta.checksum == null || p.meta.checksum == checksum(p);

  /// Hash of the normalised solution, used by the leaderboard submission.
  static String solutionHash(Puzzle p) {
    final letters = <int>[];
    for (var i = 0; i < p.shape.cellCount; i++) {
      if (p.shape.kinds[i] == CellKind.letter) letters.add(p.solution[i]);
    }
    return sha256.convert(utf8.encode('${p.id}|${letters.join(',')}')).toString();
  }

  Uint8List _xor(String id, Uint8List data) {
    final out = Uint8List(data.length);
    var counter = 0;
    var offset = 0;
    while (offset < data.length) {
      final block = sha256.convert(utf8.encode('$id|$salt|$counter')).bytes;
      for (var i = 0; i < block.length && offset < data.length; i++, offset++) {
        out[offset] = data[offset] ^ block[i];
      }
      counter++;
    }
    return out;
  }

  /// Deterministic JSON: object keys sorted, no insignificant whitespace.
  static String canonicalJson(Object? value) {
    final buf = StringBuffer();
    _writeCanonical(value, buf);
    return buf.toString();
  }

  static void _writeCanonical(Object? value, StringBuffer buf) {
    if (value is Map) {
      final keys = value.keys.map((k) => k.toString()).toList()..sort();
      buf.write('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) buf.write(',');
        buf.write(jsonEncode(keys[i]));
        buf.write(':');
        _writeCanonical(value[keys[i]], buf);
      }
      buf.write('}');
    } else if (value is List) {
      buf.write('[');
      for (var i = 0; i < value.length; i++) {
        if (i > 0) buf.write(',');
        _writeCanonical(value[i], buf);
      }
      buf.write(']');
    } else if (value is double) {
      // avoid 1.0 vs 1 differences across platforms
      buf.write(value == value.roundToDouble() && value.abs() < 1e15 ? value.toInt().toString() : value.toString());
    } else {
      buf.write(jsonEncode(value));
    }
  }
}
