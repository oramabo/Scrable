import 'dart:math' as math;

import '../model/geometry.dart';
import 'bitset.dart';
import 'dictionary_index.dart';
import 'layout.dart';
import 'level_config.dart';
import 'lexicon.dart';
import 'rng.dart';

/// Tunables of the CSP filler.
class FillConfig {
  const FillConfig({
    this.beam = 24,
    this.sampleLimit = 700,
    this.baseNodeLimit = 4000,
    this.maxRestarts = 4,
    this.steer = 0.7,
    this.weightDifficulty = 3.0,
    this.weightCrossing = 0.55,
    this.jitter = 0.6,
    this.exactBudget = 6000,
  });

  final int beam;

  /// Candidates ranked per node (a random sample when the domain is larger).
  final int sampleLimit;

  /// Node budget of the first attempt on a 40-slot grid (scaled with the slot
  /// count); each restart gets 1.6× the previous one. A template that fills
  /// does so well inside this budget; one that does not rarely recovers.
  final int baseNodeLimit;
  final int maxRestarts;
  final double steer;

  /// Candidate ordering: difficulty steering keeps the puzzle in its score
  /// band; the crossing weight prefers words leaving the crossings more
  /// options. Weighting crossings more fills faster but misses the band and
  /// costs more templates overall.
  final double weightDifficulty;
  final double weightCrossing;
  final double jitter;

  /// Work (in 32-bit word steps) up to which the letter counts of a crossing
  /// slot are exact; beyond it they are estimated from letter frequencies.
  final int exactBudget;

  FillConfig copyWith({int? maxRestarts, int? baseNodeLimit}) => FillConfig(
        beam: beam,
        sampleLimit: sampleLimit,
        baseNodeLimit: baseNodeLimit ?? this.baseNodeLimit,
        maxRestarts: maxRestarts ?? this.maxRestarts,
        steer: steer,
        weightDifficulty: weightDifficulty,
        weightCrossing: weightCrossing,
        jitter: jitter,
        exactBudget: exactBudget,
      );
}

/// Which words may be used for slots of each geometry, per length.
class Eligibility {
  Eligibility({required this.full, required this.half});

  /// Bitsets per length for full-cell and half-cell clue slots.
  final Map<int, Bitset> full;
  final Map<int, Bitset> half;

  Bitset forSlot(SlotPos pos, int len) => (pos == SlotPos.full ? full[len] : half[len])!;
}

class Slot {
  Slot({required this.idx, required this.assignment});
  final int idx;
  final RunAssignment assignment;
  int get len => assignment.run.len;
  List<int> get cells => assignment.run.cells;
  SlotPos get slotPos => assignment.slot;
  final List<Crossing> crossings = [];
}

class Crossing {
  const Crossing({required this.cell, required this.other, required this.posInThis, required this.posInOther});
  final int cell;
  final int other;
  final int posInThis;
  final int posInOther;
}

class FillResult {
  const FillResult({required this.ok, required this.slots, required this.words, required this.nodes, required this.attempts, this.deepest = 0, this.failure});
  final bool ok;
  final List<Slot> slots;

  /// Chosen word per slot (same order as [slots]).
  final List<LexWord?> words;
  final int nodes;
  final int attempts;

  /// Most slots filled at once (tells a thrashing finish from a hard start).
  final int deepest;
  final String? failure;
}

class _Restart implements Exception {
  const _Restart();
}

/// Constraint-satisfaction filler: most-constrained slot first, bitset
/// domains, letter-level forward checking, least-constraining-value ordering
/// with difficulty steering, seeded restarts.
class Filler {
  Filler(this.dict, this.level, this.eligibility, {this.config = const FillConfig()});

  final DictionaryIndex dict;
  final LevelConfig level;
  final Eligibility eligibility;
  final FillConfig config;

  static List<Slot> buildSlots(LayoutTemplate tpl) {
    final slots = <Slot>[for (var i = 0; i < tpl.assignments.length; i++) Slot(idx: i, assignment: tpl.assignments[i])];
    final cellToSlots = <int, List<(int, int)>>{};
    for (final s in slots) {
      for (var p = 0; p < s.cells.length; p++) {
        cellToSlots.putIfAbsent(s.cells[p], () => []).add((s.idx, p));
      }
    }
    for (final entry in cellToSlots.entries) {
      final list = entry.value;
      if (list.length < 2) continue;
      for (final (a, pa) in list) {
        for (final (b, pb) in list) {
          if (a == b) continue;
          slots[a].crossings.add(Crossing(cell: entry.key, other: b, posInThis: pa, posInOther: pb));
        }
      }
    }
    return slots;
  }

  /// Fills [tpl]. [forbid] maps slot index to dictionary indices that must not
  /// be used there (words whose clues failed to fit). [excludeCanonical]
  /// keeps recently used words out of the grid.
  /// [imageBonus] favours words with pictures and [pictureTarget] is how many
  /// picture words the search tries to seed before the regular MRV order (the
  /// target shrinks on every restart so a picture-heavy start never blocks a fill).
  FillResult fill(LayoutTemplate tpl, SeededRandom rng, {Map<int, Set<int>> forbid = const {}, Set<String> excludeCanonical = const {}, double imageBonus = 0.0, int pictureTarget = 0}) {
    final slots = buildSlots(tpl);
    final n = slots.length;
    final cellCount = tpl.shape.cellCount;
    final alphabet = dict.lexicon.lang.alphabetSize;
    final grid = List<int>.filled(cellCount, -1);
    final assigned = List<int>.filled(n, -1);
    final usedByLen = <int, Bitset>{for (final len in dict.byLen.keys) len: Bitset(dict.count(len))};
    // What a slot of each (length, clue position) may take regardless of the
    // grid: eligible for the level and not excluded.
    final allowedByLen = <int, List<Bitset>>{};
    for (final entry in dict.byLen.entries) {
      final len = entry.key;
      Bitset? excluded;
      if (excludeCanonical.isNotEmpty) {
        excluded = Bitset(entry.value.length);
        for (var i = 0; i < entry.value.length; i++) {
          if (excludeCanonical.contains(entry.value[i].canonical)) excluded.set(i);
        }
      }
      allowedByLen[len] = [
        for (final pos in SlotPos.values)
          if (excluded == null) eligibility.forSlot(pos, len) else eligibility.forSlot(pos, len).andNot(excluded),
      ];
    }
    // Per slot: the words matching its grid pattern among the allowed ones,
    // before removing words used elsewhere (those change too often to bake
    // in), and the count that does exclude them, kept up to date as words are
    // placed. A slot goes dirty when a crossing word changes its pattern.
    final domainCache = List<Bitset?>.filled(n, null);
    final card = List<int>.filled(n, 0);
    final dirty = List<bool>.filled(n, true);
    final slotsByLen = <int, List<int>>{};
    for (final s in slots) {
      slotsByLen.putIfAbsent(s.len, () => []).add(s.idx);
    }
    // Picture packs: which words carry an image, per length bucket.
    final imageByLen = <int, Bitset>{};
    if (imageBonus > 0 && pictureTarget > 0) {
      for (final entry in dict.byLen.entries) {
        final b = Bitset(entry.value.length);
        for (var i = 0; i < entry.value.length; i++) {
          if (entry.value[i].image != null) b.set(i);
        }
        imageByLen[entry.key] = b;
      }
    }
    var picturesPlaced = 0;
    var pictureGoal = pictureTarget;
    var nodes = 0;
    var placed = 0;
    var deepest = 0;
    var runningSum = 0.0;
    final target0 = level.meanDifficultyTarget;

    void recompute(Slot s) {
      final pattern = [for (final c in s.cells) grid[c]];
      final base = dict.lookup(pattern).copy();
      base.andInPlace(allowedByLen[s.len]![s.slotPos.index]);
      final f = forbid[s.idx];
      if (f != null) {
        for (final w in f) {
          if (w < base.length) base.clear(w);
        }
      }
      domainCache[s.idx] = base;
      dirty[s.idx] = false;
      card[s.idx] = base.cardinalityAndNot(usedByLen[s.len]!);
    }

    void ensure(Slot s) {
      if (dirty[s.idx]) recompute(s);
    }

    void markDirty(Slot s) {
      for (final x in s.crossings) {
        dirty[x.other] = true;
      }
    }

    // Marks [w] and its twins (un)used and adjusts the counts of the clean,
    // open slots of that length that contain them.
    void setUsed(int len, int w, bool on) {
      final used = usedByLen[len]!;
      for (final id in dict.twins[len]![w] ?? [w]) {
        if (used.get(id) == on) continue;
        if (on) {
          used.set(id);
        } else {
          used.clear(id);
        }
        for (final i in slotsByLen[len]!) {
          if (assigned[i] >= 0 || dirty[i]) continue;
          if (domainCache[i]!.get(id)) card[i] += on ? -1 : 1;
        }
      }
    }

    // How many words slot [o] still has for each symbol at position [p].
    // Exact while that is cheap (walking a small domain word by word, or a
    // pass per letter over a small length bucket); a large domain gets the
    // length's letter frequencies scaled to its size instead, which orders
    // candidates nearly as well and never reports a false zero.
    List<int> symbolCounts(Slot o, int p) {
      ensure(o);
      final dom = domainCache[o.idx]!;
      final used = usedByLen[o.len]!;
      final counts = List<int>.filled(alphabet, 0);
      final c = card[o.idx];
      final walkCost = c * 4;
      final passCost = alphabet * dom.wordCount;
      if (walkCost <= passCost && walkCost <= config.exactBudget) {
        final words = dict.byLen[o.len]!;
        dom.forEachSetAndNot(used, (i) => counts[words[i].symbols[p]]++);
      } else if (passCost <= config.exactBudget) {
        final table = dict.symbolBitsets(o.len, p);
        for (var sym = 0; sym < alphabet; sym++) {
          counts[sym] = dom.cardinalityAndAndNot(table[sym], used);
        }
      } else {
        final total = dict.count(o.len);
        for (var sym = 0; sym < alphabet; sym++) {
          final f = dict.countAt(o.len, p, sym);
          counts[sym] = f == 0 ? 0 : math.max(1, f * c ~/ total);
        }
      }
      return counts;
    }

    Slot? pickSlot() {
      Slot? best;
      if (picturesPlaced < pictureGoal) {
        // Seed pictures while the grid is still open: take the longest full-cell
        // slot whose domain still contains an image word.
        var bestImages = 0;
        for (final s in slots) {
          if (assigned[s.idx] >= 0 || s.slotPos != SlotPos.full || s.len < 4) continue;
          final mask = imageByLen[s.len];
          if (mask == null) continue;
          ensure(s);
          final n = domainCache[s.idx]!.cardinalityAndAndNot(mask, usedByLen[s.len]!);
          if (n == 0) continue;
          if (best == null || s.len > best.len || (s.len == best.len && n > bestImages)) {
            best = s;
            bestImages = n;
          }
        }
        if (best != null) return best;
      }
      // Fewest candidates first. (Rating slots by candidates per open
      // crossing, or by expected survivors, was tried: it helps a template
      // full of long half-cell words but costs more everywhere else.)
      var bestSize = 1 << 30;
      for (final s in slots) {
        if (assigned[s.idx] >= 0) continue;
        ensure(s);
        final size = card[s.idx];
        if (size == 0) return s;
        if (size < bestSize ||
            (size == bestSize && best != null && (s.len > best.len || (s.len == best.len && s.crossings.length > best.crossings.length)))) {
          bestSize = size;
          best = s;
        }
      }
      return best;
    }

    List<int> rank(Slot s, SeededRandom r) {
      ensure(s);
      final dom = domainCache[s.idx]!;
      final used = usedByLen[s.len]!;
      final words = dict.byLen[s.len]!;
      // Per open crossing, what the crossing slot can still take at the shared cell.
      final crossPos = <int>[];
      final crossCounts = <List<int>>[];
      for (final x in s.crossings) {
        if (grid[x.cell] >= 0 || assigned[x.other] >= 0) continue;
        crossPos.add(x.posInThis);
        crossCounts.add(symbolCounts(slots[x.other], x.posInOther));
      }
      // Only words that leave every crossing slot at least one option: the
      // rest would fail forward checking right after being placed.
      final all = <int>[];
      dom.forEachSetAndNot(used, (w) {
        final sym = words[w].symbols;
        for (var k = 0; k < crossPos.length; k++) {
          if (crossCounts[k][sym[crossPos[k]]] == 0) return;
        }
        all.add(w);
      });
      List<int> sample = all;
      if (all.length > config.sampleLimit) {
        // reservoir-free sampling: shuffle a copy of indices and take the prefix
        final idx = List<int>.generate(all.length, (i) => i);
        r.shuffle(idx);
        sample = [for (var i = 0; i < config.sampleLimit; i++) all[idx[i]]];
        if (imageBonus > 0 && s.slotPos == SlotPos.full) {
          // Picture packs: the few words with images must always be among the candidates.
          final seen = sample.toSet();
          for (final w in all) {
            if (words[w].image != null && seen.add(w)) sample.add(w);
          }
        }
      }
      final runningMean = placed == 0 ? target0 : runningSum / placed;
      final target = (target0 + config.steer * (target0 - runningMean)).clamp(0.0, 1.0);
      final scored = <(int, double)>[];
      for (final w in sample) {
        final word = words[w];
        var score = -config.weightDifficulty * (word.difficulty - target).abs() + config.jitter * r.nextDouble();
        if (imageBonus > 0 && word.image != null && s.slotPos == SlotPos.full) score += imageBonus;
        // Least constraining value: prefer words that leave the crossings the most choices.
        for (var k = 0; k < crossPos.length; k++) {
          score += config.weightCrossing * math.log(1 + crossCounts[k][word.symbols[crossPos[k]]]);
        }
        scored.add((w, score));
      }
      scored.sort((a, b) => b.$2.compareTo(a.$2));
      return [for (final e in scored) e.$1];
    }

    List<int> place(Slot s, int w) {
      final word = dict.byLen[s.len]![w];
      final changed = <int>[];
      for (var i = 0; i < s.len; i++) {
        final c = s.cells[i];
        if (grid[c] < 0) {
          grid[c] = word.symbols[i];
          changed.add(c);
        }
      }
      assigned[s.idx] = w;
      setUsed(s.len, w, true);
      runningSum += word.difficulty;
      if (word.image != null && s.slotPos == SlotPos.full) picturesPlaced++;
      placed++;
      if (placed > deepest) deepest = placed;
      markDirty(s);
      return changed;
    }

    void unplace(Slot s, int w, List<int> changed) {
      for (final c in changed) {
        grid[c] = -1;
      }
      assigned[s.idx] = -1;
      // Its count missed the updates made while it was assigned.
      dirty[s.idx] = true;
      setUsed(s.len, w, false);
      final word = dict.byLen[s.len]![w];
      runningSum -= word.difficulty;
      if (word.image != null && s.slotPos == SlotPos.full) picturesPlaced--;
      placed--;
      markDirty(s);
    }

    bool forwardCheck(Slot s) {
      for (final x in s.crossings) {
        final o = slots[x.other];
        if (assigned[o.idx] >= 0) continue;
        ensure(o);
        if (card[o.idx] == 0) return false;
      }
      return true;
    }

    // Conflict-directed backjumping. What [s] can take depends on the placed
    // words crossing it and, through the letter-level check, on those
    // crossing its open neighbours; nothing else. When [s] runs dry, levels
    // whose slot is outside that set cannot help and are skipped.
    Set<int> culprits(Slot s) {
      final set = <int>{};
      for (final x in s.crossings) {
        final o = slots[x.other];
        if (assigned[o.idx] >= 0) {
          set.add(o.idx);
          continue;
        }
        for (final y in o.crossings) {
          if (assigned[y.other] >= 0) set.add(y.other);
        }
      }
      return set;
    }

    // The dead end reached with the most slots filled, for the failure log.
    var stuckDepth = -1;
    var stuck = '';
    void noteDeadEnd(Slot s) {
      if (placed < stuckDepth) return;
      stuckDepth = placed;
      final pattern = [for (final c in s.cells) grid[c] < 0 ? '.' : dict.lexicon.lang.symbolToDisplay(grid[c])].join();
      stuck = 'slot ${s.idx} (${s.slotPos.name}, $pattern)';
    }

    late int nodeLimit;
    // Null when the grid is complete, else the slots responsible for the dead end.
    Set<int>? search(SeededRandom r) {
      if (placed == n) return null;
      final s = pickSlot()!;
      if (card[s.idx] == 0) {
        noteDeadEnd(s);
        return culprits(s);
      }
      final candidates = rank(s, r);
      if (candidates.isEmpty) noteDeadEnd(s);
      final conflict = culprits(s);
      var tried = 0;
      for (final w in candidates) {
        if (++nodes > nodeLimit) throw const _Restart();
        final changed = place(s, w);
        if (forwardCheck(s)) {
          final deeper = search(r);
          if (deeper == null) return null;
          unplace(s, w, changed);
          // Another word here cannot fix a conflict this slot is not part of.
          if (!deeper.contains(s.idx)) return deeper;
          conflict.addAll(deeper);
        } else {
          // The emptied crossing slot is constrained by s and by slots already in the set.
          unplace(s, w, changed);
        }
        tried++;
        // beam: when the domain is large and the best candidates all failed, the
        // problem is upstream; backtrack instead of grinding through the rest
        if (tried >= config.beam && candidates.length > config.beam * 2 && placed > 0) break;
      }
      conflict.remove(s.idx);
      return conflict;
    }

    var attempts = 0;
    var totalNodes = 0;
    for (var attempt = 0; attempt < config.maxRestarts; attempt++) {
      attempts++;
      totalNodes += nodes;
      nodes = 0; // each attempt gets its own budget
      // The base budget was tuned on grids of ≤ 40 words; big grids get it per 40 slots.
      nodeLimit = (config.baseNodeLimit * math.max(1.0, n / 40) * math.pow(1.6, attempt)).round();
      final r = rng.fork('attempt$attempt');
      // reset state
      for (var i = 0; i < cellCount; i++) {
        grid[i] = -1;
      }
      for (var i = 0; i < n; i++) {
        assigned[i] = -1;
        dirty[i] = true;
        domainCache[i] = null;
      }
      for (final b in usedByLen.values) {
        b.clearAll();
      }
      placed = 0;
      runningSum = 0;
      picturesPlaced = 0;
      pictureGoal = math.max(0, pictureTarget - attempt);
      try {
        if (search(r) == null) {
          return FillResult(
            ok: true,
            slots: slots,
            words: [for (final s in slots) dict.byLen[s.len]![assigned[s.idx]]],
            nodes: totalNodes + nodes,
            attempts: attempts,
            deepest: n,
          );
        }
      } on _Restart {
        continue;
      }
    }
    return FillResult(
      ok: false,
      slots: slots,
      words: const [],
      nodes: totalNodes + nodes,
      attempts: attempts,
      deepest: deepest,
      failure: 'exhausted after $attempts attempts, ${totalNodes + nodes} nodes, deepest $deepest/$n${stuck.isEmpty ? '' : ', last stuck at depth $stuckDepth on $stuck'}',
    );
  }
}
