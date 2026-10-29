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
    this.baseNodeLimit = 8000,
    this.maxRestarts = 4,
    this.steer = 0.7,
    this.weightDifficulty = 3.0,
    this.weightCrossing = 0.55,
    this.jitter = 0.6,
  });

  final int beam;

  /// Candidates ranked per node (a random sample when the domain is larger).
  final int sampleLimit;
  final int baseNodeLimit;
  final int maxRestarts;
  final double steer;
  final double weightDifficulty;
  final double weightCrossing;
  final double jitter;
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
  const FillResult({required this.ok, required this.slots, required this.words, required this.nodes, required this.attempts, this.failure});
  final bool ok;
  final List<Slot> slots;

  /// Chosen word per slot (same order as [slots]).
  final List<LexWord?> words;
  final int nodes;
  final int attempts;
  final String? failure;
}

class _Restart implements Exception {
  const _Restart();
}

/// Constraint-satisfaction filler: most-constrained slot first, bitset
/// domains, forward checking, difficulty steering, seeded restarts.
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
  FillResult fill(LayoutTemplate tpl, SeededRandom rng, {Map<int, Set<int>> forbid = const {}, Set<String> excludeCanonical = const {}, double imageBonus = 0.0}) {
    final slots = buildSlots(tpl);
    final cellCount = tpl.shape.cellCount;
    final grid = List<int>.filled(cellCount, -1);
    final assigned = List<int>.filled(slots.length, -1);
    final usedByLen = <int, Bitset>{for (final len in dict.byLen.keys) len: Bitset(dict.count(len))};
    // Pre-mark excluded and forbidden words.
    final excludedByLen = <int, Bitset>{for (final len in dict.byLen.keys) len: Bitset(dict.count(len))};
    if (excludeCanonical.isNotEmpty) {
      for (final entry in dict.byLen.entries) {
        for (var i = 0; i < entry.value.length; i++) {
          if (excludeCanonical.contains(entry.value[i].canonical)) excludedByLen[entry.key]!.set(i);
        }
      }
    }
    final domainCache = List<Bitset?>.filled(slots.length, null);
    final dirty = List<bool>.filled(slots.length, true);
    var nodes = 0;
    var placed = 0;
    var runningSum = 0.0;
    final target0 = level.meanDifficultyTarget;

    Bitset domain(Slot s) {
      if (!dirty[s.idx] && domainCache[s.idx] != null) return domainCache[s.idx]!;
      final pattern = [for (final c in s.cells) grid[c]];
      final base = dict.lookup(pattern).copy();
      base.andInPlace(eligibility.forSlot(s.slotPos, s.len));
      base.andNotInPlace(usedByLen[s.len]!);
      base.andNotInPlace(excludedByLen[s.len]!);
      final f = forbid[s.idx];
      if (f != null) {
        for (final w in f) {
          if (w < base.length) base.clear(w);
        }
      }
      domainCache[s.idx] = base;
      dirty[s.idx] = false;
      return base;
    }

    void markDirty(Slot s) {
      dirty[s.idx] = true;
      for (final x in s.crossings) {
        dirty[x.other] = true;
      }
    }

    Slot? pickSlot() {
      Slot? best;
      var bestSize = 1 << 30;
      for (final s in slots) {
        if (assigned[s.idx] >= 0) continue;
        final size = domain(s).cardinality;
        if (size < bestSize ||
            (size == bestSize && best != null && (s.len > best.len || (s.len == best.len && s.crossings.length > best.crossings.length)))) {
          bestSize = size;
          best = s;
        }
      }
      return best;
    }

    List<int> rank(Slot s, Bitset dom, SeededRandom r) {
      final all = dom.toList();
      List<int> sample = all;
      if (all.length > config.sampleLimit) {
        // reservoir-free sampling: shuffle a copy of indices and take the prefix
        final idx = List<int>.generate(all.length, (i) => i);
        r.shuffle(idx);
        sample = [for (var i = 0; i < config.sampleLimit; i++) all[idx[i]]];
      }
      final runningMean = placed == 0 ? target0 : runningSum / placed;
      final target = (target0 + config.steer * (target0 - runningMean)).clamp(0.0, 1.0);
      final words = dict.byLen[s.len]!;
      final scored = <(int, double)>[];
      for (final w in sample) {
        final word = words[w];
        var score = -config.weightDifficulty * (word.difficulty - target).abs() + config.jitter * r.nextDouble();
        if (imageBonus > 0 && word.image != null && s.slotPos == SlotPos.full) score += imageBonus;
        for (final x in s.crossings) {
          if (grid[x.cell] >= 0) continue;
          final other = slots[x.other];
          score += config.weightCrossing * math.log(1 + dict.countAt(other.len, x.posInOther, word.symbols[x.posInThis]));
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
      usedByLen[s.len]!.set(w);
      // the same canonical word may exist under another id/length-bucket only if lengths differ, which cannot clash
      runningSum += word.difficulty;
      placed++;
      markDirty(s);
      return changed;
    }

    void unplace(Slot s, int w, List<int> changed) {
      for (final c in changed) {
        grid[c] = -1;
      }
      assigned[s.idx] = -1;
      usedByLen[s.len]!.clear(w);
      runningSum -= dict.byLen[s.len]![w].difficulty;
      placed--;
      markDirty(s);
    }

    bool forwardCheck(Slot s) {
      for (final x in s.crossings) {
        final o = slots[x.other];
        if (assigned[o.idx] >= 0) continue;
        if (domain(o).isEmpty) return false;
      }
      return true;
    }

    late int nodeLimit;
    bool search(SeededRandom r) {
      if (placed == slots.length) return true;
      final s = pickSlot()!;
      final dom = domain(s);
      if (dom.isEmpty) return false;
      final candidates = rank(s, dom, r);
      var tried = 0;
      for (final w in candidates) {
        if (++nodes > nodeLimit) throw const _Restart();
        final changed = place(s, w);
        if (forwardCheck(s) && search(r)) return true;
        unplace(s, w, changed);
        tried++;
        // beam: when the domain is large and the best candidates all failed, the
        // problem is upstream; backtrack instead of grinding through the rest
        if (tried >= config.beam && candidates.length > config.beam * 2 && placed > 0) return false;
      }
      return false;
    }

    var attempts = 0;
    var totalNodes = 0;
    for (var attempt = 0; attempt < config.maxRestarts; attempt++) {
      attempts++;
      totalNodes += nodes;
      nodes = 0; // each attempt gets its own budget
      nodeLimit = (config.baseNodeLimit * math.pow(1.6, attempt)).round();
      final r = rng.fork('attempt$attempt');
      // reset state
      for (var i = 0; i < cellCount; i++) {
        grid[i] = -1;
      }
      for (var i = 0; i < slots.length; i++) {
        assigned[i] = -1;
        dirty[i] = true;
        domainCache[i] = null;
      }
      for (final b in usedByLen.values) {
        for (var i = 0; i < b.length; i++) {
          if (b.get(i)) b.clear(i);
        }
      }
      placed = 0;
      runningSum = 0;
      try {
        if (search(r)) {
          return FillResult(
            ok: true,
            slots: slots,
            words: [for (final s in slots) dict.byLen[s.len]![assigned[s.idx]]],
            nodes: totalNodes + nodes,
            attempts: attempts,
          );
        }
      } on _Restart {
        continue;
      }
    }
    return FillResult(ok: false, slots: slots, words: const [], nodes: totalNodes + nodes, attempts: attempts, failure: 'exhausted after $attempts attempts, ${totalNodes + nodes} nodes');
  }
}
