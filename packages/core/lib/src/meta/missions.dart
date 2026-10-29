import '../engine/progress.dart';
import '../generator/rng.dart';
import 'events.dart';

enum MissionPeriod { daily, weekly }

/// What a mission counts.
enum MissionKind {
  completePuzzles,
  solveWords,
  perfectPuzzles,
  completeEasyDaily,
  completeHardDaily,
  completeAnyDaily,
  useAlphabetCycler,
  newspaperPuzzles,
  underParPuzzles,
  levelPuzzles,
  earnCoins,
  shareResult,
}

class MissionTemplate {
  const MissionTemplate({
    required this.id,
    required this.kind,
    required this.dailyTarget,
    required this.weeklyTarget,
    required this.dailyReward,
    required this.weeklyReward,
    required this.titleHe,
    required this.titleEn,
    this.minLevel = 0,
    this.dailyOnly = false,
    this.weeklyOnly = false,
  });

  final String id;
  final MissionKind kind;
  final int dailyTarget;
  final int weeklyTarget;
  final int dailyReward;
  final int weeklyReward;

  /// `{n}` is replaced by the target, `{level}` by [minLevel].
  final String titleHe;
  final String titleEn;
  final int minLevel;
  final bool dailyOnly;
  final bool weeklyOnly;
}

/// A mission for a specific period.
class Mission {
  const Mission({required this.id, required this.template, required this.period, required this.periodKey, required this.target, required this.reward});

  /// `daily:2026-11-01:solve_puzzles`
  final String id;
  final MissionTemplate template;
  final MissionPeriod period;

  /// ISO date for daily missions, `YYYY-Www` for weekly ones.
  final String periodKey;
  final int target;
  final int reward;

  String title(String lang) => (lang == 'he' ? template.titleHe : template.titleEn)
      .replaceAll('{n}', target.toString())
      .replaceAll('{level}', template.minLevel.toString());
}

/// Progress counters inside one period, derived from events.
class MissionCounters {
  const MissionCounters({
    this.puzzlesCompleted = 0,
    this.wordsSolved = 0,
    this.perfectPuzzles = 0,
    this.easyDailies = 0,
    this.hardDailies = 0,
    this.alphabetCyclerUses = 0,
    this.newspaperPuzzles = 0,
    this.underParPuzzles = 0,
    this.coinsEarned = 0,
    this.shares = 0,
    this.completionsByLevel = const {},
  });

  final int puzzlesCompleted;
  final int wordsSolved;
  final int perfectPuzzles;
  final int easyDailies;
  final int hardDailies;
  final int alphabetCyclerUses;
  final int newspaperPuzzles;
  final int underParPuzzles;
  final int coinsEarned;
  final int shares;
  final Map<int, int> completionsByLevel;

  MissionCounters apply(GameEvent e) {
    switch (e.type) {
      case GameEventType.puzzleCompleted:
        final byLevel = Map<int, int>.from(completionsByLevel);
        if (e.level != null) byLevel[e.level!] = (byLevel[e.level!] ?? 0) + 1;
        return MissionCounters(
          puzzlesCompleted: puzzlesCompleted + 1,
          wordsSolved: wordsSolved + e.wordsSolved,
          perfectPuzzles: perfectPuzzles + (e.perfect ? 1 : 0),
          easyDailies: easyDailies + (e.isDaily && e.dailyVariant == 'easy' ? 1 : 0),
          hardDailies: hardDailies + (e.isDaily && e.dailyVariant == 'hard' ? 1 : 0),
          alphabetCyclerUses: alphabetCyclerUses,
          newspaperPuzzles: newspaperPuzzles + (e.mode == PlayMode.newspaper ? 1 : 0),
          underParPuzzles: underParPuzzles + (e.underPar ? 1 : 0),
          coinsEarned: coinsEarned,
          shares: shares,
          completionsByLevel: byLevel,
        );
      case GameEventType.wordSolved:
        return _with(wordsSolved: wordsSolved + e.wordsSolved);
      case GameEventType.alphabetCyclerUsed:
        return _with(alphabetCyclerUses: alphabetCyclerUses + 1);
      case GameEventType.coinsEarned:
        return _with(coinsEarned: coinsEarned + e.coins);
      case GameEventType.resultShared:
        return _with(shares: shares + 1);
      case GameEventType.hintUsed:
      case GameEventType.coinsSpent:
      case GameEventType.loginDay:
        return this;
    }
  }

  MissionCounters _with({int? wordsSolved, int? alphabetCyclerUses, int? coinsEarned, int? shares}) => MissionCounters(
        puzzlesCompleted: puzzlesCompleted,
        wordsSolved: wordsSolved ?? this.wordsSolved,
        perfectPuzzles: perfectPuzzles,
        easyDailies: easyDailies,
        hardDailies: hardDailies,
        alphabetCyclerUses: alphabetCyclerUses ?? this.alphabetCyclerUses,
        newspaperPuzzles: newspaperPuzzles,
        underParPuzzles: underParPuzzles,
        coinsEarned: coinsEarned ?? this.coinsEarned,
        shares: shares ?? this.shares,
        completionsByLevel: completionsByLevel,
      );

  int progressOf(Mission m) {
    switch (m.template.kind) {
      case MissionKind.completePuzzles:
        return puzzlesCompleted;
      case MissionKind.solveWords:
        return wordsSolved;
      case MissionKind.perfectPuzzles:
        return perfectPuzzles;
      case MissionKind.completeEasyDaily:
        return easyDailies;
      case MissionKind.completeHardDaily:
        return hardDailies;
      case MissionKind.completeAnyDaily:
        return easyDailies + hardDailies;
      case MissionKind.useAlphabetCycler:
        return alphabetCyclerUses;
      case MissionKind.newspaperPuzzles:
        return newspaperPuzzles;
      case MissionKind.underParPuzzles:
        return underParPuzzles;
      case MissionKind.levelPuzzles:
        return completionsByLevel.entries.where((e) => e.key >= m.template.minLevel).fold(0, (a, e) => a + e.value);
      case MissionKind.earnCoins:
        return coinsEarned;
      case MissionKind.shareResult:
        return shares;
    }
  }

  bool isDone(Mission m) => progressOf(m) >= m.target;

  Map<String, dynamic> toJson() => {
        'p': puzzlesCompleted,
        'w': wordsSolved,
        'pf': perfectPuzzles,
        'de': easyDailies,
        'dh': hardDailies,
        'az': alphabetCyclerUses,
        'np': newspaperPuzzles,
        'up': underParPuzzles,
        'c': coinsEarned,
        's': shares,
        'lv': completionsByLevel.map((k, v) => MapEntry(k.toString(), v)),
      };

  static MissionCounters fromJson(Map<String, dynamic> j) => MissionCounters(
        puzzlesCompleted: (j['p'] as int?) ?? 0,
        wordsSolved: (j['w'] as int?) ?? 0,
        perfectPuzzles: (j['pf'] as int?) ?? 0,
        easyDailies: (j['de'] as int?) ?? 0,
        hardDailies: (j['dh'] as int?) ?? 0,
        alphabetCyclerUses: (j['az'] as int?) ?? 0,
        newspaperPuzzles: (j['np'] as int?) ?? 0,
        underParPuzzles: (j['up'] as int?) ?? 0,
        coinsEarned: (j['c'] as int?) ?? 0,
        shares: (j['s'] as int?) ?? 0,
        completionsByLevel: ((j['lv'] as Map?) ?? const {}).map((k, v) => MapEntry(int.parse(k as String), v as int)),
      );
}

/// Deterministic daily (3) and weekly (3) missions: every player sees the
/// same set on the same day/week.
class MissionEngine {
  const MissionEngine._();

  static const List<MissionTemplate> templates = [
    MissionTemplate(id: 'solve_puzzles', kind: MissionKind.completePuzzles, dailyTarget: 2, weeklyTarget: 12, dailyReward: 30, weeklyReward: 150, titleHe: 'פתרו {n} תשחצים', titleEn: 'Complete {n} puzzles'),
    MissionTemplate(id: 'solve_words', kind: MissionKind.solveWords, dailyTarget: 25, weeklyTarget: 200, dailyReward: 25, weeklyReward: 120, titleHe: 'פתרו {n} מילים', titleEn: 'Solve {n} words'),
    MissionTemplate(id: 'perfect', kind: MissionKind.perfectPuzzles, dailyTarget: 1, weeklyTarget: 5, dailyReward: 40, weeklyReward: 200, titleHe: 'פתרו {n} תשחצים בלי רמזים', titleEn: 'Complete {n} puzzles without hints'),
    MissionTemplate(id: 'easy_daily', kind: MissionKind.completeEasyDaily, dailyTarget: 1, weeklyTarget: 5, dailyReward: 25, weeklyReward: 120, titleHe: 'פתרו את התשחץ היומי', titleEn: 'Complete the daily puzzle'),
    MissionTemplate(id: 'hard_daily', kind: MissionKind.completeHardDaily, dailyTarget: 1, weeklyTarget: 3, dailyReward: 50, weeklyReward: 200, titleHe: 'פתרו את האתגר היומי', titleEn: 'Complete the daily challenge'),
    MissionTemplate(id: 'any_daily', kind: MissionKind.completeAnyDaily, dailyTarget: 2, weeklyTarget: 10, dailyReward: 60, weeklyReward: 250, titleHe: 'פתרו את שני התשחצים היומיים', titleEn: 'Complete both dailies'),
    MissionTemplate(id: 'alphabet', kind: MissionKind.useAlphabetCycler, dailyTarget: 3, weeklyTarget: 15, dailyReward: 20, weeklyReward: 80, titleHe: 'השתמשו ברצף האותיות {n} פעמים', titleEn: 'Use the A→Z cycler {n} times'),
    MissionTemplate(id: 'newspaper', kind: MissionKind.newspaperPuzzles, dailyTarget: 1, weeklyTarget: 3, dailyReward: 35, weeklyReward: 120, titleHe: 'פתרו {n} תשחצים במצב עיתון', titleEn: 'Complete {n} puzzles in newspaper mode'),
    MissionTemplate(id: 'under_par', kind: MissionKind.underParPuzzles, dailyTarget: 1, weeklyTarget: 5, dailyReward: 35, weeklyReward: 150, titleHe: 'סיימו {n} תשחצים לפני זמן היעד', titleEn: 'Finish {n} puzzles under par'),
    MissionTemplate(id: 'level3', kind: MissionKind.levelPuzzles, dailyTarget: 1, weeklyTarget: 5, dailyReward: 30, weeklyReward: 120, titleHe: 'פתרו {n} תשחצים ברמה {level}+', titleEn: 'Complete {n} puzzles at level {level}+', minLevel: 3),
    MissionTemplate(id: 'level4', kind: MissionKind.levelPuzzles, dailyTarget: 1, weeklyTarget: 2, dailyReward: 45, weeklyReward: 180, titleHe: 'פתרו {n} תשחצים ברמה {level}+', titleEn: 'Complete {n} puzzles at level {level}+', minLevel: 4, weeklyOnly: true),
    MissionTemplate(id: 'earn_coins', kind: MissionKind.earnCoins, dailyTarget: 100, weeklyTarget: 600, dailyReward: 20, weeklyReward: 100, titleHe: 'הרוויחו {n} מטבעות', titleEn: 'Earn {n} coins'),
    MissionTemplate(id: 'share', kind: MissionKind.shareResult, dailyTarget: 1, weeklyTarget: 2, dailyReward: 20, weeklyReward: 60, titleHe: 'שתפו תוצאה', titleEn: 'Share a result', dailyOnly: false),
  ];

  static List<Mission> daily(String isoDate, {String lang = 'he', int count = 3}) {
    final pool = templates.where((t) => !t.weeklyOnly).toList();
    final rng = SeededRandom.fromString('missions|daily|$lang|$isoDate');
    rng.shuffle(pool);
    return [
      for (final t in pool.take(count))
        Mission(id: 'daily:$isoDate:${t.id}', template: t, period: MissionPeriod.daily, periodKey: isoDate, target: t.dailyTarget, reward: t.dailyReward),
    ];
  }

  static List<Mission> weekly(String isoDate, {String lang = 'he', int count = 3}) {
    final key = weekKey(isoDate);
    final pool = templates.where((t) => !t.dailyOnly).toList();
    final rng = SeededRandom.fromString('missions|weekly|$lang|$key');
    rng.shuffle(pool);
    return [
      for (final t in pool.take(count))
        Mission(id: 'weekly:$key:${t.id}', template: t, period: MissionPeriod.weekly, periodKey: key, target: t.weeklyTarget, reward: t.weeklyReward),
    ];
  }

  /// ISO-8601 week key (`2026-W44`), weeks start on Monday.
  static String weekKey(String isoDate) {
    final d = DateTime.parse(isoDate);
    final thursday = d.add(Duration(days: 4 - (d.weekday == 7 ? 7 : d.weekday)));
    final firstDay = DateTime(thursday.year, 1, 1);
    final week = ((thursday.difference(firstDay).inDays) / 7).floor() + 1;
    return '${thursday.year}-W${week.toString().padLeft(2, '0')}';
  }

  /// Monday of the week containing [isoDate] as ISO date.
  static String weekStart(String isoDate) {
    final d = DateTime.parse(isoDate);
    final monday = d.subtract(Duration(days: d.weekday - 1));
    return '${monday.year.toString().padLeft(4, '0')}-${monday.month.toString().padLeft(2, '0')}-${monday.day.toString().padLeft(2, '0')}';
  }
}
