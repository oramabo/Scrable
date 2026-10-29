import 'package:chetz_app/core/config/game_config.dart';
import 'package:chetz_app/core/content/manifests.dart';
import 'package:chetz_app/features/packs/progression.dart';
import 'package:chetz_app/features/puzzle/data/progress_repository.dart';
import 'package:chetz_core/chetz_core.dart';
import 'package:flutter_test/flutter_test.dart';

PackInfo pack(int level, int index) => PackInfo(
      id: 'he-l$level-p0$index',
      lang: 'he',
      level: level,
      index: index,
      title: const {'he': 'x'},
      puzzleCount: 30,
      puzzles: [
        for (var i = 1; i <= 30; i++) PackPuzzleEntry(id: 'he-l$level-p0$index-${i.toString().padLeft(2, '0')}', index: i),
      ],
    );

ProgressSummary done(String id, int stars) => ProgressSummary(
      puzzleId: id,
      level: 1,
      kind: PuzzleKind.pack,
      completed: true,
      stars: stars,
      filledCount: 10,
      letterCount: 10,
      lastPlayedAt: 1,
      elapsedMs: 1000,
      hintsUsed: 0,
      packId: id.substring(0, id.length - 3),
    );

void main() {
  const config = GameConfig();
  final l1 = [pack(1, 1), pack(1, 2), pack(1, 3)];

  group('isPackUnlocked', () {
    test('pack 1 of every level is always open', () {
      expect(isPackUnlocked(pack: l1[0], levelPacks: l1, progress: const {}, config: config), isTrue);
      expect(isPackUnlocked(pack: pack(5, 1), levelPacks: [pack(5, 1)], progress: const {}, config: config), isTrue);
    });

    test('pack 2 is locked without progress in pack 1', () {
      expect(isPackUnlocked(pack: l1[1], levelPacks: l1, progress: const {}, config: config), isFalse);
    });

    test('45 stars in the previous pack unlock the next one', () {
      final progress = {l1[0].id: const PackProgress(completed: 15, stars: 45)};
      expect(isPackUnlocked(pack: l1[1], levelPacks: l1, progress: progress, config: config), isTrue);
      final almost = {l1[0].id: const PackProgress(completed: 15, stars: 44)};
      expect(isPackUnlocked(pack: l1[1], levelPacks: l1, progress: almost, config: config), isFalse);
    });

    test('20 completed puzzles unlock the next pack even with few stars', () {
      final progress = {l1[0].id: const PackProgress(completed: 20, stars: 20)};
      expect(isPackUnlocked(pack: l1[1], levelPacks: l1, progress: progress, config: config), isTrue);
      expect(isPackUnlocked(pack: l1[2], levelPacks: l1, progress: progress, config: config), isFalse);
    });

    test('premium opens everything', () {
      expect(isPackUnlocked(pack: l1[2], levelPacks: l1, progress: const {}, config: config, premium: true), isTrue);
    });

    test('thresholds come from the config', () {
      final lenient = GameConfig.fromJson(const {'packUnlockStars': 10, 'packUnlockCompleted': 5});
      final progress = {l1[0].id: const PackProgress(completed: 5, stars: 0)};
      expect(isPackUnlocked(pack: l1[1], levelPacks: l1, progress: progress, config: lenient), isTrue);
    });
  });

  group('PackProgress', () {
    test('aggregates completed puzzles and stars from summaries', () {
      final p = l1[0];
      final summaries = {
        for (var i = 1; i <= 12; i++) '${p.id}-${i.toString().padLeft(2, '0')}': done('${p.id}-${i.toString().padLeft(2, '0')}', 3),
        '${p.id}-13': ProgressSummary(
          puzzleId: '${p.id}-13',
          level: 1,
          kind: PuzzleKind.pack,
          completed: false,
          stars: 0,
          filledCount: 3,
          letterCount: 20,
          lastPlayedAt: 1,
          elapsedMs: 10,
          hintsUsed: 0,
          packId: p.id,
        ),
      };
      final progress = PackProgress.fromSummaries(p, summaries);
      expect(progress.completed, 12);
      expect(progress.stars, 36);
      expect(progress.started, 13);
    });
  });
}
