import 'dart:io';

import 'package:chetz_core/chetz_core.dart';
import 'package:chetz_core/generator.dart';
import 'package:chetz_gen/src/content_store.dart';

void main(List<String> args) {
  final store = ContentStore('content', 'he');
  final lexicon = store.loadLexicon();
  final fit = FitModel(lexicon.lang);
  for (final canonical in args) {
    final matches = lexicon.words.where((w) => w.canonical == canonical);
    for (final w in matches) {
      stdout.writeln('${w.id} ${w.display} len=${w.length} diff=${w.difficulty} clues=${w.clues.length} proper=${w.isProper} multi=${w.isMultiword}');
      for (final c in w.clues) {
        final full = fit.breakLines(c.text, SlotPos.full);
        final half = fit.breakLines(c.text, SlotPos.top);
        stdout.writeln('  [${c.difficulty}] "${c.text}" full=$full half=$half');
      }
    }
  }
}
