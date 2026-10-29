import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../settings/settings_controller.dart';
import '../data/progress_repository.dart';

/// In-memory mirror of `progress_index`, updated by the puzzle controller on
/// every save so pack/home/stats screens rebuild without disk reads.
class ProgressSummariesController extends Notifier<Map<String, ProgressSummary>> {
  @override
  Map<String, ProgressSummary> build() => Map.unmodifiable(ref.read(bootstrapProvider).summaries);

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
  if (last != null && !last.completed) return last;
  ProgressSummary? best;
  for (final s in summaries.values) {
    if (s.completed || !s.started) continue;
    if (best == null || s.lastPlayedAt > best.lastPlayedAt) best = s;
  }
  return best;
});

/// Aggregates for the stats screen.
class PlayerStats {
  const PlayerStats({
    required this.solved,
    required this.stars,
    required this.perfect,
    required this.hints,
    required this.dailies,
    required this.bestTimeByLevel,
    required this.solvedByLevel,
  });

  final int solved;
  final int stars;
  final int perfect;
  final int hints;
  final int dailies;
  final Map<int, int> bestTimeByLevel;
  final Map<int, int> solvedByLevel;

  static PlayerStats from(Iterable<ProgressSummary> rows) {
    var solved = 0, stars = 0, perfect = 0, hints = 0, dailies = 0;
    final best = <int, int>{};
    final byLevel = <int, int>{};
    for (final s in rows) {
      hints += s.hintsUsed;
      if (!s.completed) continue;
      solved++;
      stars += s.stars;
      if (s.hintsUsed == 0) perfect++;
      if (s.dailyDate != null) dailies++;
      byLevel[s.level] = (byLevel[s.level] ?? 0) + 1;
      if (s.elapsedMs > 0 && (best[s.level] == null || s.elapsedMs < best[s.level]!)) best[s.level] = s.elapsedMs;
    }
    return PlayerStats(
      solved: solved,
      stars: stars,
      perfect: perfect,
      hints: hints,
      dailies: dailies,
      bestTimeByLevel: best,
      solvedByLevel: byLevel,
    );
  }
}

final playerStatsProvider = Provider<PlayerStats>((ref) => PlayerStats.from(ref.watch(progressSummariesProvider).values));
