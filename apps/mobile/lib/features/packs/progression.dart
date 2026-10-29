import '../../core/config/game_config.dart';
import '../../core/content/manifests.dart';
import '../puzzle/data/progress_repository.dart';

/// Aggregate progress inside one pack.
class PackProgress {
  const PackProgress({this.completed = 0, this.stars = 0, this.started = 0});

  final int completed;
  final int stars;
  final int started;

  static const none = PackProgress();

  bool get isComplete => completed > 0 && completed >= 30;

  static PackProgress fromSummaries(PackInfo pack, Map<String, ProgressSummary> summaries) {
    var completed = 0;
    var stars = 0;
    var started = 0;
    for (final p in pack.puzzles) {
      final s = summaries[p.id];
      if (s == null) continue;
      if (s.completed) {
        completed++;
        stars += s.stars;
      }
      if (s.started) started++;
    }
    return PackProgress(completed: completed, stars: stars, started: started);
  }

  static Map<String, PackProgress> forPacks(Iterable<PackInfo> packs, Map<String, ProgressSummary> summaries) =>
      {for (final p in packs) p.id: fromSummaries(p, summaries)};
}

/// Pure progression rule (docs/GAME_PLAN.md §3.2): pack 1 of every level is
/// open; pack N+1 opens with ≥ [GameConfig.packUnlockStars] stars or ≥
/// [GameConfig.packUnlockCompleted] completed puzzles in pack N; Premium
/// opens everything.
bool isPackUnlocked({
  required PackInfo pack,
  required List<PackInfo> levelPacks,
  required Map<String, PackProgress> progress,
  required GameConfig config,
  bool premium = false,
}) {
  if (premium || pack.index <= 1) return true;
  PackInfo? previous;
  for (final p in levelPacks) {
    if (p.level == pack.level && p.index == pack.index - 1) previous = p;
  }
  if (previous == null) {
    // Gap in the catalogue: fall back to the highest lower index.
    for (final p in levelPacks) {
      if (p.level == pack.level && p.index < pack.index && (previous == null || p.index > previous.index)) previous = p;
    }
  }
  if (previous == null) return true;
  final prev = progress[previous.id] ?? PackProgress.none;
  return prev.stars >= config.packUnlockStars || prev.completed >= config.packUnlockCompleted;
}
