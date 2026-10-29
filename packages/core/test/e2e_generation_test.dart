@Timeout(Duration(minutes: 10))
library;

import 'dart:convert';
import 'dart:io';

import 'package:chetz_core/chetz_core.dart';
import 'package:chetz_core/generator.dart';
import 'package:test/test.dart';

Iterable<String> readJsonlGz(String path) {
  final bytes = File(path).readAsBytesSync();
  return const LineSplitter().convert(utf8.decode(gzip.decode(bytes)));
}

void main() {
  final root = Directory.current.path.endsWith('core') ? '../..' : '.';
  for (final langCode in ['he', 'en']) {
    final wordsPath = '$root/content/$langCode/lexicon/words.jsonl.gz';
    if (!File(wordsPath).existsSync()) {
      // ignore: avoid_print
      print('$langCode content not present; skipping');
      continue;
    }
    group(langCode, () => languageTests(root, langCode));
  }
}

void languageTests(String root, String langCode) {
  final profile = Languages.byCode(langCode);
  final wordsPath = '$root/content/$langCode/lexicon/words.jsonl.gz';
  late Lexicon lexicon;
  late PuzzleBuilder builder;

  setUpAll(() {
    final sw = Stopwatch()..start();
    lexicon = Lexicon.fromJsonl(profile, wordLines: readJsonlGz(wordsPath), clueLines: readJsonlGz('$root/content/$langCode/clues/clues.jsonl.gz'), snapshotId: '$langCode-test');
    builder = PuzzleBuilder(lexicon);
    // ignore: avoid_print
    print('$langCode lexicon: ${lexicon.words.length} words, ${lexicon.clues.length} clues, index built in ${sw.elapsedMilliseconds}ms');
  });

  for (final level in [1, 2, 3, 4, 5]) {
    test('generates a level $level $langCode puzzle from the real lexicon', () {
      final cfg = LevelConfig.forLanguage(langCode, level);
      final gen = LayoutGenerator(cfg);
      final templates = <LayoutTemplate>[];
      for (var i = 0; i < 6 && templates.length < 3; i++) {
        final t = gen.generate(SeededRandom.fromString('e2e-$langCode-L$level-$i'), id: '$langCode-t$level-$i');
        if (t != null) templates.add(t);
      }
      expect(templates, isNotEmpty);
      final sw = Stopwatch()..start();
      final outcome = builder.build(BuildRequest(
        id: '$langCode-test-l$level',
        kind: PuzzleKind.pack,
        level: level,
        seed: Seeds.pack(lang: langCode, level: level, pack: 1, index: 1),
        templates: templates,
      ));
      sw.stop();
      final p = outcome.puzzle;
      // ignore: avoid_print
      print('L$level: ${p.cols}x${p.rows}, ${p.words.length} words, score ${p.difficulty.score} (${p.difficulty.band}) in ${sw.elapsedMilliseconds}ms');
      // ignore: avoid_print
      print(outcome.log.join('\n'));
      final lang = profile;
      final mask = FinalLetterPolicy.mask(p);
      for (var r = 0; r < p.rows; r++) {
        final row = StringBuffer();
        for (var c = 0; c < p.cols; c++) {
          final i = p.shape.index(r, c);
          row.write(p.shape.kinds[i] == CellKind.clue ? '■' : FinalLetterPolicy.display(lang, p.solution[i], mask[i]));
        }
        // ignore: avoid_print
        print(row);
      }
      for (final w in p.words.take(8)) {
        // ignore: avoid_print
        print('  ${w.id} ${w.arrow.code} ${lexicon.wordById[w.lemmaId]!.display}: ${p.clueTextOf(w.id)}');
      }
      final errors = PuzzleValidator(lexicon, builder.fit).validate(p, level: cfg);
      expect(errors, isEmpty, reason: errors.join('; '));
      // codec round trip
      final codec = const PuzzleCodec();
      final again = codec.decode(codec.encode(p));
      expect(again.solution, p.solution);
      expect(codec.verifyChecksum(again), isTrue);
      // determinism
      final second = builder.build(BuildRequest(id: '$langCode-test-l$level', kind: PuzzleKind.pack, level: level, seed: Seeds.pack(lang: langCode, level: level, pack: 1, index: 1), templates: templates));
      expect(second.puzzle.solution, p.solution);
    });
  }
}
