import 'dart:async';

import 'package:chetz_core/chetz_core.dart';

import '../../../core/storage/json_store.dart';

/// Lightweight row kept in `progress_index` so pack, home and stats screens
/// never decode full progress blobs.
class ProgressSummary {
  const ProgressSummary({
    required this.puzzleId,
    required this.level,
    required this.kind,
    required this.completed,
    required this.stars,
    required this.filledCount,
    required this.letterCount,
    required this.lastPlayedAt,
    required this.elapsedMs,
    required this.hintsUsed,
    this.packId,
    this.packIndex,
    this.dailyDate,
    this.dailyVariant,
    this.completedAt,
    this.mode = PlayMode.normal,
  });

  final String puzzleId;
  final int level;
  final PuzzleKind kind;
  final bool completed;
  final int stars;
  final int filledCount;
  final int letterCount;
  final int lastPlayedAt;
  final int elapsedMs;
  final int hintsUsed;
  final String? packId;
  final int? packIndex;
  final String? dailyDate;
  final DailyVariant? dailyVariant;
  final int? completedAt;
  final PlayMode mode;

  bool get started => filledCount > 0 || completed;
  bool get inProgress => started && !completed;

  static ProgressSummary of(PuzzleProgress p, Puzzle puzzle) => ProgressSummary(
        puzzleId: p.puzzleId,
        level: puzzle.level,
        kind: puzzle.kind,
        completed: p.completed,
        stars: p.stars,
        filledCount: p.filledCount,
        letterCount: p.letterCount,
        lastPlayedAt: p.lastPlayedAt,
        elapsedMs: p.elapsedMs,
        hintsUsed: p.hintsUsed,
        packId: puzzle.pack?.id,
        packIndex: puzzle.pack?.index,
        dailyDate: puzzle.daily?.date,
        dailyVariant: puzzle.daily?.variant,
        completedAt: p.completedAt,
        mode: p.mode,
      );

  Map<String, dynamic> toJson() => {
        'puzzleId': puzzleId,
        'level': level,
        'kind': kind.code,
        'completed': completed,
        'stars': stars,
        'filled': filledCount,
        'letters': letterCount,
        'lastPlayedAt': lastPlayedAt,
        'elapsedMs': elapsedMs,
        'hints': hintsUsed,
        if (packId != null) 'packId': packId,
        if (packIndex != null) 'packIndex': packIndex,
        if (dailyDate != null) 'dailyDate': dailyDate,
        if (dailyVariant != null) 'dailyVariant': dailyVariant!.code,
        if (completedAt != null) 'completedAt': completedAt,
        'mode': mode.code,
      };

  static ProgressSummary fromJson(Map<String, dynamic> j) => ProgressSummary(
        puzzleId: j['puzzleId'] as String,
        level: (j['level'] as int?) ?? 1,
        kind: PuzzleKind.fromCode((j['kind'] as String?) ?? 'pack'),
        completed: (j['completed'] as bool?) ?? false,
        stars: (j['stars'] as int?) ?? 0,
        filledCount: (j['filled'] as int?) ?? 0,
        letterCount: (j['letters'] as int?) ?? 0,
        lastPlayedAt: (j['lastPlayedAt'] as int?) ?? 0,
        elapsedMs: (j['elapsedMs'] as int?) ?? 0,
        hintsUsed: (j['hints'] as int?) ?? 0,
        packId: j['packId'] as String?,
        packIndex: j['packIndex'] as int?,
        dailyDate: j['dailyDate'] as String?,
        dailyVariant: j['dailyVariant'] == null ? null : DailyVariant.fromCode(j['dailyVariant'] as String),
        completedAt: j['completedAt'] as int?,
        mode: PlayMode.fromCode((j['mode'] as String?) ?? 'normal'),
      );
}

abstract class ProgressRepository {
  Future<PuzzleProgress?> load(String puzzleId);
  Future<void> save(PuzzleProgress progress, Puzzle puzzle);
  Future<Map<String, ProgressSummary>> summaries();
  Future<void> deleteAll();

  /// Emits the summary of every saved progress (listeners keep in-memory
  /// indexes fresh without the saver touching them directly).
  Stream<ProgressSummary> get changes;
}

/// One file per puzzle under `progress/`, plus `progress_index`.
class JsonProgressRepository implements ProgressRepository {
  JsonProgressRepository(this.store);

  final JsonStore store;
  Map<String, ProgressSummary>? _index;
  final StreamController<ProgressSummary> _changes = StreamController<ProgressSummary>.broadcast();

  @override
  Stream<ProgressSummary> get changes => _changes.stream;

  @override
  Future<PuzzleProgress?> load(String puzzleId) async {
    final j = await store.read('progress/$puzzleId');
    if (j == null) return null;
    try {
      return PuzzleProgress.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(PuzzleProgress progress, Puzzle puzzle) async {
    await store.write('progress/${progress.puzzleId}', progress.toJson());
    final index = await summaries();
    final summary = ProgressSummary.of(progress, puzzle);
    index[progress.puzzleId] = summary;
    await _writeIndex(index);
    _changes.add(summary);
  }

  @override
  Future<Map<String, ProgressSummary>> summaries() async {
    if (_index != null) return _index!;
    final j = await store.read('progress_index');
    final map = <String, ProgressSummary>{};
    final rows = j?['rows'];
    if (rows is Map) {
      for (final e in rows.entries) {
        try {
          map[e.key.toString()] = ProgressSummary.fromJson(e.value as Map<String, dynamic>);
        } catch (_) {
          // skip corrupt row
        }
      }
    }
    return _index = map;
  }

  Future<void> _writeIndex(Map<String, ProgressSummary> index) =>
      store.write('progress_index', {'rows': {for (final e in index.entries) e.key: e.value.toJson()}});

  @override
  Future<void> deleteAll() async {
    for (final k in await store.keys(prefix: 'progress/')) {
      await store.delete(k);
    }
    await store.delete('progress_index');
    _index = null;
  }
}
