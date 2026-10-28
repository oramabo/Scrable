import 'dart:convert';
import 'dart:io';

import 'package:chetz_core/chetz_core.dart';
import 'package:chetz_core/generator.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// File layout of `content/{lang}` and helpers to read/write it.
class ContentStore {
  ContentStore(this.root, this.lang) : langDir = p.join(root, lang);

  final String root;
  final String lang;
  final String langDir;

  String get wordsPath => p.join(langDir, 'lexicon', 'words.jsonl.gz');
  String get cluesPath => p.join(langDir, 'clues', 'clues.jsonl.gz');
  String get templatesDir => p.join(langDir, 'templates');
  String get puzzlesDir => p.join(langDir, 'puzzles');
  String get packsDir => p.join(puzzlesDir, 'packs');
  String get dailyDir => p.join(puzzlesDir, 'daily');
  String get manifestsDir => p.join(puzzlesDir, 'manifests');

  static Iterable<String> readJsonlGz(String path) {
    final bytes = File(path).readAsBytesSync();
    final text = utf8.decode(gzip.decode(bytes));
    return const LineSplitter().convert(text);
  }

  /// Snapshot id derived from the lexicon files, so puzzles record exactly
  /// which dictionary produced them.
  String snapshotId() {
    final h = sha256.convert([...File(wordsPath).readAsBytesSync(), ...File(cluesPath).readAsBytesSync()]).toString();
    return '$lang-${h.substring(0, 10)}';
  }

  Lexicon loadLexicon() {
    final profile = Languages.byCode(lang);
    return Lexicon.fromJsonl(profile, wordLines: readJsonlGz(wordsPath), clueLines: readJsonlGz(cluesPath), snapshotId: snapshotId());
  }

  File templateFile(int level) => File(p.join(templatesDir, 'L$level.json'));

  List<LayoutTemplate> loadTemplates({int? level}) {
    final out = <LayoutTemplate>[];
    final dir = Directory(templatesDir);
    if (!dir.existsSync()) return out;
    for (final f in dir.listSync().whereType<File>()) {
      if (!f.path.endsWith('.json')) continue;
      final list = jsonDecode(f.readAsStringSync()) as List;
      for (final j in list) {
        final t = LayoutTemplate.fromJson(j as Map<String, dynamic>);
        if (level == null || t.level == level) out.add(t);
      }
    }
    return out;
  }

  void saveTemplates(int level, List<LayoutTemplate> templates) {
    final f = templateFile(level);
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(templates.map((t) => t.toJson()).toList()));
  }

  String packId(int level, int pack) => '$lang-l$level-p${pack.toString().padLeft(2, '0')}';
  Directory packDir(int level, int pack) => Directory(p.join(packsDir, packId(level, pack)));
  File packPuzzleFile(int level, int pack, int index) => File(p.join(packDir(level, pack).path, '${index.toString().padLeft(2, '0')}.json'));

  String dailyId(String date, String variant) => '$lang-d-$date-$variant';
  File dailyFile(String date, String variant) => File(p.join(dailyDir, variant, '$date.json'));

  void writePuzzle(File f, Puzzle puzzle, {PuzzleCodec codec = const PuzzleCodec()}) {
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(codec.encode(puzzle));
  }

  Puzzle readPuzzle(File f, {PuzzleCodec codec = const PuzzleCodec()}) => codec.decode(f.readAsStringSync());

  /// All puzzle files under `puzzles/` (packs and dailies).
  List<File> allPuzzleFiles() {
    final dir = Directory(puzzlesDir);
    if (!dir.existsSync()) return const [];
    return dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.json') && !f.path.contains('${p.separator}manifests${p.separator}') && p.basename(f.path) != 'pack.json')
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
  }

  /// Canonical answers used by dailies of [variant] within [days] of [date].
  Set<String> recentDailyWords(String date, String variant, int days, LanguageProfile profile) {
    final out = <String>{};
    final target = DateTime.parse(date);
    for (final v in ['easy', 'hard']) {
      final dir = Directory(p.join(dailyDir, v));
      if (!dir.existsSync()) continue;
      for (final f in dir.listSync().whereType<File>()) {
        final d = DateTime.tryParse(p.basenameWithoutExtension(f.path));
        if (d == null) continue;
        final diff = target.difference(d).inDays.abs();
        if (v == variant ? diff > days : diff > 0) continue;
        final puzzle = readPuzzle(f);
        for (final w in puzzle.words) {
          out.add(profile.canonicalKey(puzzle.answerOf(w)));
        }
      }
    }
    return out;
  }
}

String isoDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
