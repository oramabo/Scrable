import 'dart:collection';

import '../model/geometry.dart';
import 'level_config.dart';

/// A maximal run of ≥ 2 letter cells; becomes one word.
class Run {
  Run({required this.id, required this.dir, required this.start, required this.cells});
  final int id;
  final Dir dir;
  final Pos start;

  /// Cell indices in word order.
  final List<int> cells;
  int get len => cells.length;

  /// Candidate clue positions (filled by the validator).
  final List<ClueOption> options = [];
}

class ClueOption {
  const ClueOption({required this.cell, required this.arrow});
  final int cell;
  final Arrow arrow;
}

/// The chosen clue cell, half and arrow for a run.
class RunAssignment {
  const RunAssignment({required this.run, required this.clueCell, required this.arrow, required this.slot});
  final Run run;
  final int clueCell;
  final Arrow arrow;
  final SlotPos slot;
}

class LayoutStats {
  const LayoutStats({
    required this.letterCount,
    required this.clueCount,
    required this.density,
    required this.checkedRatio,
    required this.wordCount,
    required this.lenHist,
    required this.twoLetterShare,
    required this.bentArrows,
    required this.splitCells,
    required this.uncheckedLetters,
    required this.unusedClueCells,
  });

  final int letterCount;
  final int clueCount;
  final double density;
  final double checkedRatio;
  final int wordCount;
  final Map<int, int> lenHist;
  final double twoLetterShare;
  final int bentArrows;
  final int splitCells;
  final int uncheckedLetters;
  final int unusedClueCells;

  Map<String, dynamic> toJson() => {
        'letterCount': letterCount,
        'clueCount': clueCount,
        'density': density,
        'checkedRatio': checkedRatio,
        'wordCount': wordCount,
        'lenHist': lenHist.map((k, v) => MapEntry(k.toString(), v)),
        'twoLetterShare': twoLetterShare,
        'bentArrows': bentArrows,
        'splitCells': splitCells,
        'uncheckedLetters': uncheckedLetters,
        'unusedClueCells': unusedClueCells,
      };

  static LayoutStats fromJson(Map<String, dynamic> j) => LayoutStats(
        letterCount: j['letterCount'] as int,
        clueCount: j['clueCount'] as int,
        density: (j['density'] as num).toDouble(),
        checkedRatio: (j['checkedRatio'] as num).toDouble(),
        wordCount: j['wordCount'] as int,
        lenHist: ((j['lenHist'] as Map?) ?? {}).map((k, v) => MapEntry(int.parse(k as String), v as int)),
        twoLetterShare: (j['twoLetterShare'] as num).toDouble(),
        bentArrows: j['bentArrows'] as int,
        splitCells: j['splitCells'] as int,
        uncheckedLetters: (j['uncheckedLetters'] as int?) ?? 0,
        unusedClueCells: (j['unusedClueCells'] as int?) ?? 0,
      );
}

class LayoutResult {
  const LayoutResult({
    required this.ok,
    required this.hardViolations,
    required this.softScore,
    required this.errors,
    this.runs = const [],
    this.assignments = const [],
    this.stats,
  });

  final bool ok;

  /// Weighted count of hard-rule violations (0 when [ok]).
  final double hardViolations;

  /// Distance from the level's soft targets (lower is better).
  final double softScore;
  final List<String> errors;
  final List<Run> runs;
  final List<RunAssignment> assignments;
  final LayoutStats? stats;

  double get energy => hardViolations * 1000 + softScore;
}

/// Checks the arrowword layout rules and assigns runs to clue cells.
class LayoutValidator {
  LayoutValidator(this.config);

  final LevelConfig config;

  static List<Run> extractRuns(GridShape shape) {
    final runs = <Run>[];
    var id = 0;
    for (var r = 0; r < shape.rows; r++) {
      var c = 0;
      while (c < shape.cols) {
        if (shape.isLetter(r, c)) {
          final cells = <int>[];
          var cc = c;
          while (cc < shape.cols && shape.isLetter(r, cc)) {
            cells.add(shape.index(r, cc));
            cc++;
          }
          if (cells.length >= 2) runs.add(Run(id: id++, dir: Dir.across, start: Pos(r, c), cells: cells));
          c = cc;
        } else {
          c++;
        }
      }
    }
    for (var c = 0; c < shape.cols; c++) {
      var r = 0;
      while (r < shape.rows) {
        if (shape.isLetter(r, c)) {
          final cells = <int>[];
          var rr = r;
          while (rr < shape.rows && shape.isLetter(rr, c)) {
            cells.add(shape.index(rr, c));
            rr++;
          }
          if (cells.length >= 2) runs.add(Run(id: id++, dir: Dir.down, start: Pos(r, c), cells: cells));
          r = rr;
        } else {
          r++;
        }
      }
    }
    return runs;
  }

  /// [exact] uses min-cost flow for the clue assignment; otherwise a fast
  /// greedy pass (used inside the annealer).
  LayoutResult validate(GridShape shape, {bool exact = true}) {
    final errors = <String>[];
    var hard = 0.0;
    final runs = extractRuns(shape);
    final acrossOf = List<int>.filled(shape.cellCount, -1);
    final downOf = List<int>.filled(shape.cellCount, -1);
    for (final run in runs) {
      for (final cell in run.cells) {
        if (run.dir == Dir.across) {
          acrossOf[cell] = run.id;
        } else {
          downOf[cell] = run.id;
        }
      }
      if (run.len > config.maxWordLen) {
        hard += run.len - config.maxWordLen;
        errors.add('run_too_long ${run.start} ${run.len}');
      }
    }

    var letterCount = 0;
    var checked = 0;
    var orphans = 0;
    for (var i = 0; i < shape.cellCount; i++) {
      if (shape.kinds[i] != CellKind.letter) continue;
      letterCount++;
      final a = acrossOf[i] >= 0, d = downOf[i] >= 0;
      if (a && d) checked++;
      if (!a && !d) orphans++;
    }
    if (orphans > 0) {
      hard += orphans;
      errors.add('isolated_letters $orphans');
    }
    if (runs.isEmpty) {
      return LayoutResult(ok: false, hardViolations: hard + 100, softScore: 0, errors: [...errors, 'no_runs']);
    }

    // Candidate clue positions.
    for (final run in runs) {
      run.options.clear();
      for (final arrow in config.allowedArrows) {
        if (arrow.dir != run.dir) continue;
        final cr = run.start.r - arrow.startDr;
        final cc = run.start.c - arrow.startDc;
        if (shape.isClue(cr, cc)) run.options.add(ClueOption(cell: shape.index(cr, cc), arrow: arrow));
      }
      if (run.options.isEmpty) {
        hard += 1;
        errors.add('no_clue_position ${run.dir.name} ${run.start}');
      }
    }

    final clueCells = <int>[for (var i = 0; i < shape.cellCount; i++) if (shape.kinds[i] == CellKind.clue) i];
    final assignments = exact ? _assignExact(runs, clueCells) : _assignGreedy(runs, clueCells);
    final assignedRuns = assignments.map((a) => a.run.id).toSet();
    final unassigned = runs.where((r) => r.options.isNotEmpty && !assignedRuns.contains(r.id)).length;
    if (unassigned > 0) {
      hard += unassigned;
      errors.add('clue_capacity_exceeded $unassigned');
    }

    final perCell = <int, int>{};
    for (final a in assignments) {
      perCell[a.clueCell] = (perCell[a.clueCell] ?? 0) + 1;
    }
    // Every clue cell must carry at least one clue: a real arrowword has no blank squares.
    final unusedClueCells = clueCells.where((c) => !perCell.containsKey(c)).length;
    if (unusedClueCells > 0) {
      hard += unusedClueCells;
      errors.add('unused_clue_cells $unusedClueCells');
    }

    // Connectivity of the word graph.
    final components = _components(runs, acrossOf, downOf, shape);
    if (components > 1) {
      hard += (components - 1) * 2;
      errors.add('disconnected $components');
    }

    // Aesthetics.
    var blocks = 0;
    for (var r = 0; r + 1 < shape.rows; r++) {
      for (var c = 0; c + 1 < shape.cols; c++) {
        if (r == 0 && c == 0) continue;
        if (shape.isClue(r, c) && shape.isClue(r, c + 1) && shape.isClue(r + 1, c) && shape.isClue(r + 1, c + 1)) blocks++;
      }
    }
    if (blocks > 0) {
      hard += blocks;
      errors.add('clue_block_2x2 $blocks');
    }
    var fullLines = 0;
    for (var r = 1; r < shape.rows; r++) {
      var all = true;
      for (var c = 0; c < shape.cols; c++) {
        if (shape.isLetter(r, c)) {
          all = false;
          break;
        }
      }
      if (all) fullLines++;
    }
    for (var c = 1; c < shape.cols; c++) {
      var all = true;
      for (var r = 0; r < shape.rows; r++) {
        if (shape.isLetter(r, c)) {
          all = false;
          break;
        }
      }
      if (all) fullLines++;
    }
    if (fullLines > 0) {
      hard += fullLines;
      errors.add('full_clue_line $fullLines');
    }

    final bent = assignments.where((a) => a.arrow.isBent).length;
    if (bent > config.maxBentArrows) {
      hard += (bent - config.maxBentArrows) * 0.5;
      errors.add('too_many_bent_arrows $bent');
    }

    final checkedRatio = letterCount == 0 ? 0.0 : checked / letterCount;
    if (checkedRatio < config.minCheckedRatio) {
      hard += (config.minCheckedRatio - checkedRatio) * 20;
      errors.add('checked_ratio ${checkedRatio.toStringAsFixed(2)}');
    }
    final twoLetter = runs.where((r) => r.len == 2).length;
    final twoShare = twoLetter / runs.length;
    if (twoShare > config.max2LetterShare) {
      hard += (twoShare - config.max2LetterShare) * 20;
      errors.add('too_many_2_letter ${twoShare.toStringAsFixed(2)}');
    }

    final lenHist = <int, int>{};
    for (final r in runs) {
      lenHist[r.len] = (lenHist[r.len] ?? 0) + 1;
    }
    final stats = LayoutStats(
      letterCount: letterCount,
      clueCount: clueCells.length,
      density: letterCount / shape.cellCount,
      checkedRatio: checkedRatio,
      wordCount: runs.length,
      lenHist: lenHist,
      twoLetterShare: twoShare,
      bentArrows: bent,
      splitCells: perCell.values.where((n) => n == 2).length,
      uncheckedLetters: letterCount - checked,
      unusedClueCells: unusedClueCells,
    );

    // Soft targets.
    var soft = 0.0;
    soft += (stats.density - config.letterDensityTarget).abs() * 40;
    soft += (stats.wordCount - config.targetWords).abs() * 0.6;
    soft += (checkedRatio < config.minCheckedRatio + 0.08 ? (config.minCheckedRatio + 0.08 - checkedRatio) * 15 : 0);
    soft += stats.splitCells * 0.05; // a few split cells are fine, many are busy
    soft += bent * 0.3;
    // prefer a spread of lengths: penalise when a single length dominates
    final maxShare = lenHist.values.fold<int>(0, (m, v) => v > m ? v : m) / runs.length;
    soft += maxShare > 0.45 ? (maxShare - 0.45) * 20 : 0;

    return LayoutResult(
      ok: hard == 0,
      hardViolations: hard,
      softScore: soft,
      errors: errors,
      runs: runs,
      assignments: assignments,
      stats: stats,
    );
  }

  int _components(List<Run> runs, List<int> acrossOf, List<int> downOf, GridShape shape) {
    final parent = List<int>.generate(runs.length, (i) => i);
    int find(int x) {
      while (parent[x] != x) {
        parent[x] = parent[parent[x]];
        x = parent[x];
      }
      return x;
    }
    void union(int a, int b) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }
    for (var i = 0; i < shape.cellCount; i++) {
      if (acrossOf[i] >= 0 && downOf[i] >= 0) union(acrossOf[i], downOf[i]);
    }
    final roots = <int>{};
    for (var i = 0; i < runs.length; i++) {
      roots.add(find(i));
    }
    return roots.length;
  }

  /// Fast greedy assignment: most constrained runs first, cheapest option.
  List<RunAssignment> _assignGreedy(List<Run> runs, List<int> clueCells) {
    final order = runs.where((r) => r.options.isNotEmpty).toList()
      ..sort((a, b) => a.options.length != b.options.length ? a.options.length - b.options.length : b.len - a.len);
    final used = <int, List<SlotPos>>{}; // cell -> occupied halves
    final out = <RunAssignment>[];
    for (final run in order) {
      final opts = List<ClueOption>.from(run.options)..sort((a, b) => a.arrow.cost - b.arrow.cost);
      RunAssignment? chosen;
      for (final opt in opts) {
        final occ = used[opt.cell] ?? const [];
        if (occ.length >= 2) continue;
        for (final half in const [SlotPos.top, SlotPos.bottom]) {
          if (occ.contains(half) || !half.allows(opt.arrow.exit)) continue;
          chosen = RunAssignment(run: run, clueCell: opt.cell, arrow: opt.arrow, slot: half);
          break;
        }
        if (chosen != null) break;
      }
      if (chosen != null) {
        used.putIfAbsent(chosen.clueCell, () => []).add(chosen.slot);
        out.add(chosen);
      }
    }
    return _collapseSingles(out);
  }

  /// Exact min-cost bipartite assignment of runs to (clue cell, half).
  List<RunAssignment> _assignExact(List<Run> runs, List<int> clueCells) {
    final active = runs.where((r) => r.options.isNotEmpty).toList();
    final cellPos = <int, int>{for (var i = 0; i < clueCells.length; i++) clueCells[i]: i};
    final n = 2 + active.length + clueCells.length * 2;
    final source = 0, sink = n - 1;
    final flow = _MinCostFlow(n);
    final edgeOf = <int, (Run, int, Arrow, SlotPos)>{};
    for (var i = 0; i < active.length; i++) {
      final runNode = 1 + i;
      flow.addEdge(source, runNode, 1, 0);
      for (final opt in active[i].options) {
        for (final half in const [SlotPos.top, SlotPos.bottom]) {
          if (!half.allows(opt.arrow.exit)) continue;
          final halfNode = 1 + active.length + cellPos[opt.cell]! * 2 + (half == SlotPos.top ? 0 : 1);
          final e = flow.addEdge(runNode, halfNode, 1, opt.arrow.cost);
          edgeOf[e] = (active[i], opt.cell, opt.arrow, half);
        }
      }
    }
    for (var c = 0; c < clueCells.length; c++) {
      for (var h = 0; h < 2; h++) {
        flow.addEdge(1 + active.length + c * 2 + h, sink, 1, 0);
      }
    }
    flow.run(source, sink);
    final out = <RunAssignment>[];
    for (final entry in edgeOf.entries) {
      if (flow.flowOn(entry.key) > 0) {
        final (run, cell, arrow, half) = entry.value;
        out.add(RunAssignment(run: run, clueCell: cell, arrow: arrow, slot: half));
      }
    }
    return _collapseSingles(out);
  }

  /// Cells hosting a single clue use the full cell.
  List<RunAssignment> _collapseSingles(List<RunAssignment> assignments) {
    final count = <int, int>{};
    for (final a in assignments) {
      count[a.clueCell] = (count[a.clueCell] ?? 0) + 1;
    }
    return [
      for (final a in assignments)
        count[a.clueCell] == 1 ? RunAssignment(run: a.run, clueCell: a.clueCell, arrow: a.arrow, slot: SlotPos.full) : a,
    ];
  }
}

/// Successive shortest path min-cost max-flow for small graphs.
class _MinCostFlow {
  _MinCostFlow(this.n) : adj = List.generate(n, (_) => <int>[]);
  final int n;
  final List<List<int>> adj;
  final List<int> to = [], cap = [], cost = [];

  int addEdge(int u, int v, int c, int w) {
    final id = to.length;
    to.add(v);
    cap.add(c);
    cost.add(w);
    adj[u].add(id);
    to.add(u);
    cap.add(0);
    cost.add(-w);
    adj[v].add(id + 1);
    return id;
  }

  int flowOn(int edge) => cap[edge ^ 1];

  void run(int s, int t) {
    while (true) {
      final dist = List<int>.filled(n, 1 << 30);
      final inQueue = List<bool>.filled(n, false);
      final prevEdge = List<int>.filled(n, -1);
      dist[s] = 0;
      final q = Queue<int>()..add(s);
      while (q.isNotEmpty) {
        final u = q.removeFirst();
        inQueue[u] = false;
        for (final e in adj[u]) {
          if (cap[e] > 0 && dist[u] + cost[e] < dist[to[e]]) {
            dist[to[e]] = dist[u] + cost[e];
            prevEdge[to[e]] = e;
            if (!inQueue[to[e]]) {
              inQueue[to[e]] = true;
              q.add(to[e]);
            }
          }
        }
      }
      if (dist[t] >= 1 << 30) return;
      // augment by 1 (all capacities are 1)
      var v = t;
      while (v != s) {
        final e = prevEdge[v];
        cap[e] -= 1;
        cap[e ^ 1] += 1;
        v = to[e ^ 1];
      }
    }
  }
}

/// A validated, reusable grid shape with its clue assignment.
class LayoutTemplate {
  LayoutTemplate({required this.id, required this.level, required this.shape, required this.assignments, required this.stats, this.source = 'procedural'});

  final String id;
  final int level;
  final GridShape shape;
  final List<RunAssignment> assignments;
  final LayoutStats stats;
  final String source;

  Map<String, dynamic> toJson() => {
        'id': id,
        'level': level,
        'rows': shape.rows,
        'cols': shape.cols,
        'layout': shape.toRows(),
        'assignments': [
          for (final a in assignments)
            {
              'dir': a.run.dir == Dir.across ? 'A' : 'D',
              'r': a.run.start.r,
              'c': a.run.start.c,
              'len': a.run.len,
              'clue': shape.pos(a.clueCell).toJson(),
              'arrow': a.arrow.code,
              'slot': a.slot.code,
            }
        ],
        'stats': stats.toJson(),
        'source': source,
      };

  static LayoutTemplate fromJson(Map<String, dynamic> j) {
    final shape = GridShape.fromRows((j['layout'] as List).cast<String>());
    var id = 0;
    final assignments = <RunAssignment>[];
    for (final a in (j['assignments'] as List).cast<Map<String, dynamic>>()) {
      final dir = a['dir'] == 'A' ? Dir.across : Dir.down;
      final start = Pos(a['r'] as int, a['c'] as int);
      final len = a['len'] as int;
      final run = Run(id: id++, dir: dir, start: start, cells: [for (var k = 0; k < len; k++) shape.indexOf(start.step(dir, k))]);
      assignments.add(RunAssignment(
        run: run,
        clueCell: shape.indexOf(Pos.fromJson(a['clue'] as Map<String, dynamic>)),
        arrow: Arrow.fromCode(a['arrow'] as String),
        slot: SlotPos.fromCode(a['slot'] as String),
      ));
    }
    return LayoutTemplate(
      id: j['id'] as String,
      level: j['level'] as int,
      shape: shape,
      assignments: assignments,
      stats: LayoutStats.fromJson(j['stats'] as Map<String, dynamic>),
      source: (j['source'] as String?) ?? 'procedural',
    );
  }
}
