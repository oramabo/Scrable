import 'package:collection/collection.dart';

import 'geometry.dart';

enum PuzzleKind {
  pack('pack'),
  daily('daily'),
  tutorial('tutorial'),
  practice('practice');

  const PuzzleKind(this.code);
  final String code;
  static PuzzleKind fromCode(String code) =>
      PuzzleKind.values.firstWhere((v) => v.code == code, orElse: () => throw FormatException('unknown kind $code'));
}

enum DailyVariant {
  easy('easy'),
  hard('hard');

  const DailyVariant(this.code);
  final String code;
  static DailyVariant fromCode(String code) =>
      DailyVariant.values.firstWhere((v) => v.code == code, orElse: () => throw FormatException('unknown variant $code'));
}

class DailyInfo {
  const DailyInfo({required this.date, required this.variant});

  /// ISO date `YYYY-MM-DD`.
  final String date;
  final DailyVariant variant;

  Map<String, dynamic> toJson() => {'date': date, 'variant': variant.code};
  static DailyInfo fromJson(Map<String, dynamic> j) =>
      DailyInfo(date: j['date'] as String, variant: DailyVariant.fromCode(j['variant'] as String));
}

class PackRef {
  const PackRef({required this.id, required this.index});
  final String id;

  /// 1-based position inside the pack.
  final int index;

  Map<String, dynamic> toJson() => {'id': id, 'index': index};
  static PackRef fromJson(Map<String, dynamic> j) => PackRef(id: j['id'] as String, index: j['index'] as int);
}

/// One clue inside a clue cell.
class ClueSlot {
  const ClueSlot({
    required this.pos,
    required this.wordId,
    required this.arrow,
    required this.text,
    required this.lines,
  });

  final SlotPos pos;
  final String wordId;
  final Arrow arrow;

  /// Full clue text (shown in the clue bar).
  final String text;

  /// Pre-broken lines for the in-cell rendering.
  final List<String> lines;

  Map<String, dynamic> toJson() => {
        'pos': pos.code,
        'wordId': wordId,
        'arrow': arrow.code,
        'text': text,
        'lines': lines,
      };

  static ClueSlot fromJson(Map<String, dynamic> j) => ClueSlot(
        pos: SlotPos.fromCode(j['pos'] as String),
        wordId: j['wordId'] as String,
        arrow: Arrow.fromCode(j['arrow'] as String),
        text: j['text'] as String,
        lines: (j['lines'] as List).cast<String>(),
      );
}

class ClueCell {
  const ClueCell({required this.pos, required this.slots});
  final Pos pos;
  final List<ClueSlot> slots;

  Map<String, dynamic> toJson() => {'r': pos.r, 'c': pos.c, 'slots': slots.map((s) => s.toJson()).toList()};
  static ClueCell fromJson(Map<String, dynamic> j) => ClueCell(
        pos: Pos(j['r'] as int, j['c'] as int),
        slots: (j['slots'] as List).map((s) => ClueSlot.fromJson(s as Map<String, dynamic>)).toList(),
      );
}

class PuzzleWord {
  const PuzzleWord({
    required this.id,
    required this.dir,
    required this.start,
    required this.len,
    required this.clueCell,
    required this.arrow,
    this.clueId,
    this.lemmaId,
    this.wordCount = 1,
    this.difficulty = 0,
  });

  final String id;
  final Dir dir;
  final Pos start;
  final int len;
  final Pos clueCell;
  final Arrow arrow;
  final String? clueId;
  final String? lemmaId;
  final int wordCount;
  final double difficulty;

  /// Grid position of the k-th letter.
  Pos cellAt(int k) => start.step(dir, k);

  List<Pos> get cells => [for (var k = 0; k < len; k++) cellAt(k)];

  Map<String, dynamic> toJson() => {
        'id': id,
        'dir': dir == Dir.across ? 'A' : 'D',
        'start': start.toJson(),
        'len': len,
        'clueCell': clueCell.toJson(),
        'arrow': arrow.code,
        if (clueId != null) 'clueId': clueId,
        if (lemmaId != null) 'lemmaId': lemmaId,
        'wordCount': wordCount,
        'difficulty': difficulty,
      };

  static PuzzleWord fromJson(Map<String, dynamic> j) => PuzzleWord(
        id: j['id'] as String,
        dir: (j['dir'] as String) == 'A' ? Dir.across : Dir.down,
        start: Pos.fromJson(j['start'] as Map<String, dynamic>),
        len: j['len'] as int,
        clueCell: Pos.fromJson(j['clueCell'] as Map<String, dynamic>),
        arrow: Arrow.fromCode(j['arrow'] as String),
        clueId: j['clueId'] as String?,
        lemmaId: j['lemmaId'] as String?,
        wordCount: (j['wordCount'] as int?) ?? 1,
        difficulty: ((j['difficulty'] as num?) ?? 0).toDouble(),
      );
}

class PuzzleDifficulty {
  const PuzzleDifficulty({required this.score, required this.band, this.features = const {}});
  final double score;
  final String band;
  final Map<String, double> features;

  Map<String, dynamic> toJson() => {'score': score, 'band': band, 'features': features};
  static PuzzleDifficulty fromJson(Map<String, dynamic> j) => PuzzleDifficulty(
        score: (j['score'] as num).toDouble(),
        band: j['band'] as String,
        features: ((j['features'] as Map?) ?? {}).map((k, v) => MapEntry(k as String, (v as num).toDouble())),
      );

  static String bandFor(double score) {
    if (score < 20) return 'starter';
    if (score < 40) return 'easy';
    if (score < 60) return 'medium';
    if (score < 80) return 'hard';
    return 'expert';
  }
}

class GeneratorInfo {
  const GeneratorInfo({required this.version, required this.seed, this.templateId, this.dictSnapshot});
  final String version;
  final String seed;
  final String? templateId;
  final String? dictSnapshot;

  Map<String, dynamic> toJson() => {
        'version': version,
        'seed': seed,
        if (templateId != null) 'templateId': templateId,
        if (dictSnapshot != null) 'dictSnapshot': dictSnapshot,
      };
  static GeneratorInfo fromJson(Map<String, dynamic> j) => GeneratorInfo(
        version: j['version'] as String,
        seed: j['seed'] as String,
        templateId: j['templateId'] as String?,
        dictSnapshot: j['dictSnapshot'] as String?,
      );
}

class PuzzleMeta {
  const PuzzleMeta({
    this.generator,
    this.author,
    this.reviewer,
    this.createdAt,
    this.publishedAt,
    this.version = 1,
    this.checksum,
  });
  final GeneratorInfo? generator;
  final String? author;
  final String? reviewer;
  final String? createdAt;
  final String? publishedAt;
  final int version;
  final String? checksum;

  PuzzleMeta copyWith({String? checksum, String? publishedAt, int? version}) => PuzzleMeta(
        generator: generator,
        author: author,
        reviewer: reviewer,
        createdAt: createdAt,
        publishedAt: publishedAt ?? this.publishedAt,
        version: version ?? this.version,
        checksum: checksum ?? this.checksum,
      );

  Map<String, dynamic> toJson() => {
        if (generator != null) 'generator': generator!.toJson(),
        if (author != null) 'author': author,
        if (reviewer != null) 'reviewer': reviewer,
        if (createdAt != null) 'createdAt': createdAt,
        if (publishedAt != null) 'publishedAt': publishedAt,
        'version': version,
        if (checksum != null) 'checksum': checksum,
      };
  static PuzzleMeta fromJson(Map<String, dynamic> j) => PuzzleMeta(
        generator: j['generator'] == null ? null : GeneratorInfo.fromJson(j['generator'] as Map<String, dynamic>),
        author: j['author'] as String?,
        reviewer: j['reviewer'] as String?,
        createdAt: j['createdAt'] as String?,
        publishedAt: j['publishedAt'] as String?,
        version: (j['version'] as int?) ?? 1,
        checksum: j['checksum'] as String?,
      );
}

/// A complete arrowword puzzle: shape, clue cells, words and solution.
class Puzzle {
  Puzzle({
    required this.id,
    required this.lang,
    required this.kind,
    required this.level,
    required this.shape,
    required this.clueCells,
    required this.words,
    required List<int> solution,
    required this.difficulty,
    this.meta = const PuzzleMeta(),
    this.daily,
    this.pack,
    this.title,
    this.schemaVersion = 1,
  })  : solution = List.unmodifiable(solution),
        wordById = {for (final w in words) w.id: w},
        index = WordIndex.build(shape, words) {
    if (solution.length != shape.cellCount) {
      throw ArgumentError('solution has ${solution.length} entries for ${shape.cellCount} cells');
    }
  }

  final int schemaVersion;
  final String id;
  final String lang;
  final PuzzleKind kind;
  final int level;
  final DailyInfo? daily;
  final PackRef? pack;
  final String? title;
  final GridShape shape;
  final List<ClueCell> clueCells;
  final List<PuzzleWord> words;

  /// One entry per grid cell (row-major): the symbol id for letter cells,
  /// `-1` for clue cells.
  final List<int> solution;
  final PuzzleDifficulty difficulty;
  final PuzzleMeta meta;

  final Map<String, PuzzleWord> wordById;
  final WordIndex index;

  int get rows => shape.rows;
  int get cols => shape.cols;

  int solutionAt(Pos p) => solution[shape.indexOf(p)];

  /// Symbols of a word's answer in grid order.
  List<int> answerOf(PuzzleWord w) => [for (final p in w.cells) solutionAt(p)];

  ClueSlot? slotForWord(String wordId) {
    for (final cell in clueCells) {
      final slot = cell.slots.firstWhereOrNull((s) => s.wordId == wordId);
      if (slot != null) return slot;
    }
    return null;
  }

  /// Clue text for a word, or empty.
  String clueTextOf(String wordId) => slotForWord(wordId)?.text ?? '';

  /// Letter cell indices in row-major order.
  List<int> get letterCellIndices =>
      [for (var i = 0; i < shape.cellCount; i++) if (shape.kinds[i] == CellKind.letter) i];

  Puzzle copyWith({PuzzleMeta? meta, List<ClueCell>? clueCells, List<PuzzleWord>? words, PuzzleDifficulty? difficulty}) => Puzzle(
        id: id,
        lang: lang,
        kind: kind,
        level: level,
        shape: shape,
        clueCells: clueCells ?? this.clueCells,
        words: words ?? this.words,
        solution: solution,
        difficulty: difficulty ?? this.difficulty,
        meta: meta ?? this.meta,
        daily: daily,
        pack: pack,
        title: title,
        schemaVersion: schemaVersion,
      );
}

/// Maps every letter cell to the across and down words that cover it.
class WordIndex {
  WordIndex._(this.acrossOf, this.downOf);

  /// Word id per cell index, or `null`.
  final List<String?> acrossOf;
  final List<String?> downOf;

  static WordIndex build(GridShape shape, List<PuzzleWord> words) {
    final across = List<String?>.filled(shape.cellCount, null);
    final down = List<String?>.filled(shape.cellCount, null);
    for (final w in words) {
      for (final p in w.cells) {
        final i = shape.indexOf(p);
        if (w.dir == Dir.across) {
          across[i] = w.id;
        } else {
          down[i] = w.id;
        }
      }
    }
    return WordIndex._(across, down);
  }

  String? wordAt(int cell, Dir dir) => dir == Dir.across ? acrossOf[cell] : downOf[cell];

  /// Word ids covering a cell (0, 1 or 2 entries).
  List<String> wordsAt(int cell) => [
        if (acrossOf[cell] != null) acrossOf[cell]!,
        if (downOf[cell] != null) downOf[cell]!,
      ];

  /// Whether the cell belongs to two words.
  bool isChecked(int cell) => acrossOf[cell] != null && downOf[cell] != null;
}
