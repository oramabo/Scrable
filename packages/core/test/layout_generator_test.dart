import 'package:chetz_core/chetz_core.dart';
import 'package:chetz_core/src/generator/layout.dart';
import 'package:chetz_core/src/generator/layout_generator.dart';
import 'package:chetz_core/src/generator/level_config.dart';
import 'package:chetz_core/src/generator/rng.dart';
import 'package:test/test.dart';

void main() {
  for (final level in [1, 2, 3, 5]) {
    test('annealing produces a valid level $level layout', () {
      final config = LevelConfig.forLanguage('he', level);
      final gen = LayoutGenerator(config);
      final sw = Stopwatch()..start();
      LayoutTemplate? tpl;
      for (var attempt = 0; attempt < 4 && tpl == null; attempt++) {
        tpl = gen.generate(SeededRandom.fromString('test-L$level-$attempt'), id: 't$level');
      }
      sw.stop();
      expect(tpl, isNotNull, reason: 'no valid layout for level $level');
      final check = LayoutValidator(config).validate(tpl!.shape);
      expect(check.ok, isTrue, reason: check.errors.join(', '));
      // ignore: avoid_print
      print('L$level ${tpl.shape.cols}x${tpl.shape.rows} words=${tpl.stats.wordCount} checked=${tpl.stats.checkedRatio.toStringAsFixed(2)} '
          'density=${tpl.stats.density.toStringAsFixed(2)} bent=${tpl.stats.bentArrows} split=${tpl.stats.splitCells} in ${sw.elapsedMilliseconds}ms');
      // ignore: avoid_print
      print(tpl.shape.toRows().join('\n'));
      expect(tpl.stats.wordCount, greaterThan(config.targetWords ~/ 2));
    });
  }

  test('validator rejects an isolated letter and a run without a clue', () {
    final config = LevelConfig.forLanguage('he', 1);
    final shape = GridShape.fromRows(['CCCC', 'CLLL', 'CLCL', 'LLLL']);
    final res = LayoutValidator(config).validate(shape);
    expect(res.ok, isFalse);
    expect(res.errors.any((e) => e.startsWith('no_clue_position')), isTrue);
  });

  test('validator accepts a classic small grid and assigns clues', () {
    final config = LevelConfig.forLanguage('he', 1);
    final shape = GridShape.fromRows(['CCCC', 'CLLL', 'CLLL', 'CLLL']);
    final res = LayoutValidator(config).validate(shape);
    expect(res.ok, isTrue, reason: res.errors.join(', '));
    expect(res.assignments.length, 6);
    // Every clue cell except the corner hosts exactly one word.
    final perCell = <int, int>{};
    for (final a in res.assignments) {
      perCell[a.clueCell] = (perCell[a.clueCell] ?? 0) + 1;
    }
    expect(perCell.values.every((n) => n == 1), isTrue);
  });
}
