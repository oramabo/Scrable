import 'dart:math' as math;

import '../model/geometry.dart';
import '../model/puzzle.dart';
import '../model/puzzle_codec.dart';
import 'clue_assigner.dart';
import 'dictionary_index.dart';
import 'difficulty.dart';
import 'fill.dart';
import 'fit.dart';
import 'layout.dart';
import 'level_config.dart';
import 'lexicon.dart';
import 'puzzle_validator.dart';
import 'rng.dart';

const String generatorVersion = '0.2.1';

class BuildRequest {
  const BuildRequest({
    required this.id,
    required this.kind,
    required this.level,
    required this.seed,
    required this.templates,
    this.config,
    this.daily,
    this.pack,
    this.title,
    this.excludeCanonical = const {},
    this.usedClueIds = const {},
    this.maxTemplates = 12,
    this.pictureShare = 0.0,
    this.bandTolerance = 0.0,
  });

  final String id;
  final PuzzleKind kind;
  final int level;

  /// Hex/string seed; everything downstream derives from it.
  final String seed;
  final List<LayoutTemplate> templates;

  /// Overrides the level defaults (daily variants).
  final LevelConfig? config;
  final DailyInfo? daily;
  final PackRef? pack;
  final String? title;

  /// Words to keep out (recent dailies, same pack).
  final Set<String> excludeCanonical;
  final Set<String> usedClueIds;
  final int maxTemplates;

  /// Share of clues rendered as pictures (words need an attached image).
  final double pictureShare;

  /// How far outside the level's score band a puzzle may land and still be
  /// taken at once instead of trying another template (random puzzles).
  final double bandTolerance;
}

class BuildFailure implements Exception {
  BuildFailure(this.message, this.log);
  final String message;
  final List<String> log;
  @override
  String toString() => 'BuildFailure: $message\n${log.join('\n')}';
}

class BuildOutcome {
  const BuildOutcome({required this.puzzle, required this.words, required this.clues, required this.log});
  final Puzzle puzzle;
  final List<LexWord> words;
  final List<LexClue> clues;
  final List<String> log;
}

/// Template → fill → clues → validate → difficulty → Puzzle.
class PuzzleBuilder {
  PuzzleBuilder(this.lexicon, {FitModel? fit, this.codec = const PuzzleCodec(), this.difficulty = const DifficultyModel(), FillConfig? fillConfig})
      : fit = fit ?? FitModel(lexicon.lang),
        fillConfig = fillConfig ?? const FillConfig(),
        dict = DictionaryIndex(lexicon);

  final Lexicon lexicon;
  final FitModel fit;
  final PuzzleCodec codec;
  final DifficultyModel difficulty;
  final FillConfig fillConfig;
  final DictionaryIndex dict;

  final Map<String, Eligibility> _eligibility = {};

  Eligibility eligibilityFor(LevelConfig cfg, {double pictureShare = 0.0}) => _eligibility.putIfAbsent(
      '${cfg.level}|${cfg.maxWordDifficulty}|${cfg.allowMultiword}|${cfg.allowProper}|${pictureShare > 0}|${cfg.targetWords > ClueAssigner.bigGridWords}',
      () => ClueAssigner(lexicon, fit, cfg, pictureShare: pictureShare).eligibility(dict));

  BuildOutcome build(BuildRequest req) {
    final cfg = req.config ?? LevelConfig.forLanguage(lexicon.lang.code, req.level);
    final rng = SeededRandom.fromString(req.seed);
    final log = <String>[];
    // Same level rules can come in several sizes (a level's packs, the 25×25 dailies).
    final templates = req.templates.where((t) => t.level == cfg.level && t.shape.rows == cfg.rows && t.shape.cols == cfg.cols).toList();
    if (templates.isEmpty) throw BuildFailure('no ${cfg.rows}x${cfg.cols} templates for level ${cfg.level}', log);
    rng.shuffle(templates);
    final eligibility = eligibilityFor(cfg, pictureShare: req.pictureShare);
    final assigner = ClueAssigner(lexicon, fit, cfg, pictureShare: req.pictureShare);
    final validator = PuzzleValidator(lexicon, fit);

    BuildOutcome? best;
    var bestDistance = double.infinity;
    final tried = templates.take(req.maxTemplates).toList();
    // A template that fills does so within one modest budget, and the next
    // template is a better bet than restarts on one that did not: the quick
    // pass gives each a single attempt. Only when all of them fail does the
    // deep pass spend the full restart budget per template.
    for (final (phase, filler) in [
      ('quick', Filler(dict, cfg, eligibility, config: fillConfig.copyWith(maxRestarts: 1))),
      ('deep', Filler(dict, cfg, eligibility, config: fillConfig)),
    ]) {
      for (final tpl in tried) {
        final forbid = <int, Set<int>>{};
        // Big grids hit more clue dead ends; each round can rule out several.
        final rounds = math.max(6, tpl.assignments.length ~/ 20);
        for (var round = 0; round < rounds; round++) {
          final fillRng = rng.fork('tpl${tpl.id}-$phase-round$round');
          final fullSlots = tpl.assignments.where((a) => a.slot == SlotPos.full).length;
          final fill = filler.fill(tpl, fillRng,
              forbid: forbid,
              excludeCanonical: req.excludeCanonical,
              imageBonus: req.pictureShare > 0 ? 6.0 : 0.0,
              pictureTarget: req.pictureShare > 0 ? (fullSlots * req.pictureShare).round().clamp(0, 2) : 0); // ≤ 2 seeds keeps the few picture words spread across a 30-puzzle pack
          if (!fill.ok) {
            log.add('template ${tpl.id} ($phase): fill failed (${fill.failure})');
            break;
          }
          final words = fill.words.cast<LexWord>();
          final clues = assigner.assign(fill.slots, words, rng.fork('clues${tpl.id}-$phase-$round'),
              date: req.daily?.date, variant: req.daily?.variant.code, usedClueIds: req.usedClueIds);
          if (!clues.ok) {
            for (final slot in clues.failedSlots) {
              forbid.putIfAbsent(slot, () => <int>{}).add(words[slot].dictIndex);
            }
            final slot = clues.failedSlot!;
            final more = clues.failedSlots.length > 1 ? ' and ${clues.failedSlots.length - 1} more' : '';
            log.add('template ${tpl.id}: no clue for ${words[slot].display} in slot $slot (${clues.failureReason})$more; retrying');
            continue;
          }
          final outcome = _assemble(req, cfg, tpl, fill, words, clues.clues.cast<AssignedClue>(), log);
          final errors = validator.validate(outcome.puzzle, level: cfg);
          if (errors.isNotEmpty) {
            log.add('template ${tpl.id}: validation failed: ${errors.join('; ')}');
            break;
          }
          final score = outcome.puzzle.difficulty.score;
          final distance = score < cfg.scoreMin ? cfg.scoreMin - score : (score > cfg.scoreMax ? score - cfg.scoreMax : 0.0);
          log.add('template ${tpl.id}: ok, score $score (band ${cfg.scoreMin}-${cfg.scoreMax}), ${fill.nodes} nodes');
          if (distance <= req.bandTolerance) return outcome;
          if (distance < bestDistance) {
            bestDistance = distance;
            best = outcome;
          }
          break;
        }
      }
      if (best != null) {
        log.add('accepting best-effort puzzle ${bestDistance.toStringAsFixed(1)} points outside the band');
        return best;
      }
    }
    throw BuildFailure('could not build ${req.id}', log);
  }

  BuildOutcome _assemble(BuildRequest req, LevelConfig cfg, LayoutTemplate tpl, FillResult fill, List<LexWord> words, List<AssignedClue> clues, List<String> log) {
    final shape = tpl.shape;
    // Word ids in reading order: across words top-down, then down words.
    final order = List<int>.generate(fill.slots.length, (i) => i)
      ..sort((a, b) {
        final ra = fill.slots[a].assignment.run, rb = fill.slots[b].assignment.run;
        if (ra.dir != rb.dir) return ra.dir == Dir.across ? -1 : 1;
        if (ra.dir == Dir.across) {
          return ra.start.r != rb.start.r ? ra.start.r - rb.start.r : ra.start.c - rb.start.c;
        }
        return ra.start.c != rb.start.c ? ra.start.c - rb.start.c : ra.start.r - rb.start.r;
      });
    final ids = List<String>.filled(fill.slots.length, '');
    var na = 0, nd = 0;
    for (final i in order) {
      final run = fill.slots[i].assignment.run;
      ids[i] = run.dir == Dir.across ? 'a${(++na).toString().padLeft(2, '0')}' : 'd${(++nd).toString().padLeft(2, '0')}';
    }
    final puzzleWords = <PuzzleWord>[];
    final solution = List<int>.filled(shape.cellCount, -1);
    final slotsByCell = <int, List<ClueSlot>>{};
    for (final i in order) {
      final slot = fill.slots[i];
      final a = slot.assignment;
      final word = words[i];
      final clue = clues[i];
      for (var k = 0; k < slot.len; k++) {
        solution[slot.cells[k]] = word.symbols[k];
      }
      puzzleWords.add(PuzzleWord(
        id: ids[i],
        dir: a.run.dir,
        start: a.run.start,
        len: a.run.len,
        clueCell: shape.pos(a.clueCell),
        arrow: a.arrow,
        clueId: clue.clue.id,
        lemmaId: word.id,
        wordCount: word.wordCount,
        difficulty: word.difficulty,
      ));
      slotsByCell.putIfAbsent(a.clueCell, () => []).add(ClueSlot(pos: a.slot, wordId: ids[i], arrow: a.arrow, text: clue.text, lines: clue.lines, image: clue.image));
    }
    final clueCells = <ClueCell>[];
    final cellIndices = slotsByCell.keys.toList()..sort();
    for (final c in cellIndices) {
      final slots = slotsByCell[c]!..sort((x, y) => x.pos.index - y.pos.index);
      clueCells.add(ClueCell(pos: shape.pos(c), slots: slots));
    }
    final lexClues = [for (final c in clues) c.clue];
    final pictureCount = clues.where((c) => c.image != null).length;
    final diff = difficulty.score(words: words, clues: lexClues, layout: tpl.stats, pictureClues: pictureCount);
    final puzzle = Puzzle(
      id: req.id,
      lang: lexicon.lang.code,
      kind: req.kind,
      level: req.level,
      daily: req.daily,
      pack: req.pack,
      title: req.title,
      shape: shape,
      clueCells: clueCells,
      words: puzzleWords,
      solution: solution,
      difficulty: diff,
      meta: PuzzleMeta(
        generator: GeneratorInfo(version: generatorVersion, seed: req.seed, templateId: tpl.id, dictSnapshot: lexicon.snapshotId),
        author: 'generator',
        createdAt: DateTime.now().toUtc().toIso8601String(),
      ),
    );
    return BuildOutcome(puzzle: codec.withChecksum(puzzle), words: words, clues: lexClues, log: log);
  }
}
