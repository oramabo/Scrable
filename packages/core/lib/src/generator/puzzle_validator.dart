import '../model/geometry.dart';
import '../model/puzzle.dart';
import 'fit.dart';
import 'layout.dart';
import 'level_config.dart';
import 'lexicon.dart';

/// Final gate before a puzzle is written: structural rules, dictionary
/// membership, uniqueness, clue fit and solution consistency.
class PuzzleValidator {
  PuzzleValidator(this.lexicon, this.fit);

  final Lexicon lexicon;
  final FitModel fit;

  List<String> validate(Puzzle p, {LevelConfig? level, Set<String> blockedCanonical = const {}}) {
    final errors = <String>[];
    final cfg = level ?? LevelConfig.forLanguage(p.lang, p.level);
    final layout = LayoutValidator(cfg).validate(p.shape);
    if (!layout.ok) errors.addAll(layout.errors.map((e) => 'layout: $e'));

    // Every run is a word and every word is a run.
    final runKeys = {for (final r in layout.runs) '${r.dir.name}:${r.start.r},${r.start.c},${r.len}'};
    final wordKeys = {for (final w in p.words) '${w.dir.name}:${w.start.r},${w.start.c},${w.len}'};
    if (runKeys.length != wordKeys.length || !runKeys.containsAll(wordKeys)) {
      errors.add('words do not match runs (${runKeys.difference(wordKeys)} / ${wordKeys.difference(runKeys)})');
    }

    final seen = <String>{};
    for (final w in p.words) {
      // clue cell geometry
      final expectedStart = w.clueCell + Pos(w.arrow.startDr, w.arrow.startDc);
      if (expectedStart != w.start || w.arrow.dir != w.dir) errors.add('word ${w.id}: arrow/clue cell inconsistent');
      if (!p.shape.isClue(w.clueCell.r, w.clueCell.c)) errors.add('word ${w.id}: clue cell is not a clue cell');
      for (final cell in w.cells) {
        if (!p.shape.isLetter(cell.r, cell.c)) errors.add('word ${w.id}: covers a non-letter cell $cell');
      }
      final answer = p.answerOf(w);
      if (answer.any((s) => s < 0)) {
        errors.add('word ${w.id}: missing solution letters');
        continue;
      }
      final canonical = lexicon.lang.canonicalKey(answer);
      if (!seen.add(canonical)) errors.add('word ${w.id}: duplicate answer $canonical');
      if (blockedCanonical.contains(canonical)) errors.add('word ${w.id}: blocked word');
      final lex = w.lemmaId == null ? null : lexicon.wordById[w.lemmaId!];
      if (lex == null) {
        errors.add('word ${w.id}: not in lexicon');
      } else if (lex.canonical != canonical) {
        errors.add('word ${w.id}: solution differs from lexicon entry ${lex.canonical}');
      }
      final slot = p.slotForWord(w.id);
      if (slot == null) {
        errors.add('word ${w.id}: no clue slot');
      } else {
        if (slot.arrow != w.arrow) errors.add('word ${w.id}: slot arrow differs');
        if (w.clueId != null && !lexicon.clueById.containsKey(w.clueId)) errors.add('word ${w.id}: unknown clue ${w.clueId}');
        if (w.clueId != null && lexicon.clueById[w.clueId]?.wordId != w.lemmaId) errors.add('word ${w.id}: clue belongs to another word');
        if (slot.image != null) {
          if (slot.pos != SlotPos.full) errors.add('word ${w.id}: picture clues need a full cell');
          if (slot.lines.isNotEmpty) errors.add('word ${w.id}: picture clue must not carry text lines');
        } else if (slot.lines.isEmpty || fit.breakLines(slot.text, slot.pos) == null) {
          errors.add('word ${w.id}: clue does not fit the cell');
        }
      }
    }
    // Clue cells: 1–2 slots with the exit rule.
    for (final cell in p.clueCells) {
      if (cell.slots.isEmpty || cell.slots.length > 2) errors.add('clue cell ${cell.pos}: ${cell.slots.length} slots');
      if (cell.slots.length == 2) {
        final positions = cell.slots.map((s) => s.pos).toSet();
        if (!positions.containsAll({SlotPos.top, SlotPos.bottom})) errors.add('clue cell ${cell.pos}: split cell needs top+bottom');
        for (final s in cell.slots) {
          if (!s.pos.allows(s.arrow.exit)) errors.add('clue cell ${cell.pos}: ${s.pos.code} slot cannot exit ${s.arrow.exit.name}');
        }
      } else if (cell.slots.single.pos != SlotPos.full) {
        errors.add('clue cell ${cell.pos}: single slot must be full');
      }
      for (final s in cell.slots) {
        if (!p.wordById.containsKey(s.wordId)) errors.add('clue cell ${cell.pos}: unknown word ${s.wordId}');
      }
    }
    // Solution covers exactly the letter cells.
    for (var i = 0; i < p.shape.cellCount; i++) {
      final isLetter = p.shape.kinds[i] == CellKind.letter;
      if (isLetter && (p.solution[i] < 0 || p.solution[i] >= lexicon.lang.alphabetSize)) errors.add('cell $i: invalid solution symbol');
      if (!isLetter && p.solution[i] != -1) errors.add('cell $i: clue cell carries a symbol');
    }
    if (p.difficulty.score < cfg.scoreMin - 10 || p.difficulty.score > cfg.scoreMax + 10) {
      errors.add('difficulty ${p.difficulty.score} far outside level band ${cfg.scoreMin}-${cfg.scoreMax}');
    }
    return errors;
  }
}
