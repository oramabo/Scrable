import 'package:chetz_app/core/util/clock.dart';
import 'package:chetz_app/features/daily/daily_history.dart';
import 'package:chetz_core/chetz_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 10, 28, 15);
  String day(int offset) => dateKey(today.subtract(Duration(days: offset)));

  group('DailyHistory streaks', () {
    test('no completions → no streak', () {
      expect(DailyHistory().currentStreak(today), 0);
      expect(DailyHistory().isAtRisk(today), isFalse);
    });

    test('consecutive days ending today', () {
      var h = DailyHistory();
      for (var i = 0; i < 3; i++) {
        h = h.markCompleted(day(i), DailyVariant.easy);
      }
      expect(h.currentStreak(today), 3);
      expect(h.isAtRisk(today), isFalse);
    });

    test('streak alive but at risk when today is not done yet', () {
      var h = DailyHistory();
      h = h.markCompleted(day(1), DailyVariant.hard).markCompleted(day(2), DailyVariant.easy);
      expect(h.currentStreak(today), 2);
      expect(h.isAtRisk(today), isTrue);
    });

    test('a gap of two days breaks the streak', () {
      var h = DailyHistory();
      h = h.markCompleted(day(2), DailyVariant.easy).markCompleted(day(3), DailyVariant.easy);
      expect(h.currentStreak(today), 0);
    });

    test('any daily counts; both do not count twice', () {
      var h = DailyHistory();
      h = h.markCompleted(day(0), DailyVariant.easy).markCompleted(day(0), DailyVariant.hard);
      expect(h.currentStreak(today), 1);
      expect(h.bothCompleted(day(0)), isTrue);
      expect(h.totalCompleted, 2);
    });

    test('a streak freeze bridges a missed day', () {
      var h = DailyHistory();
      h = h.markCompleted(day(0), DailyVariant.easy).markCompleted(day(2), DailyVariant.easy).freeze(day(1));
      expect(h.currentStreak(today), 3);
    });

    test('best streak scans history', () {
      var h = DailyHistory();
      for (final d in [10, 9, 8, 7, 6, 3, 2]) {
        h = h.markCompleted(day(d), DailyVariant.easy);
      }
      expect(h.bestStreak(), 5);
      expect(h.currentStreak(today), 0);
    });

    test('json round trip', () {
      final h = DailyHistory()
          .markCompleted(day(0), DailyVariant.easy)
          .markCompleted(day(0), DailyVariant.hard)
          .freeze(day(1))
          .withLoginDate(day(0));
      final back = DailyHistory.fromJson(h.toJson());
      expect(back.isCompleted(day(0), DailyVariant.hard), isTrue);
      expect(back.frozenDates, contains(day(1)));
      expect(back.lastLoginDate, day(0));
      expect(back.currentStreak(today), 2);
    });
  });

  group('date helpers', () {
    test('dateKey / parseDateKey', () {
      expect(dateKey(DateTime(2026, 1, 5, 23, 59)), '2026-01-05');
      expect(parseDateKey('2026-01-05'), DateTime(2026, 1, 5));
      expect(daysBetween(DateTime(2026, 1, 5, 23), DateTime(2026, 1, 6, 1)), 1);
    });

    test('formatDuration', () {
      expect(formatDuration(0), '0:00');
      expect(formatDuration(65000), '1:05');
      expect(formatDuration(3725000), '1:02:05');
    });
  });
}
