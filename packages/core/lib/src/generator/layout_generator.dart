import 'dart:math' as math;

import '../model/geometry.dart';
import 'layout.dart';
import 'level_config.dart';
import 'rng.dart';

/// Produces valid layout templates by simulated annealing over the set of
/// clue cells, starting from the classic arrowword border.
class LayoutGenerator {
  LayoutGenerator(this.config, {this.iterations = 12000});

  final LevelConfig config;
  final int iterations;

  late final LayoutValidator _validator = LayoutValidator(config);

  /// Run-length weights per level: easier levels favour short words.
  List<double> _lengthWeights() {
    final w = List<double>.filled(config.maxWordLen + 1, 0);
    for (var len = 2; len <= config.maxWordLen; len++) {
      final mid = config.effectiveLengthMid;
      w[len] = math.exp(-math.pow(len - mid, 2) / (2 * 1.6 * 1.6));
    }
    w[2] *= config.max2LetterShare * 2.2; // two-letter words are a spice, not a diet
    return w;
  }

  int _sampleLength(SeededRandom rng, List<double> weights, int maxLen) {
    var total = 0.0;
    for (var len = 2; len <= maxLen; len++) {
      total += weights[len];
    }
    var x = rng.nextDouble() * total;
    for (var len = 2; len <= maxLen; len++) {
      x -= weights[len];
      if (x <= 0) return len;
    }
    return maxLen;
  }

  List<CellKind> _initial(SeededRandom rng) {
    final rows = config.rows, cols = config.cols;
    final kinds = List<CellKind>.filled(rows * cols, CellKind.letter);
    for (var c = 0; c < cols; c++) {
      kinds[c] = CellKind.clue;
    }
    for (var r = 0; r < rows; r++) {
      kinds[r * cols] = CellKind.clue;
    }
    final weights = _lengthWeights();
    for (var r = 1; r < rows; r++) {
      var c = 1;
      while (c < cols) {
        final remaining = cols - c;
        if (remaining < 2) {
          // a trailing single letter would be unchecked across; make it a clue sometimes
          if (rng.nextDouble() < 0.5) kinds[r * cols + c] = CellKind.clue;
          break;
        }
        var len = _sampleLength(rng, weights, math.min(config.maxWordLen, remaining));
        if (remaining - len == 1) len = remaining; // avoid a lonely trailing cell
        c += len;
        if (c < cols) {
          kinds[r * cols + c] = CellKind.clue;
          c++;
        }
      }
    }
    // The corner clue cell can only serve a word that starts on the border, so
    // open the cell next to it; then flip a few more border cells to letters so
    // bent arrows appear and no border square stays blank.
    kinds[1] = CellKind.letter;
    for (var k = 0; k < config.borderLetters; k++) {
      if (rng.nextBool()) {
        final c = 2 + rng.nextInt(math.max(1, cols - 3));
        kinds[c] = CellKind.letter;
      } else {
        final r = 2 + rng.nextInt(math.max(1, rows - 3));
        kinds[r * cols] = CellKind.letter;
      }
    }
    return kinds;
  }

  /// Generates one template or returns `null` when annealing did not reach a
  /// valid layout within the iteration budget.
  LayoutTemplate? generate(SeededRandom rng, {required String id}) {
    final rows = config.rows, cols = config.cols;
    var kinds = _initial(rng);
    var shape = GridShape(rows, cols, kinds);
    var result = _validator.validate(shape, exact: false);
    var energy = result.energy;
    var best = kinds;
    var bestEnergy = energy;
    final t0 = 3.0, t1 = 0.05;
    for (var it = 0; it < iterations; it++) {
      final temp = t0 * math.pow(t1 / t0, it / iterations);
      final candidate = List<CellKind>.from(kinds);
      _mutate(candidate, rng);
      final candShape = GridShape(rows, cols, candidate);
      final candResult = _validator.validate(candShape, exact: false);
      final delta = candResult.energy - energy;
      if (delta <= 0 || rng.nextDouble() < math.exp(-delta / temp)) {
        kinds = candidate;
        shape = candShape;
        result = candResult;
        energy = candResult.energy;
        if (energy < bestEnergy) {
          bestEnergy = energy;
          best = kinds;
          if (bestEnergy < 8 && it > iterations ~/ 3) break;
        }
      }
    }
    final finalShape = GridShape(rows, cols, best);
    final exact = _validator.validate(finalShape, exact: true);
    if (!exact.ok) return null;
    return LayoutTemplate(id: id, level: config.level, shape: finalShape, assignments: exact.assignments, stats: exact.stats!);
  }

  void _mutate(List<CellKind> kinds, SeededRandom rng) {
    final rows = config.rows, cols = config.cols;
    final move = rng.nextInt(10);
    int interior() {
      final r = 1 + rng.nextInt(rows - 1);
      final c = 1 + rng.nextInt(cols - 1);
      return r * cols + c;
    }
    if (move < 5) {
      // toggle an interior cell
      final i = interior();
      kinds[i] = kinds[i] == CellKind.clue ? CellKind.letter : CellKind.clue;
    } else if (move < 8) {
      // shift a clue cell by one along its row or column
      for (var tries = 0; tries < 20; tries++) {
        final i = interior();
        if (kinds[i] != CellKind.clue) continue;
        final r = i ~/ cols, c = i % cols;
        final horizontal = rng.nextBool();
        final nr = horizontal ? r : r + (rng.nextBool() ? 1 : -1);
        final nc = horizontal ? c + (rng.nextBool() ? 1 : -1) : c;
        if (nr < 1 || nc < 1 || nr >= rows || nc >= cols) continue;
        final j = nr * cols + nc;
        if (kinds[j] == CellKind.letter) {
          kinds[j] = CellKind.clue;
          kinds[i] = CellKind.letter;
          break;
        }
      }
    } else if (move < 9) {
      // swap two interior cells of different kinds
      for (var tries = 0; tries < 20; tries++) {
        final i = interior(), j = interior();
        if (kinds[i] != kinds[j]) {
          final t = kinds[i];
          kinds[i] = kinds[j];
          kinds[j] = t;
          break;
        }
      }
    } else {
      // toggle a border cell (bent arrows) only when the level allows them
      if (config.allowedArrows.any((a) => a.isBent)) {
        final onTop = rng.nextBool();
        final i = onTop ? 2 + rng.nextInt(math.max(1, cols - 2)) : (2 + rng.nextInt(math.max(1, rows - 2))) * cols;
        kinds[i] = kinds[i] == CellKind.clue ? CellKind.letter : CellKind.clue;
      } else {
        final i = interior();
        kinds[i] = kinds[i] == CellKind.clue ? CellKind.letter : CellKind.clue;
      }
    }
  }
}
