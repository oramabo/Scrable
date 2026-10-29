import 'package:chetz_core/chetz_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/analytics/analytics.dart';
import '../../core/providers.dart';
import '../../core/util/clock.dart';
import '../settings/settings_controller.dart';
import 'daily_history.dart';

class DailyHistoryController extends Notifier<DailyHistory> {
  @override
  DailyHistory build() => ref.read(bootstrapProvider).dailyHistory;

  void _set(DailyHistory next) {
    state = next;
    ref.read(dailyRepositoryProvider).save(next).ignore();
  }

  /// Records a completion; returns the new streak.
  int markCompleted(String date, DailyVariant variant) {
    final before = state.currentStreak(ref.read(clockProvider).now());
    _set(state.markCompleted(date, variant));
    final after = state.currentStreak(ref.read(clockProvider).now());
    if (after != before) {
      ref.read(analyticsProvider).track(AnalyticsEvents.streakChange, {'from': before, 'to': after});
    }
    return after;
  }

  void freeze(String date) => _set(state.freeze(date));
  void setLoginDate(String date) => _set(state.withLoginDate(date));
  void reset() => _set(DailyHistory());
}

final dailyHistoryProvider = NotifierProvider<DailyHistoryController, DailyHistory>(DailyHistoryController.new);

/// Local date key of "today". Re-evaluated whenever the clock provider changes
/// (tests) and on each app resume via [refreshTodayProvider].
final refreshTodayProvider = NotifierProvider<_RefreshToday, int>(_RefreshToday.new);

class _RefreshToday extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final todayProvider = Provider<String>((ref) {
  ref.watch(refreshTodayProvider);
  return dateKey(ref.watch(clockProvider).now());
});

final streakProvider = Provider<int>((ref) {
  ref.watch(todayProvider);
  return ref.watch(dailyHistoryProvider).currentStreak(ref.watch(clockProvider).now());
});

final streakAtRiskProvider = Provider<bool>((ref) {
  ref.watch(todayProvider);
  return ref.watch(dailyHistoryProvider).isAtRisk(ref.watch(clockProvider).now());
});

/// Daily puzzle id for (date, variant) in the active puzzle language.
final dailyPuzzleIdProvider = FutureProvider.family<String?, (String, DailyVariant)>(
  (ref, key) => ref.watch(puzzleContentProvider).dailyPuzzleId(key.$1, key.$2),
);

final dailyAvailableProvider = FutureProvider.family<bool, (String, DailyVariant)>(
  (ref, key) => ref.watch(puzzleContentProvider).isDailyAvailable(key.$1, key.$2),
);

/// Dates shown in the archive: today and the previous [days − 1] days.
List<String> archiveDates(DateTime today, int days) =>
    [for (var i = 0; i < days; i++) dateKey(dateOnly(today).subtract(Duration(days: i)))];
