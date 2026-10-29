import 'package:chetz_core/chetz_core.dart';

/// Hint kinds the app sells. Prices live in [GameConfig].
enum HintType {
  revealLetter('reveal_letter'),
  randomLetter('random_letter'),
  smartLetter('smart_letter'),
  revealWord('reveal_word'),
  checkWord('check_word'),
  checkPuzzle('check_puzzle'),
  firstLetters('first_letters');

  const HintType(this.code);
  final String code;
}

/// Economy, hint prices, progression thresholds, par times and ad caps.
///
/// Defaults follow docs/GAME_PLAN.md §3.5 / §4.1 / §4.3. Every value can be
/// overridden from a JSON map (Remote Config) via [GameConfig.fromJson]; keys
/// that are missing keep their default so partial configs are safe.
class GameConfig {
  const GameConfig({
    this.startingWallet = 200,
    this.freeHints = 5,
    this.hintPrices = defaultHintPrices,
    this.revealWordPriceHighLevel = 70,
    this.revealWordHighLevelFrom = 4,
    this.completionRewards = defaultCompletionRewards,
    this.threeStarBonusPercent = 50,
    this.dailyEasyReward = 40,
    this.dailyHardReward = 120,
    this.dailyBothBonus = 50,
    this.loginBonus = 10,
    this.loginBonusDay7 = 50,
    this.rewardedAdCoins = 25,
    this.rewardedAdDailyCap = 6,
    this.packUnlockStars = 45,
    this.packUnlockCompleted = 20,
    this.packCompletionBonus = 150,
    this.parMinutes = defaultParMinutes,
    this.interstitialEnabled = true,
    this.interstitialMinCompletedPuzzles = 3,
    this.interstitialEveryNCompletions = 2,
    this.interstitialMinIntervalSec = 180,
    this.quietAfterRewardedSec = 60,
    this.rewardedCooldownSec = 180,
    this.archiveFreeDays = 7,
    this.archiveDayPrice = 50,
    this.streakFreezePrice = 150,
    this.lenientGeresh = true,
    this.newspaperFromLevel = 4,
  });

  static const Map<HintType, int> defaultHintPrices = {
    HintType.revealLetter: 15,
    HintType.randomLetter: 10,
    HintType.smartLetter: 20,
    HintType.revealWord: 40,
    HintType.checkWord: 5,
    HintType.checkPuzzle: 20,
    HintType.firstLetters: 100,
  };

  /// Coins for completing a puzzle, by level (1-based).
  static const Map<int, int> defaultCompletionRewards = {1: 20, 2: 30, 3: 45, 4: 60, 5: 80, 6: 100};

  /// Par time per level in minutes (upper end of the target range).
  static const Map<int, int> defaultParMinutes = {1: 5, 2: 8, 3: 14, 4: 25, 5: 40, 6: 60};

  final int startingWallet;
  final int freeHints;
  final Map<HintType, int> hintPrices;
  final int revealWordPriceHighLevel;
  final int revealWordHighLevelFrom;
  final Map<int, int> completionRewards;
  final int threeStarBonusPercent;
  final int dailyEasyReward;
  final int dailyHardReward;
  final int dailyBothBonus;
  final int loginBonus;
  final int loginBonusDay7;
  final int rewardedAdCoins;
  final int rewardedAdDailyCap;
  final int packUnlockStars;
  final int packUnlockCompleted;
  final int packCompletionBonus;
  final Map<int, int> parMinutes;
  final bool interstitialEnabled;
  final int interstitialMinCompletedPuzzles;
  final int interstitialEveryNCompletions;
  final int interstitialMinIntervalSec;
  final int quietAfterRewardedSec;
  final int rewardedCooldownSec;
  final int archiveFreeDays;
  final int archiveDayPrice;
  final int streakFreezePrice;
  final bool lenientGeresh;
  final int newspaperFromLevel;

  /// Price of a hint for a puzzle of [level] played in [mode]. Checks are free
  /// in relaxed mode.
  int hintPrice(HintType type, {required int level, required PlayMode mode}) {
    if (mode == PlayMode.relaxed && (type == HintType.checkWord || type == HintType.checkPuzzle)) return 0;
    if (type == HintType.revealWord && level >= revealWordHighLevelFrom) return revealWordPriceHighLevel;
    return hintPrices[type] ?? defaultHintPrices[type]!;
  }

  int completionReward(int level, {required int stars}) {
    final base = completionRewards[level] ?? completionRewards.values.last;
    if (stars >= 3) return base + (base * threeStarBonusPercent / 100).round();
    return base;
  }

  int parMs(int level) => (parMinutes[level] ?? parMinutes.values.last) * 60 * 1000;

  PlayMode defaultModeForLevel(int level) => level >= newspaperFromLevel ? PlayMode.newspaper : PlayMode.normal;

  /// Merges [j] over the defaults. Unknown keys are ignored.
  factory GameConfig.fromJson(Map<String, dynamic> j, {GameConfig base = const GameConfig()}) {
    int i(String key, int def) {
      final v = j[key];
      return v is num ? v.toInt() : def;
    }

    bool b(String key, bool def) {
      final v = j[key];
      return v is bool ? v : def;
    }

    Map<int, int> intMap(String key, Map<int, int> def) {
      final v = j[key];
      if (v is! Map) return def;
      final out = Map<int, int>.from(def);
      for (final e in v.entries) {
        final k = int.tryParse(e.key.toString());
        if (k != null && e.value is num) out[k] = (e.value as num).toInt();
      }
      return out;
    }

    Map<HintType, int> hintMap(String key, Map<HintType, int> def) {
      final v = j[key];
      if (v is! Map) return def;
      final out = Map<HintType, int>.from(def);
      for (final e in v.entries) {
        for (final t in HintType.values) {
          if (t.code == e.key && e.value is num) out[t] = (e.value as num).toInt();
        }
      }
      return out;
    }

    return GameConfig(
      startingWallet: i('startingWallet', base.startingWallet),
      freeHints: i('freeHints', base.freeHints),
      hintPrices: hintMap('hintPrices', base.hintPrices),
      revealWordPriceHighLevel: i('revealWordPriceHighLevel', base.revealWordPriceHighLevel),
      revealWordHighLevelFrom: i('revealWordHighLevelFrom', base.revealWordHighLevelFrom),
      completionRewards: intMap('completionRewards', base.completionRewards),
      threeStarBonusPercent: i('threeStarBonusPercent', base.threeStarBonusPercent),
      dailyEasyReward: i('dailyEasyReward', base.dailyEasyReward),
      dailyHardReward: i('dailyHardReward', base.dailyHardReward),
      dailyBothBonus: i('dailyBothBonus', base.dailyBothBonus),
      loginBonus: i('loginBonus', base.loginBonus),
      loginBonusDay7: i('loginBonusDay7', base.loginBonusDay7),
      rewardedAdCoins: i('rewardedAdCoins', base.rewardedAdCoins),
      rewardedAdDailyCap: i('rewardedAdDailyCap', base.rewardedAdDailyCap),
      packUnlockStars: i('packUnlockStars', base.packUnlockStars),
      packUnlockCompleted: i('packUnlockCompleted', base.packUnlockCompleted),
      packCompletionBonus: i('packCompletionBonus', base.packCompletionBonus),
      parMinutes: intMap('parMinutes', base.parMinutes),
      interstitialEnabled: b('interstitialEnabled', base.interstitialEnabled),
      interstitialMinCompletedPuzzles: i('interstitialMinCompletedPuzzles', base.interstitialMinCompletedPuzzles),
      interstitialEveryNCompletions: i('interstitialEveryNCompletions', base.interstitialEveryNCompletions),
      interstitialMinIntervalSec: i('interstitialMinIntervalSec', base.interstitialMinIntervalSec),
      quietAfterRewardedSec: i('quietAfterRewardedSec', base.quietAfterRewardedSec),
      rewardedCooldownSec: i('rewardedCooldownSec', base.rewardedCooldownSec),
      archiveFreeDays: i('archiveFreeDays', base.archiveFreeDays),
      archiveDayPrice: i('archiveDayPrice', base.archiveDayPrice),
      streakFreezePrice: i('streakFreezePrice', base.streakFreezePrice),
      lenientGeresh: b('lenientGeresh', base.lenientGeresh),
      newspaperFromLevel: i('newspaperFromLevel', base.newspaperFromLevel),
    );
  }

  Map<String, dynamic> toJson() => {
        'startingWallet': startingWallet,
        'freeHints': freeHints,
        'hintPrices': {for (final e in hintPrices.entries) e.key.code: e.value},
        'revealWordPriceHighLevel': revealWordPriceHighLevel,
        'revealWordHighLevelFrom': revealWordHighLevelFrom,
        'completionRewards': {for (final e in completionRewards.entries) '${e.key}': e.value},
        'threeStarBonusPercent': threeStarBonusPercent,
        'dailyEasyReward': dailyEasyReward,
        'dailyHardReward': dailyHardReward,
        'dailyBothBonus': dailyBothBonus,
        'loginBonus': loginBonus,
        'loginBonusDay7': loginBonusDay7,
        'rewardedAdCoins': rewardedAdCoins,
        'rewardedAdDailyCap': rewardedAdDailyCap,
        'packUnlockStars': packUnlockStars,
        'packUnlockCompleted': packUnlockCompleted,
        'packCompletionBonus': packCompletionBonus,
        'parMinutes': {for (final e in parMinutes.entries) '${e.key}': e.value},
        'interstitialEnabled': interstitialEnabled,
        'interstitialMinCompletedPuzzles': interstitialMinCompletedPuzzles,
        'interstitialEveryNCompletions': interstitialEveryNCompletions,
        'interstitialMinIntervalSec': interstitialMinIntervalSec,
        'quietAfterRewardedSec': quietAfterRewardedSec,
        'rewardedCooldownSec': rewardedCooldownSec,
        'archiveFreeDays': archiveFreeDays,
        'archiveDayPrice': archiveDayPrice,
        'streakFreezePrice': streakFreezePrice,
        'lenientGeresh': lenientGeresh,
        'newspaperFromLevel': newspaperFromLevel,
      };
}
