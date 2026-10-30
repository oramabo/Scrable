import 'package:chetz_core/generator.dart' show LevelConfig;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/content/manifests.dart';
import '../../core/providers.dart';
import '../puzzle/application/progress_providers.dart';
import '../settings/settings_controller.dart';
import '../store/store_providers.dart';
import 'progression.dart';

/// The pack levels. Grid sizes come from the generator rules, so the labels
/// match the shipped puzzles.
class LevelInfo {
  const LevelInfo(this.level);
  final int level;

  static const all = [LevelInfo(1), LevelInfo(2), LevelInfo(3), LevelInfo(4), LevelInfo(5)];

  /// Grid of this level's puzzles in [lang] (English is a column wider from level 3).
  ({int cols, int rows}) grid(String lang) {
    final c = LevelConfig.forLanguage(lang, level);
    return (cols: c.cols, rows: c.rows);
  }
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
