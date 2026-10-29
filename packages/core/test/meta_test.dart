import 'package:chetz_core/chetz_core.dart';
import 'package:chetz_core/meta.dart';
import 'package:test/test.dart';

GameEvent done({required int ts, int level = 1, bool daily = false, String? variant, String? date, PlayMode mode = PlayMode.normal, int hints = 0, int elapsed = 100000, int par = 300000, String lang = 'he', int? hour}) =>
    GameEvent.puzzleCompleted(
      timestampMs: ts,
      lang: lang,
      puzzleId: 'p$ts',
      level: level,
      mode: mode,
      elapsedMs: elapsed,
      parMs: par,
      hintsUsed: hints,
      wordsSolved: 16,
      isDaily: daily,
      dailyVariant: variant,
      dailyDate: date,
      localHour: hour,
    );

void main() {
  group('player stats', () {
    test('counts completions, perfects, streaks and languages', () {
      var s = const PlayerStats();
      s = s.apply(done(ts: 1, daily: true, variant: 'easy', date: '2026-11-01'));
      s = s.apply(done(ts: 2, daily: true, variant: 'hard', date: '2026-11-02', level: 5, lang: 'en', hour: 2));
      s = s.apply(done(ts: 3, daily: true, variant: 'easy', date: '2026-11-02', hints: 2, mode: PlayMode.relaxed));
      s = s.apply(done(ts: 4, daily: true, variant: 'easy', date: '2026-11-05'));
      expect(s.puzzlesCompleted, 4);
      expect(s.perfectPuzzles, 3);
      expect(s.dailiesCompleted, 4);
      expect(s.hardDailiesCompleted, 1);
      expect(s.bestStreak, 2);
      expect(s.currentStreak, 1); // the gap to 11-05 reset it
      expect(s.languages, {'he', 'en'});
      expect(s.completionsAtLeastLevel(5), 1);
      expect(s.nightOwlSolves, 1);
      expect(s.underHalfParSolves, 4);
      expect(s.streakOn('2026-11-06'), 1);
      expect(s.streakOn('2026-11-08'), 0);
      final back = PlayerStats.fromJson(s.toJson());
      expect(back.bestStreak, 2);
      expect(back.languages, {'he', 'en'});
    });
  });

  group('achievements', () {
    test('catalogue has 30+ unique ids and unlocks progressively', () {
      expect(Achievements.all.length, greaterThanOrEqualTo(30));
      expect(Achievements.all.map((a) => a.id).toSet().length, Achievements.all.length);
      var s = const PlayerStats();
      expect(AchievementEngine.unlocked(s), isEmpty);
      final after = s.apply(done(ts: 1));
      final newly = AchievementEngine.newlyUnlocked(s, after);
      expect(newly.map((a) => a.id), containsAll(['first_solve', 'perfect_1', 'speed_1']));
      s = after;
      for (var i = 0; i < 9; i++) {
        s = s.apply(done(ts: 10 + i, hints: 1));
      }
      expect(Achievements.byId['solver_10']!.isUnlocked(s), isTrue);
      expect(Achievements.byId['perfect_10']!.isUnlocked(s), isFalse);
      expect(Achievements.byId['solver_10']!.title('he'), isNotEmpty);
    });
  });

  group('missions', () {
    test('daily and weekly sets are deterministic and distinct', () {
      final a = MissionEngine.daily('2026-11-03');
      final b = MissionEngine.daily('2026-11-03');
      expect(a.map((m) => m.id).toList(), b.map((m) => m.id).toList());
      expect(a.length, 3);
      expect(a.map((m) => m.template.id).toSet().length, 3);
      final w = MissionEngine.weekly('2026-11-03');
      expect(w.first.periodKey, '2026-W45');
      expect(MissionEngine.weekKey('2026-01-01'), '2026-W01');
      expect(MissionEngine.weekStart('2026-11-05'), '2026-11-02');
      expect(w.every((m) => !m.template.dailyOnly), isTrue);
    });

    test('counters track progress from events', () {
      var c = const MissionCounters();
      c = c.apply(done(ts: 1, daily: true, variant: 'easy', date: '2026-11-03'));
      c = c.apply(done(ts: 2, daily: true, variant: 'hard', date: '2026-11-03', level: 5));
      c = c.apply(GameEvent.alphabetCyclerUsed(timestampMs: 3));
      final both = Mission(id: 'x', template: MissionEngine.templates.firstWhere((t) => t.id == 'any_daily'), period: MissionPeriod.daily, periodKey: '2026-11-03', target: 2, reward: 60);
      expect(c.isDone(both), isTrue);
      final lvl = Mission(id: 'y', template: MissionEngine.templates.firstWhere((t) => t.id == 'level4'), period: MissionPeriod.weekly, periodKey: '2026-W45', target: 2, reward: 180);
      expect(c.progressOf(lvl), 1);
      expect(MissionCounters.fromJson(c.toJson()).alphabetCyclerUses, 1);
      expect(both.title('en'), 'Complete both dailies');
    });
  });
}
