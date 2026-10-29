import 'player_stats.dart';

enum AchievementTier { bronze, silver, gold, platinum }

/// A lifetime achievement: unlocked once [progress] reaches [threshold].
class Achievement {
  const Achievement({
    required this.id,
    required this.tier,
    required this.titleHe,
    required this.titleEn,
    required this.descHe,
    required this.descEn,
    required this.rewardCoins,
    required this.threshold,
    required this.progress,
    this.icon = 'star',
  });

  final String id;
  final AchievementTier tier;
  final String titleHe;
  final String titleEn;
  final String descHe;
  final String descEn;
  final int rewardCoins;
  final int threshold;

  /// Current progress value from the stats.
  final int Function(PlayerStats) progress;

  /// Material icon name hint for the UI.
  final String icon;

  bool isUnlocked(PlayerStats s) => progress(s) >= threshold;
  double fraction(PlayerStats s) => (progress(s) / threshold).clamp(0.0, 1.0);
  String title(String lang) => lang == 'he' ? titleHe : titleEn;
  String description(String lang) => lang == 'he' ? descHe : descEn;
}

/// The catalogue (32 achievements). Ids are stable: the app stores unlocked ids.
class Achievements {
  static final List<Achievement> all = [
    Achievement(id: 'first_solve', tier: AchievementTier.bronze, titleHe: 'צעד ראשון', titleEn: 'First Step', descHe: 'פתרו תשחץ ראשון', descEn: 'Complete your first puzzle', rewardCoins: 25, threshold: 1, progress: (s) => s.puzzlesCompleted, icon: 'flag'),
    Achievement(id: 'solver_10', tier: AchievementTier.bronze, titleHe: 'מתחממים', titleEn: 'Warming Up', descHe: 'פתרו 10 תשחצים', descEn: 'Complete 10 puzzles', rewardCoins: 50, threshold: 10, progress: (s) => s.puzzlesCompleted, icon: 'grid'),
    Achievement(id: 'solver_50', tier: AchievementTier.silver, titleHe: 'פותר מנוסה', titleEn: 'Seasoned Solver', descHe: 'פתרו 50 תשחצים', descEn: 'Complete 50 puzzles', rewardCoins: 100, threshold: 50, progress: (s) => s.puzzlesCompleted, icon: 'grid'),
    Achievement(id: 'solver_100', tier: AchievementTier.gold, titleHe: 'מאה!', titleEn: 'Century', descHe: 'פתרו 100 תשחצים', descEn: 'Complete 100 puzzles', rewardCoins: 200, threshold: 100, progress: (s) => s.puzzlesCompleted, icon: 'grid'),
    Achievement(id: 'solver_500', tier: AchievementTier.platinum, titleHe: 'אגדה', titleEn: 'Legend', descHe: 'פתרו 500 תשחצים', descEn: 'Complete 500 puzzles', rewardCoins: 500, threshold: 500, progress: (s) => s.puzzlesCompleted, icon: 'trophy'),
    Achievement(id: 'perfect_1', tier: AchievementTier.bronze, titleHe: 'נקי', titleEn: 'Clean Sheet', descHe: 'פתרו תשחץ בלי רמזים', descEn: 'Complete a puzzle without hints', rewardCoins: 30, threshold: 1, progress: (s) => s.perfectPuzzles, icon: 'sparkle'),
    Achievement(id: 'perfect_10', tier: AchievementTier.silver, titleHe: 'ראש צלול', titleEn: 'Clear Head', descHe: '10 תשחצים בלי רמזים', descEn: '10 puzzles without hints', rewardCoins: 100, threshold: 10, progress: (s) => s.perfectPuzzles, icon: 'sparkle'),
    Achievement(id: 'perfect_50', tier: AchievementTier.gold, titleHe: 'פרפקציוניסט', titleEn: 'Perfectionist', descHe: '50 תשחצים בלי רמזים', descEn: '50 puzzles without hints', rewardCoins: 300, threshold: 50, progress: (s) => s.perfectPuzzles, icon: 'sparkle'),
    Achievement(id: 'daily_1', tier: AchievementTier.bronze, titleHe: 'יומי ראשון', titleEn: 'Daily Debut', descHe: 'פתרו תשחץ יומי', descEn: 'Complete a daily puzzle', rewardCoins: 25, threshold: 1, progress: (s) => s.dailiesCompleted, icon: 'calendar'),
    Achievement(id: 'streak_3', tier: AchievementTier.bronze, titleHe: 'שלושה ברצף', titleEn: 'Three in a Row', descHe: 'רצף של 3 ימים', descEn: 'A 3-day streak', rewardCoins: 30, threshold: 3, progress: (s) => s.bestStreak, icon: 'fire'),
    Achievement(id: 'streak_7', tier: AchievementTier.silver, titleHe: 'שבוע שלם', titleEn: 'Full Week', descHe: 'רצף של 7 ימים', descEn: 'A 7-day streak', rewardCoins: 75, threshold: 7, progress: (s) => s.bestStreak, icon: 'fire'),
    Achievement(id: 'streak_30', tier: AchievementTier.gold, titleHe: 'חודש של חצים', titleEn: 'Month of Arrows', descHe: 'רצף של 30 ימים', descEn: 'A 30-day streak', rewardCoins: 300, threshold: 30, progress: (s) => s.bestStreak, icon: 'fire'),
    Achievement(id: 'streak_100', tier: AchievementTier.platinum, titleHe: 'מאה ימים', titleEn: 'Hundred Days', descHe: 'רצף של 100 ימים', descEn: 'A 100-day streak', rewardCoins: 1000, threshold: 100, progress: (s) => s.bestStreak, icon: 'fire'),
    Achievement(id: 'hard_daily_1', tier: AchievementTier.silver, titleHe: 'האתגר נענה', titleEn: 'Challenge Accepted', descHe: 'פתרו את האתגר היומי', descEn: 'Complete the daily challenge', rewardCoins: 50, threshold: 1, progress: (s) => s.hardDailiesCompleted, icon: 'bolt'),
    Achievement(id: 'hard_daily_10', tier: AchievementTier.gold, titleHe: 'אלוף האתגרים', titleEn: 'Challenge Champion', descHe: '10 אתגרים יומיים', descEn: '10 daily challenges', rewardCoins: 200, threshold: 10, progress: (s) => s.hardDailiesCompleted, icon: 'bolt'),
    Achievement(id: 'pack_1', tier: AchievementTier.silver, titleHe: 'חבילה סגורה', titleEn: 'Pack Closed', descHe: 'סיימו חבילה שלמה', descEn: 'Finish a whole pack', rewardCoins: 100, threshold: 1, progress: (s) => s.packsCompleted, icon: 'box'),
    Achievement(id: 'pack_5', tier: AchievementTier.gold, titleHe: 'אספן חבילות', titleEn: 'Pack Collector', descHe: 'סיימו 5 חבילות', descEn: 'Finish 5 packs', rewardCoins: 250, threshold: 5, progress: (s) => s.packsCompleted, icon: 'box'),
    Achievement(id: 'level3_10', tier: AchievementTier.silver, titleHe: 'בינוני פלוס', titleEn: 'Stepping Up', descHe: '10 תשחצים ברמה 3 ומעלה', descEn: '10 puzzles at level 3 or higher', rewardCoins: 100, threshold: 10, progress: (s) => s.completionsAtLeastLevel(3), icon: 'stairs'),
    Achievement(id: 'expert_1', tier: AchievementTier.gold, titleHe: 'מומחה', titleEn: 'Expert', descHe: 'פתרו תשחץ ברמה 5', descEn: 'Complete a level-5 puzzle', rewardCoins: 100, threshold: 1, progress: (s) => s.completionsAtLeastLevel(5), icon: 'crown'),
    Achievement(id: 'expert_10', tier: AchievementTier.platinum, titleHe: 'מאסטר', titleEn: 'Master', descHe: '10 תשחצים ברמה 5', descEn: '10 level-5 puzzles', rewardCoins: 400, threshold: 10, progress: (s) => s.completionsAtLeastLevel(5), icon: 'crown'),
    Achievement(id: 'words_500', tier: AchievementTier.bronze, titleHe: 'אוצר מילים', titleEn: 'Vocabulary', descHe: 'פתרו 500 מילים', descEn: 'Solve 500 words', rewardCoins: 50, threshold: 500, progress: (s) => s.wordsSolved, icon: 'book'),
    Achievement(id: 'words_5000', tier: AchievementTier.gold, titleHe: 'מילון מהלך', titleEn: 'Walking Dictionary', descHe: 'פתרו 5000 מילים', descEn: 'Solve 5,000 words', rewardCoins: 300, threshold: 5000, progress: (s) => s.wordsSolved, icon: 'book'),
    Achievement(id: 'speed_1', tier: AchievementTier.silver, titleHe: 'זריז', titleEn: 'Quick', descHe: 'פתרו תשחץ בחצי מזמן היעד', descEn: 'Finish in half the par time', rewardCoins: 75, threshold: 1, progress: (s) => s.underHalfParSolves, icon: 'timer'),
    Achievement(id: 'speed_10', tier: AchievementTier.gold, titleHe: 'ברק', titleEn: 'Lightning', descHe: '10 פתרונות בחצי מזמן היעד', descEn: '10 finishes in half the par time', rewardCoins: 200, threshold: 10, progress: (s) => s.underHalfParSolves, icon: 'timer'),
    Achievement(id: 'newspaper_1', tier: AchievementTier.silver, titleHe: 'כמו בעיתון', titleEn: 'Like the Paper', descHe: 'פתרו תשחץ במצב עיתון', descEn: 'Complete a puzzle in newspaper mode', rewardCoins: 50, threshold: 1, progress: (s) => s.newspaperSolves, icon: 'newspaper'),
    Achievement(id: 'newspaper_10', tier: AchievementTier.gold, titleHe: 'פותר ותיק', titleEn: 'Old School', descHe: '10 תשחצים במצב עיתון', descEn: '10 puzzles in newspaper mode', rewardCoins: 200, threshold: 10, progress: (s) => s.newspaperSolves, icon: 'newspaper'),
    Achievement(id: 'night_owl', tier: AchievementTier.bronze, titleHe: 'ינשוף', titleEn: 'Night Owl', descHe: 'פתרו תשחץ בין חצות ל-5 בבוקר', descEn: 'Complete a puzzle between midnight and 5am', rewardCoins: 30, threshold: 1, progress: (s) => s.nightOwlSolves, icon: 'moon'),
    Achievement(id: 'early_bird', tier: AchievementTier.bronze, titleHe: 'ציפור מוקדמת', titleEn: 'Early Bird', descHe: 'פתרו תשחץ בין 5 ל-8 בבוקר', descEn: 'Complete a puzzle between 5am and 8am', rewardCoins: 30, threshold: 1, progress: (s) => s.earlyBirdSolves, icon: 'sun'),
    Achievement(id: 'polyglot', tier: AchievementTier.silver, titleHe: 'דו-לשוני', titleEn: 'Polyglot', descHe: 'פתרו תשחצים בשתי שפות', descEn: 'Complete puzzles in both languages', rewardCoins: 100, threshold: 2, progress: (s) => s.languages.length, icon: 'globe'),
    Achievement(id: 'alphabet_25', tier: AchievementTier.bronze, titleHe: 'מא׳ עד ת׳', titleEn: 'A to Z', descHe: 'השתמשו ברצף האותיות 25 פעמים', descEn: 'Use the alphabet cycler 25 times', rewardCoins: 40, threshold: 25, progress: (s) => s.alphabetCyclerUses, icon: 'abc'),
    Achievement(id: 'sharer_3', tier: AchievementTier.bronze, titleHe: 'משתפים', titleEn: 'Sharing', descHe: 'שתפו תוצאה 3 פעמים', descEn: 'Share a result 3 times', rewardCoins: 40, threshold: 3, progress: (s) => s.shares, icon: 'share'),
    Achievement(id: 'coins_1000', tier: AchievementTier.silver, titleHe: 'אוצר', titleEn: 'Treasure', descHe: 'הרוויחו 1000 מטבעות', descEn: 'Earn 1,000 coins', rewardCoins: 50, threshold: 1000, progress: (s) => s.coinsEarned, icon: 'coins'),
  ];

  static final Map<String, Achievement> byId = {for (final a in all) a.id: a};
}

class AchievementEngine {
  const AchievementEngine._();

  /// Achievements that became unlocked by moving from [before] to [after].
  static List<Achievement> newlyUnlocked(PlayerStats before, PlayerStats after) =>
      [for (final a in Achievements.all) if (!a.isUnlocked(before) && a.isUnlocked(after)) a];

  static List<Achievement> unlocked(PlayerStats s) => [for (final a in Achievements.all) if (a.isUnlocked(s)) a];
}
