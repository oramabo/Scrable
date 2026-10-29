import 'package:chetz_app/core/config/game_config.dart';
import 'package:chetz_core/chetz_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameConfig defaults (GAME_PLAN §3.5 / §4.1)', () {
    const c = GameConfig();

    test('economy values', () {
      expect(c.startingWallet, 200);
      expect(c.freeHints, 5);
      expect(c.completionReward(1, stars: 1), 20);
      expect(c.completionReward(3, stars: 2), 45);
      expect(c.completionReward(5, stars: 1), 80);
      expect(c.completionReward(1, stars: 3), 30, reason: '3-star bonus +50%');
      expect(c.dailyEasyReward, 40);
      expect(c.dailyHardReward, 120);
      expect(c.dailyBothBonus, 50);
      expect(c.loginBonus, 10);
      expect(c.loginBonusDay7, 50);
      expect(c.rewardedAdCoins, 25);
      expect(c.rewardedAdDailyCap, 6);
      expect(c.packUnlockStars, 45);
      expect(c.packUnlockCompleted, 20);
      expect(c.packCompletionBonus, 150);
    });

    test('hint prices', () {
      expect(c.hintPrice(HintType.revealLetter, level: 1, mode: PlayMode.normal), 15);
      expect(c.hintPrice(HintType.randomLetter, level: 1, mode: PlayMode.normal), 10);
      expect(c.hintPrice(HintType.smartLetter, level: 1, mode: PlayMode.normal), 20);
      expect(c.hintPrice(HintType.revealWord, level: 3, mode: PlayMode.normal), 40);
      expect(c.hintPrice(HintType.revealWord, level: 4, mode: PlayMode.normal), 70);
      expect(c.hintPrice(HintType.checkWord, level: 1, mode: PlayMode.normal), 5);
      expect(c.hintPrice(HintType.checkPuzzle, level: 1, mode: PlayMode.newspaper), 20);
      expect(c.hintPrice(HintType.firstLetters, level: 1, mode: PlayMode.normal), 100);
    });

    test('checks are free in relaxed mode', () {
      expect(c.hintPrice(HintType.checkWord, level: 1, mode: PlayMode.relaxed), 0);
      expect(c.hintPrice(HintType.checkPuzzle, level: 2, mode: PlayMode.relaxed), 0);
      expect(c.hintPrice(HintType.revealLetter, level: 1, mode: PlayMode.relaxed), 15);
    });

    test('par times and default modes per level', () {
      expect(c.parMs(1), 5 * 60 * 1000);
      expect(c.parMs(5), 40 * 60 * 1000);
      expect(c.defaultModeForLevel(1), PlayMode.normal);
      expect(c.defaultModeForLevel(3), PlayMode.normal);
      expect(c.defaultModeForLevel(4), PlayMode.newspaper);
    });
  });

  group('GameConfig.fromJson', () {
    test('partial override keeps the other defaults', () {
      final c = GameConfig.fromJson(const {
        'startingWallet': 500,
        'hintPrices': {'reveal_letter': 12, 'unknown_hint': 99},
        'completionRewards': {'1': 25, '6': 120},
        'parMinutes': {'2': 9},
        'interstitialEnabled': false,
        'lenientGeresh': false,
      });
      expect(c.startingWallet, 500);
      expect(c.freeHints, 5);
      expect(c.hintPrice(HintType.revealLetter, level: 1, mode: PlayMode.normal), 12);
      expect(c.hintPrice(HintType.smartLetter, level: 1, mode: PlayMode.normal), 20);
      expect(c.completionReward(1, stars: 1), 25);
      expect(c.completionReward(2, stars: 1), 30);
      expect(c.completionReward(6, stars: 1), 120);
      expect(c.parMs(2), 9 * 60 * 1000);
      expect(c.parMs(1), 5 * 60 * 1000);
      expect(c.interstitialEnabled, isFalse);
      expect(c.lenientGeresh, isFalse);
    });

    test('ignores wrong types', () {
      final c = GameConfig.fromJson(const {'startingWallet': 'lots', 'hintPrices': 'nope', 'parMinutes': []});
      expect(c.startingWallet, 200);
      expect(c.hintPrices, GameConfig.defaultHintPrices);
      expect(c.parMinutes, GameConfig.defaultParMinutes);
    });

    test('toJson → fromJson is lossless', () {
      const original = GameConfig(startingWallet: 123, revealWordPriceHighLevel: 77, archiveFreeDays: 9);
      final back = GameConfig.fromJson(original.toJson());
      expect(back.startingWallet, 123);
      expect(back.revealWordPriceHighLevel, 77);
      expect(back.archiveFreeDays, 9);
      expect(back.toJson(), original.toJson());
    });
  });
}
