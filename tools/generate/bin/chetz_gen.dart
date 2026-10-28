import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:chetz_core/chetz_core.dart';
import 'package:chetz_core/generator.dart';
import 'package:chetz_gen/src/content_store.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:path/path.dart' as p;

Future<void> main(List<String> args) async {
  final runner = CommandRunner<void>('chetz_gen', 'Generate and validate Chetz arrowword content.')
    ..argParser.addOption('content', defaultsTo: 'content', help: 'Content root directory')
    ..addCommand(TemplatesCommand())
    ..addCommand(PackCommand())
    ..addCommand(DailiesCommand())
    ..addCommand(ManifestCommand())
    ..addCommand(ValidateCommand())
    ..addCommand(PreviewCommand())
    ..addCommand(GalleryCommand())
    ..addCommand(StatsCommand());
  try {
    await runner.run(args);
  } on UsageException catch (e) {
    stderr.writeln(e);
    exitCode = 64;
  } on BuildFailure catch (e) {
    stderr.writeln(e);
    exitCode = 1;
  }
}

/// Builds a puzzle, retrying with salted seeds when the first seed cannot be
/// completed (rare: a template whose words have no usable clues). Returns null
/// after [retries] failures so batch commands can continue.
BuildOutcome? buildWithRetries(PuzzleBuilder builder, BuildRequest Function(String seed) request, String seed, {int retries = 3, void Function(String)? log}) {
  for (var attempt = 0; attempt <= retries; attempt++) {
    final s = attempt == 0 ? seed : '$seed|retry$attempt';
    try {
      return builder.build(request(s));
    } on BuildFailure catch (e) {
      log?.call('  attempt ${attempt + 1} failed: ${e.message}');
    }
  }
  return null;
}

abstract class _Base extends Command<void> {
  _Base() {
    argParser.addOption('lang', defaultsTo: 'he', help: 'Puzzle language code (he, en)');
  }

  String get lang => argResults!['lang'] as String;
  ContentStore get store => ContentStore(globalResults!['content'] as String, lang);

  void log(String s) => stdout.writeln(s);
}

class TemplatesCommand extends _Base {
  TemplatesCommand() {
    argParser
      ..addOption('level', help: 'Level 1-6 (default: all 1-5)')
      ..addOption('count', defaultsTo: '40')
      ..addOption('seed', defaultsTo: 'templates-v1')
      ..addOption('iterations', defaultsTo: '12000');
  }

  @override
  String get name => 'templates';
  @override
  String get description => 'Generate layout templates per level by simulated annealing.';

  @override
  void run() {
    final levels = argResults!['level'] == null ? [1, 2, 3, 4, 5] : [int.parse(argResults!['level'] as String)];
    final count = int.parse(argResults!['count'] as String);
    final seed = argResults!['seed'] as String;
    final iterations = int.parse(argResults!['iterations'] as String);
    for (final level in levels) {
      final cfg = LevelConfig.forLanguage(lang, level);
      final gen = LayoutGenerator(cfg, iterations: iterations);
      final existing = store.loadTemplates(level: level);
      final seen = {for (final t in existing) t.shape.toRows().join('|')};
      final out = [...existing];
      final sw = Stopwatch()..start();
      var attempt = 0;
      var failures = 0;
      while (out.length < count && attempt < count * 4) {
        final rng = SeededRandom.fromString('$seed|$lang|L$level|$attempt');
        attempt++;
        final tpl = gen.generate(rng, id: '$lang-t$level-${attempt.toString().padLeft(3, '0')}');
        if (tpl == null) {
          failures++;
          continue;
        }
        final key = tpl.shape.toRows().join('|');
        if (seen.add(key)) out.add(tpl);
      }
      store.saveTemplates(level, out);
      log('L$level: ${out.length} templates (${out.length - existing.length} new, $failures failed anneals) in ${sw.elapsed.inSeconds}s -> ${store.templateFile(level).path}');
    }
  }
}

class PackCommand extends _Base {
  PackCommand() {
    argParser
      ..addOption('level', mandatory: true)
      ..addOption('pack', mandatory: true, help: 'Pack number within the level (1-based)')
      ..addOption('count', defaultsTo: '30')
      ..addOption('salt', defaultsTo: '', help: 'Extra seed salt to regenerate a pack differently')
      ..addFlag('force', help: 'Regenerate puzzles that already exist');
  }

  @override
  String get name => 'pack';
  @override
  String get description => 'Generate a 30-puzzle pack for a level.';

  @override
  void run() {
    final level = int.parse(argResults!['level'] as String);
    final pack = int.parse(argResults!['pack'] as String);
    final count = int.parse(argResults!['count'] as String);
    final salt = argResults!['salt'] as String;
    final force = argResults!['force'] as bool;
    final s = store;
    final lexicon = s.loadLexicon();
    final builder = PuzzleBuilder(lexicon);
    final templates = s.loadTemplates(level: level);
    if (templates.isEmpty) throw UsageException('no templates for level $level; run `templates` first', usage);
    final cfg = LevelConfig.forLanguage(lang, level);
    final usedWords = <String>{};
    final usedClues = <String>{};
    final ids = <String>[];
    var failed = 0;
    final sw = Stopwatch()..start();
    for (var index = 1; index <= count; index++) {
      final file = s.packPuzzleFile(level, pack, index);
      final id = '${s.packId(level, pack)}-${index.toString().padLeft(2, '0')}';
      ids.add(id);
      if (file.existsSync() && !force) {
        final existing = s.readPuzzle(file);
        for (final w in existing.words) {
          usedWords.add(lexicon.lang.canonicalKey(existing.answerOf(w)));
          if (w.clueId != null) usedClues.add(w.clueId!);
        }
        continue;
      }
      // Ramp inside the pack: early puzzles lean easier, late ones harder.
      final ramp = (index - 1) / (count - 1).clamp(1, count);
      final shifted = _shiftDifficulty(cfg, ramp);
      final outcome = buildWithRetries(
        builder,
        (seed) => BuildRequest(
          id: id,
          kind: PuzzleKind.pack,
          level: level,
          seed: seed,
          templates: templates,
          config: shifted,
          pack: PackRef(id: s.packId(level, pack), index: index),
          excludeCanonical: usedWords,
          usedClueIds: usedClues,
        ),
        Seeds.pack(lang: lang, level: level, pack: pack, index: index, salt: salt),
        log: log,
      );
      if (outcome == null) {
        stderr.writeln('FAILED $id after retries');
        failed++;
        continue;
      }
      for (final w in outcome.words) {
        usedWords.add(w.canonical);
      }
      for (final c in outcome.clues) {
        usedClues.add(c.id);
      }
      s.writePuzzle(file, outcome.puzzle);
      log('${outcome.puzzle.id}: ${outcome.puzzle.words.length} words, score ${outcome.puzzle.difficulty.score} (${sw.elapsed.inSeconds}s)');
    }
    final packJson = {
      'id': s.packId(level, pack),
      'lang': lang,
      'level': level,
      'index': pack,
      'title': {'he': 'רמה $level · חבילה $pack', 'en': 'Level $level · Pack $pack'},
      'puzzleCount': count,
      'puzzles': ids,
      'free': pack == 1,
    };
    File(p.join(s.packDir(level, pack).path, 'pack.json')).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(packJson));
    log('pack ${s.packId(level, pack)} done in ${sw.elapsed.inSeconds}s${failed > 0 ? ' with $failed FAILED puzzles' : ''}');
    if (failed > 0) exitCode = 1;
  }

  LevelConfig _shiftDifficulty(LevelConfig cfg, double ramp) {
    // ±0.05 around the level's band depending on position in the pack
    final shift = (ramp - 0.5) * 0.1;
    return LevelConfig(
      level: cfg.level,
      rows: cfg.rows,
      cols: cfg.cols,
      targetWords: cfg.targetWords,
      maxWordLen: cfg.maxWordLen,
      max2LetterShare: cfg.max2LetterShare,
      maxWordDifficulty: cfg.maxWordDifficulty,
      meanDifficultyMin: (cfg.meanDifficultyMin + shift).clamp(0.0, 1.0),
      meanDifficultyMax: (cfg.meanDifficultyMax + shift).clamp(0.0, 1.0),
      minCheckedRatio: cfg.minCheckedRatio,
      maxBentArrows: cfg.maxBentArrows,
      allowedArrows: cfg.allowedArrows,
      clueDifficultyMin: cfg.clueDifficultyMin,
      clueDifficultyMax: cfg.clueDifficultyMax,
      allowMultiword: cfg.allowMultiword,
      allowProper: cfg.allowProper,
      parSeconds: cfg.parSeconds,
      letterDensityTarget: cfg.letterDensityTarget,
      scoreMin: cfg.scoreMin,
      scoreMax: cfg.scoreMax,
      borderLetters: cfg.borderLetters,
      lengthMid: cfg.lengthMid,
    );
  }
}

class DailiesCommand extends _Base {
  DailiesCommand() {
    argParser
      ..addOption('from', mandatory: true, help: 'First date YYYY-MM-DD')
      ..addOption('days', defaultsTo: '90')
      ..addOption('secret', help: 'Daily seed secret (default: env DAILY_SEED_SECRET or a dev value)')
      ..addMultiOption('variant', defaultsTo: ['easy', 'hard'])
      ..addFlag('force');
  }

  @override
  String get name => 'dailies';
  @override
  String get description => 'Generate daily puzzles (easy + hard) for a date range.';

  @override
  void run() {
    final from = DateTime.parse(argResults!['from'] as String);
    final days = int.parse(argResults!['days'] as String);
    final secret = (argResults!['secret'] as String?) ?? Platform.environment['DAILY_SEED_SECRET'] ?? 'dev-daily-secret-change-me';
    final variants = argResults!['variant'] as List<String>;
    final force = argResults!['force'] as bool;
    final s = store;
    final lexicon = s.loadLexicon();
    final builder = PuzzleBuilder(lexicon);
    final templates = s.loadTemplates();
    final sw = Stopwatch()..start();
    var made = 0;
    var failed = 0;
    for (var d = 0; d < days; d++) {
      final date = isoDate(from.add(Duration(days: d)));
      for (final variant in variants) {
        final file = s.dailyFile(date, variant);
        if (file.existsSync() && !force) continue;
        final cfg = variant == 'easy' ? LevelConfig.dailyEasy(lang) : LevelConfig.dailyHard(lang);
        final recent = s.recentDailyWords(date, variant, 30, lexicon.lang);
        final outcome = buildWithRetries(
          builder,
          (seed) => BuildRequest(
            id: s.dailyId(date, variant),
            kind: PuzzleKind.daily,
            level: cfg.level,
            seed: seed,
            templates: templates,
            config: cfg,
            daily: DailyInfo(date: date, variant: DailyVariant.fromCode(variant)),
            title: lang == 'he' ? (variant == 'easy' ? 'התשחץ היומי' : 'האתגר היומי') : (variant == 'easy' ? 'Daily Arrowword' : 'Daily Challenge'),
            excludeCanonical: recent,
          ),
          Seeds.daily(secret: secret, lang: lang, date: date, variant: variant),
          log: log,
        );
        if (outcome == null) {
          stderr.writeln('FAILED ${s.dailyId(date, variant)} after retries');
          failed++;
          continue;
        }
        s.writePuzzle(file, outcome.puzzle);
        made++;
        log('${outcome.puzzle.id}: ${outcome.puzzle.words.length} words, score ${outcome.puzzle.difficulty.score} (${sw.elapsed.inSeconds}s)');
      }
    }
    log('$made dailies generated in ${sw.elapsed.inSeconds}s${failed > 0 ? ', $failed FAILED' : ''}');
    if (failed > 0) exitCode = 1;
  }
}

class ManifestCommand extends _Base {
  ManifestCommand() {
    argParser.addOption('cdn-prefix', defaultsTo: 'puzzles', help: 'URL prefix of puzzle files on the CDN');
  }

  @override
  String get name => 'manifest';
  @override
  String get description => 'Build daily.json, packs.json and publish-index.json manifests from the generated puzzles.';

  @override
  void run() {
    final s = store;
    final prefix = argResults!['cdn-prefix'] as String;
    const codec = PuzzleCodec();
    final now = DateTime.now().toUtc().toIso8601String();
    final dailyEntries = <Map<String, dynamic>>[];
    final publishIndex = <Map<String, dynamic>>[];
    final dailyRoot = Directory(s.dailyDir);
    if (dailyRoot.existsSync()) {
      for (final variantDir in dailyRoot.listSync().whereType<Directory>()) {
        final variant = p.basename(variantDir.path);
        for (final f in variantDir.listSync().whereType<File>()) {
          if (!f.path.endsWith('.json')) continue;
          final puzzle = s.readPuzzle(f);
          final date = p.basenameWithoutExtension(f.path);
          dailyEntries.add({
            'date': date,
            'variant': variant,
            'id': puzzle.id,
            'url': '$prefix/$lang/daily/$variant/$date.v${puzzle.meta.version}.json',
            'checksum': puzzle.meta.checksum,
            'version': puzzle.meta.version,
          });
          publishIndex.add({
            'id': puzzle.id,
            'kind': 'daily',
            'lang': lang,
            'date': date,
            'variant': variant,
            'file': p.relative(f.path, from: s.root),
            'letterCells': puzzle.shape.letterCount,
            'solutionHash': PuzzleCodec.solutionHash(puzzle),
            'checksum': puzzle.meta.checksum,
            'version': puzzle.meta.version,
          });
        }
      }
    }
    dailyEntries.sort((a, b) => '${a['date']}${a['variant']}'.compareTo('${b['date']}${b['variant']}'));
    final packs = <Map<String, dynamic>>[];
    final packsRoot = Directory(s.packsDir);
    if (packsRoot.existsSync()) {
      final dirs = packsRoot.listSync().whereType<Directory>().toList()..sort((a, b) => a.path.compareTo(b.path));
      for (final dir in dirs) {
        final packFile = File(p.join(dir.path, 'pack.json'));
        if (!packFile.existsSync()) continue;
        final pj = jsonDecode(packFile.readAsStringSync()) as Map<String, dynamic>;
        final puzzleFiles = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.json') && p.basename(f.path) != 'pack.json').toList()
          ..sort((a, b) => a.path.compareTo(b.path));
        final puzzles = <Map<String, dynamic>>[];
        for (final f in puzzleFiles) {
          final puzzle = s.readPuzzle(f);
          puzzles.add({
            'id': puzzle.id,
            'index': puzzle.pack?.index,
            'url': '$prefix/$lang/packs/${pj['id']}/${p.basenameWithoutExtension(f.path)}.v${puzzle.meta.version}.json',
            'checksum': puzzle.meta.checksum,
            'difficulty': puzzle.difficulty.score,
            'words': puzzle.words.length,
          });
          publishIndex.add({
            'id': puzzle.id,
            'kind': 'pack',
            'lang': lang,
            'packId': pj['id'],
            'index': puzzle.pack?.index,
            'file': p.relative(f.path, from: s.root),
            'letterCells': puzzle.shape.letterCount,
            'solutionHash': PuzzleCodec.solutionHash(puzzle),
            'checksum': puzzle.meta.checksum,
            'version': puzzle.meta.version,
          });
        }
        packs.add({
          'id': pj['id'],
          'lang': lang,
          'level': pj['level'],
          'index': pj['index'],
          'title': pj['title'],
          'puzzleCount': puzzles.length,
          'url': '$prefix/$lang/packs/${pj['id']}/pack.v1.json',
          'checksum': 'sha256:${_sha(jsonEncode(puzzles))}',
          'free': pj['free'] ?? false,
          'puzzles': puzzles,
        });
      }
    }
    Directory(s.manifestsDir).createSync(recursive: true);
    const enc = JsonEncoder.withIndent(' ');
    File(p.join(s.manifestsDir, 'daily.json')).writeAsStringSync(enc.convert({'version': 1, 'generatedAt': now, 'lang': lang, 'entries': dailyEntries}));
    File(p.join(s.manifestsDir, 'packs.json')).writeAsStringSync(enc.convert({'version': 1, 'generatedAt': now, 'lang': lang, 'packs': packs}));
    File(p.join(s.manifestsDir, 'publish-index.json')).writeAsStringSync(enc.convert({'generatedAt': now, 'lang': lang, 'puzzles': publishIndex}));
    log('manifests: ${dailyEntries.length} dailies, ${packs.length} packs -> ${s.manifestsDir}');
    // keep the codec referenced for clarity of what the manifest describes
    assert(codec.salt.isNotEmpty);
  }

  String _sha(String s) => sha256Hex(s);
}

class ValidateCommand extends _Base {
  @override
  String get name => 'validate';
  @override
  String get description => 'Validate every generated puzzle against the lexicon, layout rules and checksums.';

  @override
  void run() {
    final s = store;
    final lexicon = s.loadLexicon();
    final fit = FitModel(lexicon.lang);
    final validator = PuzzleValidator(lexicon, fit);
    const codec = PuzzleCodec();
    var bad = 0;
    final files = s.allPuzzleFiles();
    for (final f in files) {
      final puzzle = s.readPuzzle(f);
      final errors = validator.validate(puzzle);
      if (!codec.verifyChecksum(puzzle)) errors.add('checksum mismatch');
      if (errors.isNotEmpty) {
        bad++;
        stderr.writeln('${p.relative(f.path, from: s.root)}: ${errors.join('; ')}');
      }
    }
    log('${files.length} puzzles checked, $bad invalid');
    if (bad > 0) exitCode = 1;
  }
}

class PreviewCommand extends _Base {
  PreviewCommand() {
    argParser
      ..addOption('in', mandatory: true)
      ..addOption('out', mandatory: true)
      ..addFlag('solution', defaultsTo: true);
  }

  @override
  String get name => 'preview';
  @override
  String get description => 'Render a puzzle JSON file as SVG.';

  @override
  void run() {
    final puzzle = const PuzzleCodec().decode(File(argResults!['in'] as String).readAsStringSync());
    final svg = SvgPreview(showSolution: argResults!['solution'] as bool).render(puzzle);
    File(argResults!['out'] as String)
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(svg);
    log('wrote ${argResults!['out']}');
  }
}

class GalleryCommand extends _Base {
  GalleryCommand() {
    argParser
      ..addOption('out', defaultsTo: 'build/gallery')
      ..addOption('filter', help: 'Only puzzles whose id contains this text (e.g. he-l1-p01 or he-d-2026-11)')
      ..addOption('limit', defaultsTo: '400');
  }

  @override
  String get name => 'gallery';
  @override
  String get description => 'Write an HTML gallery with SVG previews, words and clues for editorial review.';

  @override
  void run() {
    final s = store;
    final out = Directory(argResults!['out'] as String)..createSync(recursive: true);
    final filter = argResults!['filter'] as String?;
    final limit = int.parse(argResults!['limit'] as String);
    final lexicon = s.loadLexicon();
    const preview = SvgPreview(cell: 54);
    final files = s.allPuzzleFiles().where((f) => filter == null || f.path.contains(filter)).take(limit).toList();
    final index = StringBuffer()
      ..writeln('<!doctype html><html lang="$lang" dir="${lang == 'he' ? 'rtl' : 'ltr'}"><head><meta charset="utf-8"><title>Chetz gallery ($lang)</title>'
          '<style>body{font-family:Arial,sans-serif;margin:24px;background:#faf8f3}article{background:#fff;border:1px solid #ddd;border-radius:12px;padding:16px;margin:16px 0;display:flex;gap:24px;flex-wrap:wrap}'
          'h2{margin:0 0 8px;font-size:18px}table{border-collapse:collapse;font-size:14px}td{padding:2px 8px;border-bottom:1px solid #eee}.meta{color:#666;font-size:13px}</style></head><body>')
      ..writeln('<h1>Chetz puzzle gallery · $lang · ${files.length} puzzles</h1>');
    for (final f in files) {
      final puzzle = s.readPuzzle(f);
      final rows = StringBuffer();
      for (final w in puzzle.words) {
        final lex = w.lemmaId == null ? null : lexicon.wordById[w.lemmaId!];
        rows.writeln('<tr><td>${w.id}</td><td>${w.arrow.code}</td><td><b>${_esc(lex?.display ?? '')}</b></td><td>${_esc(puzzle.clueTextOf(w.id))}</td><td class="meta">${w.difficulty.toStringAsFixed(2)}</td></tr>');
      }
      index
        ..writeln('<article><div>${preview.render(puzzle)}</div><div><h2>${puzzle.id}</h2>')
        ..writeln('<div class="meta">level ${puzzle.level} · ${puzzle.cols}×${puzzle.rows} · ${puzzle.words.length} words · score ${puzzle.difficulty.score} (${puzzle.difficulty.band}) · template ${puzzle.meta.generator?.templateId}</div>')
        ..writeln('<table>$rows</table></div></article>');
    }
    index.writeln('</body></html>');
    final target = File(p.join(out.path, 'index-$lang${filter == null ? '' : '-${filter.replaceAll(RegExp(r'[^a-zA-Z0-9-]'), '_')}'}.html'));
    target.writeAsStringSync(index.toString());
    log('wrote ${target.path} (${files.length} puzzles)');
  }

  static String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}

class StatsCommand extends _Base {
  @override
  String get name => 'stats';
  @override
  String get description => 'Print lexicon statistics and eligibility per level.';

  @override
  void run() {
    final s = store;
    final lexicon = s.loadLexicon();
    final builder = PuzzleBuilder(lexicon);
    log('lexicon ${lexicon.snapshotId}: ${lexicon.words.length} words, ${lexicon.clues.length} clues');
    for (final level in [1, 2, 3, 4, 5]) {
      final cfg = LevelConfig.forLanguage(lang, level);
      final e = builder.eligibilityFor(cfg);
      final perLen = [for (var len = 2; len <= cfg.maxWordLen; len++) '$len:${e.full[len]?.cardinality ?? 0}'];
      log('L$level eligible words by length: ${perLen.join(' ')}');
    }
  }
}

String sha256Hex(String s) => crypto.sha256.convert(utf8.encode(s)).toString();
