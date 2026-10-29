import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/content/manifests.dart';
import '../../core/providers.dart';
import '../puzzle/application/progress_providers.dart';
import '../settings/settings_controller.dart';
import '../store/store_providers.dart';
import 'progression.dart';

/// Static level table from docs/GAME_PLAN.md §3.2.
class LevelInfo {
  const LevelInfo({required this.level, required this.cols, required this.rows, required this.words});
  final int level;
  final int cols;
  final int rows;
  final String words;

  static const all = [
    LevelInfo(level: 1, cols: 7, rows: 9, words: '14–18'),
    LevelInfo(level: 2, cols: 8, rows: 10, words: '20–24'),
    LevelInfo(level: 3, cols: 9, rows: 12, words: '28–32'),
    LevelInfo(level: 4, cols: 10, rows: 14, words: '36–42'),
    LevelInfo(level: 5, cols: 11, rows: 15, words: '45–55'),
  ];
}

/// All packs of the active puzzle language, sorted by level and index.
final packsProvider = FutureProvider<List<PackInfo>>((ref) => ref.watch(puzzleContentProvider).packs());

final packsOfLevelProvider = Provider.family<List<PackInfo>, int>(
  (ref, level) => (ref.watch(packsProvider).value ?? const []).where((p) => p.level == level).toList(),
);

final packProvider = Provider.family<PackInfo?, String>((ref, id) {
  for (final p in ref.watch(packsProvider).value ?? const <PackInfo>[]) {
    if (p.id == id) return p;
  }
  return null;
});

/// Progress per pack id, derived from the summaries index.
final packProgressMapProvider = Provider<Map<String, PackProgress>>((ref) {
  final packs = ref.watch(packsProvider).value ?? const <PackInfo>[];
  return PackProgress.forPacks(packs, ref.watch(progressSummariesProvider));
});

final packUnlockedProvider = Provider.family<bool, String>((ref, id) {
  final pack = ref.watch(packProvider(id));
  if (pack == null) return false;
  return isPackUnlocked(
    pack: pack,
    levelPacks: ref.watch(packsOfLevelProvider(pack.level)),
    progress: ref.watch(packProgressMapProvider),
    config: ref.watch(gameConfigProvider),
    premium: ref.watch(isPremiumProvider),
  );
});

/// Stars and completions summed over a level.
final levelProgressProvider = Provider.family<PackProgress, int>((ref, level) {
  final map = ref.watch(packProgressMapProvider);
  var completed = 0, stars = 0, started = 0;
  for (final p in ref.watch(packsOfLevelProvider(level))) {
    final pr = map[p.id] ?? PackProgress.none;
    completed += pr.completed;
    stars += pr.stars;
    started += pr.started;
  }
  return PackProgress(completed: completed, stars: stars, started: started);
});
