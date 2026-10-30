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

  /// JSON in the puzzle's [Puzzle.schemaVersion] format: 1 lists clue cells
  /// and words as objects, 2 is compact (see [_cluesV2]).
  Map<String, dynamic> toJson(Puzzle p, {bool obfuscate = true}) {
    final letterSymbols = <int>[];
    for (var i = 0; i < p.shape.cellCount; i++) {
      if (p.shape.kinds[i] == CellKind.letter) letterSymbols.add(p.solution[i]);
    }
    final v2 = p.schemaVersion >= 2;
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
      if (v2) 'clues': _cluesV2(p),
      if (!v2) 'clueCells': p.clueCells.map((c) => c.toJson()).toList(),
      if (!v2) 'words': p.words.map((w) => w.toJson()).toList(),
      'solution': obfuscate
          ? {'enc': 'xor1', 'data': base64Encode(_xor(p.id, Uint8List.fromList(letterSymbols)))}
          : {'enc': 'plain', 'data': letterSymbols},
      'difficulty': v2 ? {'score': p.difficulty.score, 'band': p.difficulty.band} : p.difficulty.toJson(),
      'meta': p.meta.toJson(),
    };
    return json;
  }

  /// Format 2: one array per clue, in clue-cell order:
  /// `[r, c, pos, arrow, len, wordId, clueId, text, difficulty, extras?]`.
  /// `pos` is `f`/`t`/`b` (full, top, bottom half); the word starts at the
  /// arrow's offset from the clue cell and runs `len` cells in the arrow's
  /// direction. `text` carries the in-cell line breaks as newlines (the clue
  /// bar shows it with spaces). `extras` is present only when needed:
  /// `{"image": {...}}` for a picture clue, `{"lines": [...]}` when the lines
  /// are not the text split at spaces. The word's lexicon entry is reached
  /// through its clue id (clue bank), so it is not repeated here.
  List<List<Object?>> _cluesV2(Puzzle p) {
    final out = <List<Object?>>[];
    for (final cell in p.clueCells) {
      for (final slot in cell.slots) {
        final w = p.wordById[slot.wordId]!;
        final Map<String, dynamic> extras;
        final String text;
        if (slot.image != null) {
          text = slot.text;
          extras = {'image': slot.image!.toJson(), if (slot.lines.isNotEmpty) 'lines': slot.lines};
        } else if (slot.lines.isNotEmpty && slot.lines.join(' ') == slot.text && !slot.text.contains('\n')) {
          text = slot.lines.join('\n');
          extras = const {};
        } else {
          text = slot.text;
          extras = {'lines': slot.lines};
        }
        out.add([
          cell.pos.r,
          cell.pos.c,
          _posCode[slot.pos],
          slot.arrow.code,
          w.len,
          w.id,
          w.clueId,
          text,
          w.difficulty,
          if (extras.isNotEmpty) extras,
        ]);
      }
    }
    return out;
  }

  static const _posCode = {SlotPos.full: 'f', SlotPos.top: 't', SlotPos.bottom: 'b'};
  static const _posFromCode = {'f': SlotPos.full, 't': SlotPos.top, 'b': SlotPos.bottom};

  /// Clue cells and words of a format-2 puzzle.
  (List<ClueCell>, List<PuzzleWord>) _fromCluesV2(List<dynamic> clues) {
    final slotsByCell = <Pos, List<ClueSlot>>{};
    final words = <PuzzleWord>[];
    for (final raw in clues) {
      final e = raw as List<dynamic>;
      if (e.length < 9) throw const FormatException('clue entry needs 9 fields');
      final cell = Pos(e[0] as int, e[1] as int);
      final pos = _posFromCode[e[2]] ?? (throw FormatException('unknown clue position ${e[2]}'));
      final arrow = Arrow.fromCode(e[3] as String);
      final wordId = e[5] as String;
      final extras = e.length > 9 ? e[9] as Map<String, dynamic> : const <String, dynamic>{};
      final image = extras['image'] == null ? null : ClueImage.fromJson(extras['image'] as Map<String, dynamic>);
      var text = e[7] as String;
      List<String> lines;
      if (extras['lines'] != null) {
        lines = (extras['lines'] as List).cast<String>();
      } else if (image != null) {
        lines = const [];
      } else {
        lines = text.split('\n');
        text = lines.join(' ');
      }
      slotsByCell.putIfAbsent(cell, () => []).add(ClueSlot(pos: pos, wordId: wordId, arrow: arrow, text: text, lines: lines, image: image));
      words.add(PuzzleWord(
        id: wordId,
        dir: arrow.dir,
        start: Pos(cell.r + arrow.startDr, cell.c + arrow.startDc),
        len: e[4] as int,
        clueCell: cell,
        arrow: arrow,
        clueId: e[6] as String?,
        difficulty: (e[8] as num).toDouble(),
      ));
    }
    // The builder's word order (across by row then column, then down by
    // column then row): clue order alone would reshuffle next-word navigation.
    words.sort((a, b) {
      if (a.dir != b.dir) return a.dir == Dir.across ? -1 : 1;
      final (major, minor) = a.dir == Dir.across ? (a.start.r - b.start.r, a.start.c - b.start.c) : (a.start.c - b.start.c, a.start.r - b.start.r);
      return major != 0 ? major : minor;
    });
    return ([for (final entry in slotsByCell.entries) ClueCell(pos: entry.key, slots: entry.value)], words);
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
    final schemaVersion = (j['schemaVersion'] as int?) ?? 1;
    final (clueCells, words) = schemaVersion >= 2
        ? _fromCluesV2(j['clues'] as List)
        : (
            (j['clueCells'] as List).map((c) => ClueCell.fromJson(c as Map<String, dynamic>)).toList(),
            (j['words'] as List).map((w) => PuzzleWord.fromJson(w as Map<String, dynamic>)).toList(),
          );
    return Puzzle(
      schemaVersion: schemaVersion,
      id: j['id'] as String,
      lang: j['lang'] as String,
      kind: PuzzleKind.fromCode(j['kind'] as String),
      level: j['level'] as int,
      title: j['title'] as String?,
      daily: j['daily'] == null ? null : DailyInfo.fromJson(j['daily'] as Map<String, dynamic>),
      pack: j['pack'] == null ? null : PackRef.fromJson(j['pack'] as Map<String, dynamic>),
      shape: shape,
      clueCells: clueCells,
      words: words,
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
