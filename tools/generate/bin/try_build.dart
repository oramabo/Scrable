import 'dart:io';

import 'package:chetz_core/chetz_core.dart';
import 'package:chetz_core/generator.dart';
import 'package:chetz_gen/src/content_store.dart';

/// Builds one puzzle and prints the builder log: `dart run bin/try_build.dart <lang> <level> [seed]`.
void main(List<String> args) {
  final lang = args.isNotEmpty ? args[0] : 'he';
  final level = args.length > 1 ? int.parse(args[1]) : 1;
  final seed = args.length > 2 ? args[2] : 'try-$lang-$level';
  final store = ContentStore('content', lang);
  final lexicon = store.loadLexicon();
  final builder = PuzzleBuilder(lexicon);
  final cfg = LevelConfig.forLanguage(lang, level);
  final e = builder.eligibilityFor(cfg);
  stdout.writeln('eligible (full/half) per length: ${[for (var len = 2; len <= cfg.maxWordLen; len++) '$len:${e.full[len]?.cardinality}/${e.half[len]?.cardinality}'].join(' ')}');
  try {
    final out = builder.build(BuildRequest(id: '$lang-try-$level', kind: PuzzleKind.pack, level: level, seed: seed, templates: store.loadTemplates(level: level)));
    stdout.writeln(out.log.join('\n'));
    stdout.writeln('OK score ${out.puzzle.difficulty.score}');
    for (final w in out.puzzle.words.take(12)) {
      stdout.writeln('  ${w.id} ${lexicon.wordById[w.lemmaId]!.display}: ${out.puzzle.clueTextOf(w.id)}');
    }
  } on BuildFailure catch (f) {
    stdout.writeln(f.log.join('\n'));
    stdout.writeln('FAILED');
  }
}
