import '../engine/progress.dart';
import 'events.dart';

/// Lifetime counters derived from [GameEvent]s. Immutable; [apply] returns a
/// new instance. Persisted as JSON by the app.
class PlayerStats {
  const PlayerStats({
    this.puzzlesCompleted = 0,
    this.perfectPuzzles = 0,
    this.dailiesCompleted = 0,
    this.hardDailiesCompleted = 0,
    this.wordsSolved = 0,
    this.hintsUsed = 0,
    this.coinsEarned = 0,
    this.coinsSpent = 0,
    this.alphabetCyclerUses = 0,
    this.shares = 0,
    this.nightOwlSolves = 0,
    this.earlyBirdSolves = 0,
    this.newspaperSolves = 0,
    this.relaxedSolves = 0,
    this.underParSolves = 0,
    this.underHalfParSolves = 0,
    this.packsCompleted = 0,
    this.currentStreak = 0,
    this.bestStreak = 0,
    this.lastDailyDate,
    this.languages = const {},
    this.completionsByLevel = const {},
    this.loginDays = 0,
    this.lastLoginDate,
  });

  final int puzzlesCompleted;
  final int perfectPuzzles;
  final int dailiesCompleted;
  final int hardDailiesCompleted;
  final int wordsSolved;
  final int hintsUsed;
  final int coinsEarned;
  final int coinsSpent;
  final int alphabetCyclerUses;
  final int shares;
  final int nightOwlSolves;
  final int earlyBirdSolves;
  final int newspaperSolves;
  final int relaxedSolves;
  final int underParSolves;
  final int underHalfParSolves;
  final int packsCompleted;
  final int currentStreak;
  final int bestStreak;
  final String? lastDailyDate;

  /// Languages with at least one completed puzzle.
  final Set<String> languages;
  final Map<int, int> completionsByLevel;
  final int loginDays;
  final String? lastLoginDate;

  int completionsAtLevel(int level) => completionsByLevel[level] ?? 0;
  int completionsAtLeastLevel(int level) =>
      completionsByLevel.entries.where((e) => e.key >= level).fold(0, (a, e) => a + e.value);

  PlayerStats apply(GameEvent e) {
    switch (e.type) {
      case GameEventType.puzzleCompleted:
        final byLevel = Map<int, int>.from(completionsByLevel);
        if (e.level != null) byLevel[e.level!] = (byLevel[e.level!] ?? 0) + 1;
        var streak = currentStreak;
        var best = bestStreak;
        var lastDate = lastDailyDate;
        if (e.isDaily && e.dailyDate != null && e.dailyDate != lastDailyDate) {
          streak = _isNextDay(lastDailyDate, e.dailyDate!) ? streak + 1 : 1;
          best = streak > best ? streak : best;
          lastDate = e.dailyDate;
        }
        final hour = e.localHour;
        return _copy(
          puzzlesCompleted: puzzlesCompleted + 1,
          perfectPuzzles: perfectPuzzles + (e.perfect ? 1 : 0),
          dailiesCompleted: dailiesCompleted + (e.isDaily ? 1 : 0),
          hardDailiesCompleted: hardDailiesCompleted + (e.isDaily && e.dailyVariant == 'hard' ? 1 : 0),
          wordsSolved: wordsSolved + e.wordsSolved,
          hintsUsed: hintsUsed + e.hintsUsed,
          nightOwlSolves: nightOwlSolves + (hour != null && hour < 5 ? 1 : 0),
          earlyBirdSolves: earlyBirdSolves + (hour != null && hour >= 5 && hour < 8 ? 1 : 0),
          newspaperSolves: newspaperSolves + (e.mode == PlayMode.newspaper ? 1 : 0),
          relaxedSolves: relaxedSolves + (e.mode == PlayMode.relaxed ? 1 : 0),
          underParSolves: underParSolves + (e.underPar ? 1 : 0),
          underHalfParSolves: underHalfParSolves + (e.underHalfPar ? 1 : 0),
          packsCompleted: packsCompleted + (e.completedPack ? 1 : 0),
          currentStreak: streak,
          bestStreak: best,
          lastDailyDate: lastDate,
          languages: e.lang == null ? languages : {...languages, e.lang!},
          completionsByLevel: byLevel,
        );
      case GameEventType.wordSolved:
        return _copy(wordsSolved: wordsSolved + e.wordsSolved);
      case GameEventType.hintUsed:
        return _copy(hintsUsed: hintsUsed + 1, coinsSpent: coinsSpent + e.coins);
      case GameEventType.coinsEarned:
        return _copy(coinsEarned: coinsEarned + e.coins);
      case GameEventType.coinsSpent:
        return _copy(coinsSpent: coinsSpent + e.coins);
      case GameEventType.alphabetCyclerUsed:
        return _copy(alphabetCyclerUses: alphabetCyclerUses + 1);
      case GameEventType.resultShared:
        return _copy(shares: shares + 1);
      case GameEventType.loginDay:
        if (e.dailyDate == lastLoginDate) return this;
        return _copy(loginDays: loginDays + 1, lastLoginDate: e.dailyDate);
    }
  }

  /// Streak as seen on [today]: a streak older than yesterday is broken.
  int streakOn(String today) {
    if (lastDailyDate == null) return 0;
    if (lastDailyDate == today || _isNextDay(lastDailyDate, today)) return currentStreak;
    return 0;
  }

  static bool _isNextDay(String? prev, String next) {
    if (prev == null) return false;
    final a = DateTime.tryParse(prev);
    final b = DateTime.tryParse(next);
    if (a == null || b == null) return false;
    return b.difference(a).inDays == 1;
  }

  PlayerStats _copy({
    int? puzzlesCompleted,
    int? perfectPuzzles,
    int? dailiesCompleted,
    int? hardDailiesCompleted,
    int? wordsSolved,
    int? hintsUsed,
    int? coinsEarned,
    int? coinsSpent,
    int? alphabetCyclerUses,
    int? shares,
    int? nightOwlSolves,
    int? earlyBirdSolves,
    int? newspaperSolves,
    int? relaxedSolves,
    int? underParSolves,
    int? underHalfParSolves,
    int? packsCompleted,
    int? currentStreak,
    int? bestStreak,
    String? lastDailyDate,
    Set<String>? languages,
    Map<int, int>? completionsByLevel,
    int? loginDays,
    String? lastLoginDate,
  }) =>
      PlayerStats(
        puzzlesCompleted: puzzlesCompleted ?? this.puzzlesCompleted,
        perfectPuzzles: perfectPuzzles ?? this.perfectPuzzles,
        dailiesCompleted: dailiesCompleted ?? this.dailiesCompleted,
        hardDailiesCompleted: hardDailiesCompleted ?? this.hardDailiesCompleted,
        wordsSolved: wordsSolved ?? this.wordsSolved,
        hintsUsed: hintsUsed ?? this.hintsUsed,
        coinsEarned: coinsEarned ?? this.coinsEarned,
        coinsSpent: coinsSpent ?? this.coinsSpent,
        alphabetCyclerUses: alphabetCyclerUses ?? this.alphabetCyclerUses,
        shares: shares ?? this.shares,
        nightOwlSolves: nightOwlSolves ?? this.nightOwlSolves,
        earlyBirdSolves: earlyBirdSolves ?? this.earlyBirdSolves,
        newspaperSolves: newspaperSolves ?? this.newspaperSolves,
        relaxedSolves: relaxedSolves ?? this.relaxedSolves,
        underParSolves: underParSolves ?? this.underParSolves,
        underHalfParSolves: underHalfParSolves ?? this.underHalfParSolves,
        packsCompleted: packsCompleted ?? this.packsCompleted,
        currentStreak: currentStreak ?? this.currentStreak,
        bestStreak: bestStreak ?? this.bestStreak,
        lastDailyDate: lastDailyDate ?? this.lastDailyDate,
        languages: languages ?? this.languages,
        completionsByLevel: completionsByLevel ?? this.completionsByLevel,
        loginDays: loginDays ?? this.loginDays,
        lastLoginDate: lastLoginDate ?? this.lastLoginDate,
      );

  Map<String, dynamic> toJson() => {
        'puzzlesCompleted': puzzlesCompleted,
        'perfectPuzzles': perfectPuzzles,
        'dailiesCompleted': dailiesCompleted,
        'hardDailiesCompleted': hardDailiesCompleted,
        'wordsSolved': wordsSolved,
        'hintsUsed': hintsUsed,
        'coinsEarned': coinsEarned,
        'coinsSpent': coinsSpent,
        'alphabetCyclerUses': alphabetCyclerUses,
        'shares': shares,
        'nightOwlSolves': nightOwlSolves,
        'earlyBirdSolves': earlyBirdSolves,
        'newspaperSolves': newspaperSolves,
        'relaxedSolves': relaxedSolves,
        'underParSolves': underParSolves,
        'underHalfParSolves': underHalfParSolves,
        'packsCompleted': packsCompleted,
        'currentStreak': currentStreak,
        'bestStreak': bestStreak,
        if (lastDailyDate != null) 'lastDailyDate': lastDailyDate,
        'languages': languages.toList()..sort(),
        'completionsByLevel': completionsByLevel.map((k, v) => MapEntry(k.toString(), v)),
        'loginDays': loginDays,
        if (lastLoginDate != null) 'lastLoginDate': lastLoginDate,
      };

  static PlayerStats fromJson(Map<String, dynamic> j) => PlayerStats(
        puzzlesCompleted: (j['puzzlesCompleted'] as int?) ?? 0,
        perfectPuzzles: (j['perfectPuzzles'] as int?) ?? 0,
        dailiesCompleted: (j['dailiesCompleted'] as int?) ?? 0,
        hardDailiesCompleted: (j['hardDailiesCompleted'] as int?) ?? 0,
        wordsSolved: (j['wordsSolved'] as int?) ?? 0,
        hintsUsed: (j['hintsUsed'] as int?) ?? 0,
        coinsEarned: (j['coinsEarned'] as int?) ?? 0,
        coinsSpent: (j['coinsSpent'] as int?) ?? 0,
        alphabetCyclerUses: (j['alphabetCyclerUses'] as int?) ?? 0,
        shares: (j['shares'] as int?) ?? 0,
        nightOwlSolves: (j['nightOwlSolves'] as int?) ?? 0,
        earlyBirdSolves: (j['earlyBirdSolves'] as int?) ?? 0,
        newspaperSolves: (j['newspaperSolves'] as int?) ?? 0,
        relaxedSolves: (j['relaxedSolves'] as int?) ?? 0,
        underParSolves: (j['underParSolves'] as int?) ?? 0,
        underHalfParSolves: (j['underHalfParSolves'] as int?) ?? 0,
        packsCompleted: (j['packsCompleted'] as int?) ?? 0,
        currentStreak: (j['currentStreak'] as int?) ?? 0,
        bestStreak: (j['bestStreak'] as int?) ?? 0,
        lastDailyDate: j['lastDailyDate'] as String?,
        languages: ((j['languages'] as List?) ?? const []).cast<String>().toSet(),
        completionsByLevel: ((j['completionsByLevel'] as Map?) ?? const {}).map((k, v) => MapEntry(int.parse(k as String), v as int)),
        loginDays: (j['loginDays'] as int?) ?? 0,
        lastLoginDate: j['lastLoginDate'] as String?,
      );
}
