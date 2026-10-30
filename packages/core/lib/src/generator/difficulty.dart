import 'dart:math' as math;

import '../model/puzzle.dart';
import 'layout.dart';
import 'lexicon.dart';

/// Hand-set weights of the logistic difficulty model (v1). Recalibrated from
/// telemetry later; stored with the puzzle so old scores stay reproducible.
/// v1: grids grew from 16–68 words to 100–280, so the word count term is
/// centred on the level-1 size (100 words) with a weight that gives the
/// biggest grid about the boost the old biggest grid had, and bent arrows
/// count per 16 words.
class DifficultyWeights {
  const DifficultyWeights({
    this.bias = -3.2,
    this.meanWordDiff = 3.0,
    this.p90WordDiff = 1.2,
    this.meanClueDiff = 1.5,
    this.wordCount = 0.006,
    this.avgLen = 0.6,
    this.checkedRatio = -1.5,
    this.properShare = 1.0,
    this.multiwordShare = 0.8,
    this.bentArrows = 0.1,
    this.twoLetterShare = -1.0,
  });

  final double bias, meanWordDiff, p90WordDiff, meanClueDiff, wordCount, avgLen, checkedRatio, properShare, multiwordShare, bentArrows, twoLetterShare;
}

class DifficultyModel {
  const DifficultyModel({this.weights = const DifficultyWeights()});
  final DifficultyWeights weights;

  PuzzleDifficulty score({required List<LexWord> words, required List<LexClue> clues, required LayoutStats layout, int pictureClues = 0}) {
    final diffs = words.map((w) => w.difficulty).toList()..sort();
    final mean = diffs.isEmpty ? 0.0 : diffs.reduce((a, b) => a + b) / diffs.length;
    final p90 = diffs.isEmpty ? 0.0 : diffs[((diffs.length - 1) * 0.9).round()];
    // picture clues read as easy clues (0.25) whatever the textual record behind them
    final clueSum = clues.map((c) => c.difficulty).fold(0.0, (a, b) => a + b);
    final clueMean = clues.isEmpty ? 0.0 : (clueSum - clueSum / clues.length * pictureClues + 0.25 * pictureClues) / clues.length;
    final avgLen = words.isEmpty ? 0.0 : words.map((w) => w.length).reduce((a, b) => a + b) / words.length;
    final proper = words.isEmpty ? 0.0 : words.where((w) => w.isProper).length / words.length;
    final multi = words.isEmpty ? 0.0 : words.where((w) => w.isMultiword).length / words.length;
    final w = weights;
    final z = w.bias +
        w.meanWordDiff * mean +
        w.p90WordDiff * p90 +
        w.meanClueDiff * clueMean +
        w.wordCount * (layout.wordCount - 100) +
        w.avgLen * (avgLen - 3.5) +
        w.checkedRatio * (layout.checkedRatio - 0.7) +
        w.properShare * proper +
        w.multiwordShare * multi +
        w.bentArrows * (layout.wordCount == 0 ? 0 : layout.bentArrows * 16 / layout.wordCount) +
        w.twoLetterShare * layout.twoLetterShare;
    final score = 100 / (1 + math.exp(-z));
    return PuzzleDifficulty(
      score: double.parse(score.toStringAsFixed(1)),
      band: PuzzleDifficulty.bandFor(score),
      features: {
        'meanWordDiff': _r(mean),
        'p90WordDiff': _r(p90),
        'meanClueDiff': _r(clueMean),
        'wordCount': layout.wordCount.toDouble(),
        'avgLen': _r(avgLen),
        'checkedRatio': _r(layout.checkedRatio),
        'properShare': _r(proper),
        'multiwordShare': _r(multi),
        'bentArrows': layout.bentArrows.toDouble(),
        'twoLetterShare': _r(layout.twoLetterShare),
        'uncheckedLetters': layout.uncheckedLetters.toDouble(),
      },
    );
  }

  static double _r(double v) => double.parse(v.toStringAsFixed(3));

  /// Rough par time in seconds from the score and word count.
  static int parSeconds(double score, int wordCount) => (wordCount * (12 + score * 0.5)).round();

}
