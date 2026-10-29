import 'dart:math' as math;

/// Player level from lifetime XP. Level n needs `xpForLevel(n)` total XP;
/// the curve grows gently so early levels feel quick.
class XpCurve {
  const XpCurve._();

  /// XP awarded by the app for a completed puzzle at [level] (0-based bonuses
  /// are applied by the caller: perfect, under par, daily).
  static int puzzleXp(int level, {bool perfect = false, bool underPar = false, bool daily = false}) {
    var xp = 20 + 15 * (level.clamp(1, 6) - 1);
    if (perfect) xp += 10;
    if (underPar) xp += 10;
    if (daily) xp += 15;
    return xp;
  }

  static const int matchWinXp = 60;
  static const int matchLossXp = 20;
  static const int coopXp = 30;
  static const int missionXp = 15;

  /// Total XP required to *reach* [level] (level 1 = 0 XP).
  static int xpForLevel(int level) {
    if (level <= 1) return 0;
    return (100 * math.pow(level - 1, 1.5)).round();
  }

  static int levelForXp(int xp) {
    var level = 1;
    while (xpForLevel(level + 1) <= xp && level < 200) {
      level++;
    }
    return level;
  }

  /// Progress inside the current level, 0..1.
  static double levelProgress(int xp) {
    final level = levelForXp(xp);
    final start = xpForLevel(level);
    final end = xpForLevel(level + 1);
    return ((xp - start) / (end - start)).clamp(0.0, 1.0);
  }

  /// Rank title index (0..5) by level, matching the plan's טירון → מאסטר ladder.
  static int rankIndex(int level) {
    if (level < 5) return 0;
    if (level < 10) return 1;
    if (level < 20) return 2;
    if (level < 35) return 3;
    if (level < 55) return 4;
    return 5;
  }

  static const List<String> rankTitlesHe = ['טירון', 'חובב', 'פותר', 'מתקדם', 'מומחה', 'מאסטר'];
  static const List<String> rankTitlesEn = ['Rookie', 'Hobbyist', 'Solver', 'Advanced', 'Expert', 'Master'];
}

/// A season-pass tier and its reward.
class SeasonTier {
  const SeasonTier({required this.index, required this.points, required this.coins, this.badge});

  /// 1-based tier number.
  final int index;

  /// Cumulative points needed to unlock the tier.
  final int points;
  final int coins;

  /// Optional cosmetic badge id for milestone tiers.
  final String? badge;
}

/// Free season pass: 6-week seasons starting 2026-11-02 (a Monday). Points
/// come from battles, dailies and missions; tiers pay coins.
class SeasonPass {
  const SeasonPass._();

  static final DateTime epoch = DateTime.utc(2026, 11, 2);
  static const int seasonDays = 42;
  static const int tierCount = 30;
  static const int pointsPerTier = 100;

  static const int pointsMatchWin = 25;
  static const int pointsMatchLoss = 5;
  static const int pointsDaily = 10;
  static const int pointsHardDaily = 20;
  static const int pointsMission = 10;
  static const int pointsPerfectPuzzle = 5;

  /// Season number (1-based) for an ISO date; dates before the epoch map to season 0.
  static int seasonNumber(String isoDate) {
    final d = DateTime.parse('${isoDate}T00:00:00Z');
    final days = d.difference(epoch).inDays;
    if (days < 0) return 0;
    return days ~/ seasonDays + 1;
  }

  /// `2026-S1`-style id (year of the season start).
  static String seasonId(String isoDate) {
    final n = seasonNumber(isoDate);
    final start = seasonStart(n);
    return '${start.year}-S$n';
  }

  static DateTime seasonStart(int number) => epoch.add(Duration(days: (number - 1) * seasonDays));
  static DateTime seasonEnd(int number) => seasonStart(number).add(const Duration(days: seasonDays));

  /// Days left in the season containing [isoDate] (0 on its last day).
  static int daysLeft(String isoDate) {
    final n = seasonNumber(isoDate);
    final end = seasonEnd(n);
    final d = DateTime.parse('${isoDate}T00:00:00Z');
    return end.difference(d).inDays - 1;
  }

  static List<SeasonTier> get tiers => List.generate(tierCount, (i) {
        final index = i + 1;
        final milestone = index % 10 == 0;
        final coins = milestone ? 300 : (index % 5 == 0 ? 120 : 40 + (index ~/ 3) * 10);
        return SeasonTier(index: index, points: index * pointsPerTier, coins: coins, badge: milestone ? 'season_tier_$index' : null);
      });

  /// Tiers unlocked by [points].
  static int tierFor(int points) => (points ~/ pointsPerTier).clamp(0, tierCount);

  /// Coins for all tiers up to [tier] (what a player would have claimed).
  static int totalCoinsThroughTier(int tier) => tiers.take(tier).fold(0, (a, t) => a + t.coins);
}

/// Trophy (rating) changes for versus matches: Elo-flavoured around a +30/−15
/// base so active players climb. Must stay identical to functions/src/lib/trophies.ts.
class Trophies {
  const Trophies._();

  static int winDelta(int mine, int theirs) {
    final expected = 1 / (1 + math.pow(10, (theirs - mine) / 400));
    return (30 + 40 * (0.5 - expected)).round().clamp(10, 50);
  }

  static int lossDelta(int mine, int theirs) {
    final expected = 1 / (1 + math.pow(10, (theirs - mine) / 400));
    return (-(15 + 40 * (expected - 0.5))).round().clamp(-25, -5);
  }

  static int applyDelta(int trophies, int delta) => math.max(0, trophies + delta);

  /// League name index (0..6) by trophies.
  static int leagueIndex(int trophies) {
    const thresholds = [0, 100, 250, 500, 900, 1500, 2500];
    var idx = 0;
    for (var i = 0; i < thresholds.length; i++) {
      if (trophies >= thresholds[i]) idx = i;
    }
    return idx;
  }

  static const List<String> leaguesHe = ['עץ', 'ברונזה', 'כסף', 'זהב', 'פלטינה', 'יהלום', 'אגדה'];
  static const List<String> leaguesEn = ['Wood', 'Bronze', 'Silver', 'Gold', 'Platinum', 'Diamond', 'Legend'];
}
