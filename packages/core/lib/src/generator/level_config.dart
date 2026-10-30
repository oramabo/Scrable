import 'dart:math' as math;

import '../model/geometry.dart';

/// Tunable generation parameters for one difficulty level.
class LevelConfig {
  const LevelConfig({
    required this.level,
    required this.rows,
    required this.cols,
    required this.targetWords,
    required this.maxWordLen,
    required this.max2LetterShare,
    required this.maxWordDifficulty,
    required this.meanDifficultyMin,
    required this.meanDifficultyMax,
    required this.minCheckedRatio,
    required this.maxBentArrows,
    required this.allowedArrows,
    required this.clueDifficultyMin,
    required this.clueDifficultyMax,
    required this.allowMultiword,
    required this.allowProper,
    required this.parSeconds,
    required this.letterDensityTarget,
    this.scoreMin = 0,
    this.scoreMax = 100,
    this.borderLetters = 0,
    this.lengthMid,
  });

  final int level;
  final int rows;
  final int cols;
  final int targetWords;
  final int maxWordLen;
  final double max2LetterShare;
  final double maxWordDifficulty;
  final double meanDifficultyMin;
  final double meanDifficultyMax;
  final double minCheckedRatio;
  final int maxBentArrows;
  final List<Arrow> allowedArrows;
  final double clueDifficultyMin;
  final double clueDifficultyMax;
  final bool allowMultiword;
  final bool allowProper;
  final int parSeconds;
  final double letterDensityTarget;
  final double scoreMin;
  final double scoreMax;

  /// Number of border cells (top row / first column) flipped to letters to
  /// force bent arrows.
  final int borderLetters;

  /// Centre of the word-length distribution used when drawing layouts.
  /// Defaults to a Hebrew-tuned value; English words are longer.
  final double? lengthMid;

  double get effectiveLengthMid => lengthMid ?? (3.0 + (level - 1) * 0.6);

  double get meanDifficultyTarget => (meanDifficultyMin + meanDifficultyMax) / 2;

  LevelConfig copyWith({int? rows, int? cols, int? targetWords, int? maxWordLen, double? max2LetterShare, double? lengthMid, double? minCheckedRatio, double? letterDensityTarget, int? maxBentArrows, int? borderLetters, double? maxWordDifficulty, bool? allowMultiword, bool? allowProper}) => LevelConfig(
        level: level,
        rows: rows ?? this.rows,
        cols: cols ?? this.cols,
        targetWords: targetWords ?? this.targetWords,
        maxWordLen: maxWordLen ?? this.maxWordLen,
        max2LetterShare: max2LetterShare ?? this.max2LetterShare,
        maxWordDifficulty: maxWordDifficulty ?? this.maxWordDifficulty,
        meanDifficultyMin: meanDifficultyMin,
        meanDifficultyMax: meanDifficultyMax,
        minCheckedRatio: minCheckedRatio ?? this.minCheckedRatio,
        maxBentArrows: maxBentArrows ?? this.maxBentArrows,
        allowedArrows: allowedArrows,
        clueDifficultyMin: clueDifficultyMin,
        clueDifficultyMax: clueDifficultyMax,
        allowMultiword: allowMultiword ?? this.allowMultiword,
        allowProper: allowProper ?? this.allowProper,
        parSeconds: parSeconds,
        letterDensityTarget: letterDensityTarget ?? this.letterDensityTarget,
        scoreMin: scoreMin,
        scoreMax: scoreMax,
        borderLetters: borderLetters ?? this.borderLetters,
        lengthMid: lengthMid ?? this.lengthMid,
      );

  static const List<Arrow> straight = [Arrow.a, Arrow.d];
  static const List<Arrow> withBent = [Arrow.a, Arrow.d, Arrow.da, Arrow.ad];

  /// Rules per level as tuned on the original small grids (9×7 … 17×13).
  static const Map<int, LevelConfig> _tuned = {
    1: LevelConfig(level: 1, rows: 9, cols: 7, targetWords: 16, maxWordLen: 6, max2LetterShare: 0.35, maxWordDifficulty: 0.45, meanDifficultyMin: 0.10, meanDifficultyMax: 0.32, minCheckedRatio: 0.60, maxBentArrows: 4, allowedArrows: withBent, clueDifficultyMin: 0.0, clueDifficultyMax: 0.55, allowMultiword: false, allowProper: false, parSeconds: 300, letterDensityTarget: 0.62, scoreMin: 0, scoreMax: 30, borderLetters: 2),
    2: LevelConfig(level: 2, rows: 10, cols: 8, targetWords: 22, maxWordLen: 7, max2LetterShare: 0.30, maxWordDifficulty: 0.58, meanDifficultyMin: 0.22, meanDifficultyMax: 0.42, minCheckedRatio: 0.58, maxBentArrows: 5, allowedArrows: withBent, clueDifficultyMin: 0.0, clueDifficultyMax: 0.65, allowMultiword: false, allowProper: false, parSeconds: 480, letterDensityTarget: 0.64, scoreMin: 15, scoreMax: 45, borderLetters: 3),
    3: LevelConfig(level: 3, rows: 12, cols: 9, targetWords: 30, maxWordLen: 8, max2LetterShare: 0.25, maxWordDifficulty: 0.72, meanDifficultyMin: 0.35, meanDifficultyMax: 0.56, minCheckedRatio: 0.55, maxBentArrows: 7, allowedArrows: withBent, clueDifficultyMin: 0.1, clueDifficultyMax: 0.8, allowMultiword: true, allowProper: true, parSeconds: 840, letterDensityTarget: 0.66, scoreMin: 35, scoreMax: 65, borderLetters: 3),
    4: LevelConfig(level: 4, rows: 14, cols: 10, targetWords: 39, maxWordLen: 9, max2LetterShare: 0.20, maxWordDifficulty: 0.86, meanDifficultyMin: 0.48, meanDifficultyMax: 0.68, minCheckedRatio: 0.50, maxBentArrows: 9, allowedArrows: withBent, clueDifficultyMin: 0.2, clueDifficultyMax: 0.9, allowMultiword: true, allowProper: true, parSeconds: 1500, letterDensityTarget: 0.68, scoreMin: 55, scoreMax: 82, borderLetters: 4),
    5: LevelConfig(level: 5, rows: 15, cols: 11, targetWords: 50, maxWordLen: 10, max2LetterShare: 0.15, maxWordDifficulty: 1.0, meanDifficultyMin: 0.58, meanDifficultyMax: 0.82, minCheckedRatio: 0.45, maxBentArrows: 99, allowedArrows: withBent, clueDifficultyMin: 0.3, clueDifficultyMax: 1.0, allowMultiword: true, allowProper: true, parSeconds: 2400, letterDensityTarget: 0.70, scoreMin: 70, scoreMax: 100, borderLetters: 4),
    6: LevelConfig(level: 6, rows: 17, cols: 13, targetWords: 68, maxWordLen: 11, max2LetterShare: 0.12, maxWordDifficulty: 1.0, meanDifficultyMin: 0.65, meanDifficultyMax: 0.9, minCheckedRatio: 0.45, maxBentArrows: 99, allowedArrows: withBent, clueDifficultyMin: 0.4, clueDifficultyMax: 1.0, allowMultiword: true, allowProper: true, parSeconds: 3000, letterDensityTarget: 0.70, scoreMin: 80, scoreMax: 100, borderLetters: 4),
  };

  /// Grid side per level: 15×15 at level 1, three more per level up to 30×30.
  static int sizeFor(int level) => 12 + 3 * level;

  /// Default table (rows × cols are the Hebrew geometry; English gets an
  /// extra column from level 3 up, see [forLanguage]): each level's tuned
  /// rules scaled to its grid size, see [scaledTo].
  static final Map<int, LevelConfig> defaults = {
    for (final e in _tuned.entries) e.key: e.value.scaledTo(sizeFor(e.key), sizeFor(e.key)),
  };

  /// The same level rules on another grid size: word count and par time scale
  /// with the area, bent arrows and border letters with the perimeter.
  LevelConfig scaledTo(int rows, int cols) {
    final area = rows * cols / (this.rows * this.cols);
    final perimeter = (rows + cols) / (this.rows + this.cols);
    return LevelConfig(
      level: level,
      rows: rows,
      cols: cols,
      targetWords: (targetWords * area).round(),
      maxWordLen: maxWordLen,
      max2LetterShare: max2LetterShare,
      maxWordDifficulty: maxWordDifficulty,
      meanDifficultyMin: meanDifficultyMin,
      meanDifficultyMax: meanDifficultyMax,
      minCheckedRatio: minCheckedRatio,
      maxBentArrows: (maxBentArrows * perimeter).ceil(),
      allowedArrows: allowedArrows,
      clueDifficultyMin: clueDifficultyMin,
      clueDifficultyMax: clueDifficultyMax,
      allowMultiword: allowMultiword,
      allowProper: allowProper,
      parSeconds: (parSeconds * area).round(),
      letterDensityTarget: letterDensityTarget,
      scoreMin: scoreMin,
      scoreMax: scoreMax,
      borderLetters: (borderLetters * perimeter).ceil(),
      lengthMid: lengthMid,
    );
  }

  static LevelConfig forLanguage(String lang, int level) {
    final base = defaults[level];
    if (base == null) throw ArgumentError.value(level, 'level');
    if (lang == 'en') {
      // English answers are longer and two-letter words are scarce.
      // English has only ~55 usable two-letter words, so English grids avoid two-letter runs entirely.
      // English letter statistics make big dense grids hard to fill, and every
      // level is a big grid now: looser checking and more clue cells throughout.
      final en = base.copyWith(
        max2LetterShare: 0.0,
        lengthMid: base.effectiveLengthMid + 1.4,
        minCheckedRatio: base.minCheckedRatio - 0.1,
        letterDensityTarget: base.letterDensityTarget - 0.06,
      );
      // Level 1's 15×15 rarely anneals with 6-letter words at most (~1 in 5).
      final wide = level >= 3
          ? en.copyWith(cols: base.cols + 1, maxWordLen: base.maxWordLen + 1)
          : level == 1
              ? en.copyWith(maxWordLen: base.maxWordLen + 1)
              : en;
      // Big English grids only fill with short words: below ~0.33 words per
      // cell (average answer ≥ 4.7 letters) the fill search runs out, so the
      // word target never drops under 0.35 per cell. Level 1's 15×15 cannot
      // anneal that many words; 0.29 per cell is what it reaches reliably.
      final floor = (wide.rows * wide.cols * (level == 1 ? 0.29 : 0.35)).round();
      return wide.copyWith(targetWords: math.max((base.targetWords * (level >= 3 ? 1.1 : 1.0)).round(), floor));
    }
    return base;
  }

  /// Highest level random (on-device) puzzles offer: level 5 builds in about
  /// a second on a PC, level 6 grids take several, which a phone should not
  /// spend behind a spinner.
  static int maxDeviceLevel(String lang) => 5;

  /// Daily grid side: both variants are 25×25, a step up from the packs'
  /// early levels and below the expert ones.
  static const dailySize = 25;

  /// Daily variants reuse level rules (level 2 easy, level 5 hard) on the
  /// daily grid size.
  static LevelConfig dailyEasy(String lang) {
    final cfg = forLanguage(lang, 2).scaledTo(dailySize, dailySize);
    // Level 2's ~0.27 words per cell leaves long answers that rarely fill a
    // 25×25 grid; 10% more (shorter) words fill reliably and score easier.
    return lang == 'en' ? cfg : cfg.copyWith(targetWords: (cfg.targetWords * 1.1).round());
  }
  static LevelConfig dailyHard(String lang) => forLanguage(lang, 5).scaledTo(dailySize, dailySize);
}
