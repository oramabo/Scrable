@Timeout(Duration(minutes: 5))
library;

import 'dart:convert';
import 'dart:io';

import 'package:chetz_core/chetz_core.dart';
import 'package:chetz_core/generator.dart';
import 'package:test/test.dart';

Iterable<String> readJsonlGz(String path) => const LineSplitter().convert(utf8.decode(gzip.decode(File(path).readAsBytesSync())));

void main() {
  final root = Directory.current.path.endsWith('core') ? '../..' : '.';
  final words = '$root/content/he/lexicon/words.jsonl.gz';
  if (!File(words).existsSync()) return;

  test('picture clues: image attached to words appears in full-cell slots and validates', () {
    final lexicon = Lexicon.fromJsonl(Languages.he, wordLines: readJsonlGz(words), clueLines: readJsonlGz('$root/content/he/clues/clues.jsonl.gz'));
    // Give every eligible short common word a fake picture so the share is reachable.
    var attached = 0;
    for (final w in lexicon.words) {
      if (w.length >= 3 && w.length <= 5 && w.difficulty < 0.4 && w.clues.isNotEmpty) {
        w.image = ClueImage(id: 'img_${w.id}', src: 'images/${w.id}.jpg', license: 'CC0', credit: 'test');
        if (++attached > 3000) break;
      }
    }
    final builder = PuzzleBuilder(lexicon);
    final cfg = LevelConfig.forLanguage('he', 1);
    final tpl = LayoutGenerator(cfg).generate(SeededRandom.fromString('pic-tpl'), id: 'pic-t1')!;
    final out = builder.build(BuildRequest(id: 'he-pic-test', kind: PuzzleKind.pack, level: 1, seed: 'pic-seed', templates: [tpl], pictureShare: 0.4));
    final pictures = out.puzzle.clueCells.expand((c) => c.slots).where((s) => s.isPicture).toList();
    expect(pictures, isNotEmpty);
    expect(pictures.every((s) => s.pos == SlotPos.full && s.lines.isEmpty && s.text.isNotEmpty), isTrue);
    expect(PuzzleValidator(lexicon, builder.fit).validate(out.puzzle, level: cfg), isEmpty);
    const codec = PuzzleCodec();
    final back = codec.decode(codec.encode(out.puzzle));
    expect(back.clueCells.expand((c) => c.slots).where((s) => s.isPicture).length, pictures.length);
    expect(back.slotForWord(pictures.first.wordId)!.image!.license, 'CC0');
  });
}
