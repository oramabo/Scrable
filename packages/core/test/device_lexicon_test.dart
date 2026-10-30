@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:chetz_core/chetz_core.dart';
import 'package:chetz_core/generator.dart';
import 'package:test/test.dart';

void main() {
  final root = Directory.current.path.endsWith('core') ? '../..' : '.';
  for (final lang in ['he', 'en']) {
    final lexPath = '$root/content/$lang/device/lexicon.json.gz';
    if (!File(lexPath).existsSync()) continue;
    test('on-device generation from the compact $lang lexicon (random-puzzle mode)', () {
      final profile = Languages.byCode(lang);
      final sw = Stopwatch()..start();
      final lexicon = Lexicon.fromDevice(profile, jsonDecode(utf8.decode(gzip.decode(File(lexPath).readAsBytesSync()))) as Map<String, dynamic>);
      final templates = (jsonDecode(utf8.decode(gzip.decode(File('$root/content/$lang/device/templates.json.gz').readAsBytesSync()))) as List)
          .map((t) => LayoutTemplate.fromJson(t as Map<String, dynamic>))
          .toList();
      final builder = PuzzleBuilder(lexicon);
      final loadMs = sw.elapsedMilliseconds;
      for (final level in {1, 3, LevelConfig.maxDeviceLevel(lang)}) {
        sw.reset();
        // Same request as the app's random mode, tolerance included.
        final out = builder.build(BuildRequest(id: '$lang-practice-$level', kind: PuzzleKind.practice, level: level, seed: 'device-$lang-$level', templates: templates, bandTolerance: 2.5));
        // ignore: avoid_print
        print('$lang device L$level: ${out.puzzle.words.length} words, score ${out.puzzle.difficulty.score}, ${sw.elapsedMilliseconds}ms (load ${loadMs}ms)');
        expect(out.puzzle.words.length, greaterThan(10));
        expect(PuzzleValidator(lexicon, builder.fit).validate(out.puzzle, level: LevelConfig.forLanguage(lang, level)), isEmpty);
      }
    });
  }
}
