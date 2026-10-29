import 'package:chetz_core/chetz_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../settings/settings_controller.dart';
import '../data/progress_repository.dart';

/// In-memory mirror of `progress_index`. It follows the repository's change
/// stream, so savers (including the puzzle controller's dispose-time flush)
/// never have to modify this provider directly.
class ProgressSummariesController extends Notifier<Map<String, ProgressSummary>> {
  @override
  Map<String, ProgressSummary> build() {
    final sub = ref.watch(progressRepositoryProvider).changes.listen(upsert);
    ref.onDispose(sub.cancel);
    return Map.unmodifiable(ref.read(bootstrapProvider).summaries);
  }

  void upsert(ProgressSummary s) => state = Map.unmodifiable({...state, s.puzzleId: s});

  Future<void> reload() async => state = Map.unmodifiable(await ref.read(progressRepositoryProvider).summaries());

  void clear() => state = const {};
}

final progressSummariesProvider =
    NotifierProvider<ProgressSummariesController, Map<String, ProgressSummary>>(ProgressSummariesController.new);

final progressSummaryProvider =
    Provider.family<ProgressSummary?, String>((ref, id) => ref.watch(progressSummariesProvider)[id]);

/// The puzzle to offer under "Continue": the last opened puzzle when it is
/// unfinished, else the most recently played unfinished puzzle.
final continuePuzzleProvider = Provider<ProgressSummary?>((ref) {
  final summaries = ref.watch(progressSummariesProvider);
  final lastId = ref.watch(settingsProvider.select((s) => s.lastPuzzleId));
  final last = lastId == null ? null : summaries[lastId];
  if (last != null && !last.completed && !isMultiplayerSessionId(last.puzzleId)) return last;
  ProgressSummary? best;
  for (final s in summaries.values) {
    if (s.completed || !s.started || isMultiplayerSessionId(s.puzzleId)) continue;
    if (best == null || s.lastPlayedAt > best.lastPlayedAt) best = s;
  }
  return best;
});

/// Versus / co-op sessions are stored under `<puzzleId>?match=…` / `?room=…`.
bool isMultiplayerSessionId(String id) => id.contains('?');

/// Per-puzzle aggregates that only the progress index can answer (best times,
/// stars). Lifetime counters live in the meta layer's `PlayerStats`. Random
/// (practice) puzzles are unranked: their stars never count.
class ProgressAggregates {
  const ProgressAggregates({required this.stars, required this.bestTimeByLevel, required this.solvedByLevel});

  final int stars;
  final Map<int, int> bestTimeByLevel;
  final Map<int, int> solvedByLevel;

  static ProgressAggregates from(Iterable<ProgressSummary> rows) {
    var stars = 0;
    final best = <int, int>{};
    final byLevel = <int, int>{};
    for (final s in rows) {
      if (!s.completed || isMultiplayerSessionId(s.puzzleId)) continue;
      if (s.kind != PuzzleKind.practice) stars += s.stars;
      byLevel[s.level] = (byLevel[s.level] ?? 0) + 1;
      if (s.elapsedMs > 0 && (best[s.level] == null || s.elapsedMs < best[s.level]!)) best[s.level] = s.elapsedMs;
    }
    return ProgressAggregates(stars: stars, bestTimeByLevel: best, solvedByLevel: byLevel);
  }
}

final progressAggregatesProvider =
    Provider<ProgressAggregates>((ref) => ProgressAggregates.from(ref.watch(progressSummariesProvider).values));
