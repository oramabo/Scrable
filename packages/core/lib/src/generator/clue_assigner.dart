import '../model/geometry.dart';
import '../model/puzzle.dart';
import 'bitset.dart';
import 'dictionary_index.dart';
import 'fill.dart';
import 'fit.dart';
import 'level_config.dart';
import 'lexicon.dart';
import 'rng.dart';

/// A clue chosen for a slot, with its cell line breaks.
class AssignedClue {
  const AssignedClue({required this.clue, required this.text, required this.lines, this.image});
  final LexClue clue;

  /// Text as shown (includes the multi-word suffix); for picture clues a short hint.
  final String text;
  final List<String> lines;

  /// Picture clue (cell shows the image; [lines] is empty).
  final ClueImage? image;
}

class ClueAssignment {
  const ClueAssignment({required this.ok, required this.clues, this.failedSlot, this.failedSlots = const [], this.failureReason});
  final bool ok;
  final List<AssignedClue?> clues;

  /// First slot index whose word has no usable clue (fed back to the filler).
  final int? failedSlot;

  /// Every slot without a usable clue, so one refill can avoid them all.
  final List<int> failedSlots;

  /// Why every clue of that word was rejected (for logs and the admin tool).
  final String? failureReason;
}

/// Chooses clues for filled words and computes which words are eligible for
/// which slot geometry.
class ClueAssigner {
  ClueAssigner(this.lexicon, this.fit, this.level, {this.recentDays = 120, this.pictureShare = 0.0});

  final Lexicon lexicon;
  final FitModel fit;
  final LevelConfig level;
  final int recentDays;

  /// Share of full-cell clues that become picture clues when the word has an image.
  final double pictureShare;

  /// Hint text shown in the clue bar for a picture clue.
  String pictureHint(LexWord w) => lexicon.lang.code == 'he'
      ? (w.wordCount > 1 ? 'בתמונה ${lexicon.lang.multiWordSuffix(w.wordCount)}' : 'בתמונה')
      : (w.wordCount > 1 ? 'pictured ${lexicon.lang.multiWordSuffix(w.wordCount)}' : 'pictured');

  static const Set<String> _usableStatus = {'approved', 'imported'};

  bool _clueUsable(LexClue c) => _usableStatus.contains(c.status) && c.minLevel <= level.level && level.level <= c.maxLevel;

  String displayText(LexWord w, LexClue c) => w.wordCount > 1 ? '${c.text} ${lexicon.lang.multiWordSuffix(w.wordCount)}' : c.text;

  /// Big grids (more than this many words) only use words with at least two
  /// usable clues: with hundreds of answers, a word whose single clue is taken
  /// or spells out another answer is a dead end too often.
  static const bigGridWords = 80;

  /// Eligibility masks: a word qualifies when it is allowed at this level and
  /// has at least one usable clue that fits the slot geometry (two usable
  /// clues on big grids, see [bigGridWords]).
  Eligibility eligibility(DictionaryIndex dict) {
    final minClues = level.targetWords > bigGridWords ? 2 : 1;
    final full = <int, Bitset>{};
    final half = <int, Bitset>{};
    for (final entry in dict.byLen.entries) {
      final len = entry.key;
      final words = entry.value;
      final f = Bitset(words.length);
      final h = Bitset(words.length);
      for (var i = 0; i < words.length; i++) {
        final w = words[i];
        if (w.blocked || w.status == 'retired') continue;
        if (w.difficulty > level.maxWordDifficulty) continue;
        if (w.isMultiword && !level.allowMultiword) continue;
        if (w.isProper && !level.allowProper) continue;
        if (minClues > 1 && w.clues.where(_clueUsable).length < minClues) continue;
        var fitsFull = false, fitsHalf = false;
        // In a picture pack the image is the clue, so a word with an image only
        // needs some usable clue record (for ids/stats), not one that fits the cell.
        if (pictureShare > 0 && w.image != null && w.clues.any(_clueUsable)) fitsFull = true;
        for (final c in w.clues) {
          if (!_clueUsable(c)) continue;
          if (c.fitsFull != null && c.fitsHalf != null && w.wordCount == 1) {
            fitsFull = fitsFull || c.fitsFull!;
            fitsHalf = fitsHalf || c.fitsHalf!;
          } else {
            final text = displayText(w, c);
            if (!fitsFull && fit.fits(text, SlotPos.full)) fitsFull = true;
            if (!fitsHalf && fit.fits(text, SlotPos.top)) fitsHalf = true;
          }
          if (fitsFull && fitsHalf) break;
        }
        if (fitsFull) f.set(i);
        if (fitsHalf) h.set(i);
      }
      full[len] = f;
      half[len] = h;
    }
    return Eligibility(full: full, half: half);
  }

  /// Picks a clue per slot. [date]/[variant] enable the recent-use rule for
  /// dailies; [usedClueIds] excludes clues already used in the same pack.
  ClueAssignment assign(List<Slot> slots, List<LexWord> words, SeededRandom rng, {String? date, String? variant, Set<String> usedClueIds = const {}}) {
    // other answers of the grid that a clue must not spell out (≥ 4 letters)
    final otherAnswers = [for (final w in words) if (w.length >= 4) w.canonical];
    final out = List<AssignedClue?>.filled(slots.length, null);
    final chosenIds = <String>{...usedClueIds};
    final target = (level.clueDifficultyMin + level.clueDifficultyMax) / 2;

    // Fewest usable clues first so scarce words get first pick.
    final order = List<int>.generate(slots.length, (i) => i)
      ..sort((a, b) => words[a].clues.length - words[b].clues.length);
    var pictures = 0;
    final maxPictures = (slots.length * pictureShare).round();
    final failed = <int>[];
    String? firstReason;
    for (final i in order) {
      final slot = slots[i];
      final word = words[i];
      if (pictureShare > 0 && word.image != null && slot.slotPos == SlotPos.full && pictures < maxPictures && rng.nextDouble() < 0.85) {
        // A picture clue still needs a textual clue record for ids/stats: use the easiest usable one.
        final usable = word.clues.where(_clueUsable).toList()..sort((a, b) => a.difficulty.compareTo(b.difficulty));
        if (usable.isNotEmpty) {
          pictures++;
          chosenIds.add(usable.first.id);
          out[i] = AssignedClue(clue: usable.first, text: pictureHint(word), lines: const [], image: word.image);
          continue;
        }
      }
      final candidates = <(LexClue, String, List<String>, double)>[];
      final reasons = <String, int>{};
      void reject(String why) => reasons[why] = (reasons[why] ?? 0) + 1;
      for (var pass = 0; pass < 2 && candidates.isEmpty; pass++) {
        reasons.clear();
        for (final c in word.clues) {
          if (!_clueUsable(c)) {
            reject('status/level');
            continue;
          }
          if (chosenIds.contains(c.id)) {
            reject('already used');
            continue;
          }
          if (pass == 0 && (c.difficulty < level.clueDifficultyMin - 0.15 || c.difficulty > level.clueDifficultyMax + 0.15)) {
            reject('difficulty band');
            continue;
          }
          if (date != null && variant != null && _usedRecently(c, variant, date)) {
            reject('used recently');
            continue;
          }
          final text = displayText(word, c);
          // the clue must not contain its own answer or give away another answer of the grid
          if (_containsAnswer(c.text, word)) {
            reject('contains answer');
            continue;
          }
          if (otherAnswers.any((a) => a != word.canonical && _containsToken(c.text, a, allowPrefix: false))) {
            reject('contains other answer');
            continue;
          }
          final lines = fit.breakLines(text, slot.slotPos);
          if (lines == null) {
            reject('does not fit ${slot.slotPos.code}');
            continue;
          }
          candidates.add((c, text, lines, c.difficulty));
        }
      }
      if (candidates.isEmpty) {
        failed.add(i);
        firstReason ??= '${word.clues.length} clues: ${reasons.entries.map((e) => '${e.key}×${e.value}').join(', ')}';
        continue;
      }
      // weighted pick: closeness to the target difficulty
      final weights = [for (final c in candidates) 1.0 / (0.15 + (c.$4 - target).abs())];
      var total = weights.fold(0.0, (a, b) => a + b);
      var x = rng.nextDouble() * total;
      var pick = candidates.last;
      for (var k = 0; k < candidates.length; k++) {
        x -= weights[k];
        if (x <= 0) {
          pick = candidates[k];
          break;
        }
      }
      total = 0;
      chosenIds.add(pick.$1.id);
      out[i] = AssignedClue(clue: pick.$1, text: pick.$2, lines: pick.$3);
    }
    if (failed.isNotEmpty) {
      return ClueAssignment(ok: false, clues: out, failedSlot: failed.first, failedSlots: failed, failureReason: firstReason);
    }
    return ClueAssignment(ok: true, clues: out);
  }

  /// True when the clue text contains the answer as a whole word (optionally
  /// with a one- or two-letter Hebrew prefix such as ה/ו/ב/ל/מ/ש/כ).
  bool _containsAnswer(String clueText, LexWord word) => _containsToken(clueText, word.canonical, allowPrefix: word.length >= 4);

  bool _containsToken(String text, String canonical, {required bool allowPrefix}) {
    for (final token in text.split(RegExp(r'[\s,.;:!?()\[\]"/\u05BE-]+'))) {
      if (token.isEmpty) continue;
      final symbols = lexicon.lang.normalize(token);
      if (symbols == null) continue;
      final key = lexicon.lang.canonicalKey(symbols);
      if (key == canonical) return true;
      if (allowPrefix && key.length > canonical.length && key.length - canonical.length <= 2 && key.endsWith(canonical)) return true;
    }
    return false;
  }

  bool _usedRecently(LexClue c, String variant, String date) {
    final last = c.lastDailyUse[variant];
    if (last == null) return false;
    final d1 = DateTime.tryParse(last);
    final d2 = DateTime.tryParse(date);
    if (d1 == null || d2 == null) return false;
    return d2.difference(d1).inDays.abs() < recentDays;
  }
}
