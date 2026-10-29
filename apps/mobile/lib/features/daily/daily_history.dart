import 'package:chetz_core/chetz_core.dart';

import '../../core/storage/json_store.dart';
import '../../core/util/clock.dart';

/// Which dailies were completed on which local date, plus streak freezes
/// that were consumed. Streaks are derived, never stored.
class DailyHistory {
  DailyHistory({Map<String, Set<DailyVariant>>? completed, Set<String>? frozenDates, this.lastLoginDate})
      : completed = completed ?? {},
        frozenDates = frozenDates ?? {};

  /// `YYYY-MM-DD` → variants completed that day.
  final Map<String, Set<DailyVariant>> completed;

  /// Dates covered by a streak freeze.
  final Set<String> frozenDates;

  /// Last date the login bonus was granted (`YYYY-MM-DD`).
  final String? lastLoginDate;

  bool isCompleted(String date, DailyVariant v) => completed[date]?.contains(v) ?? false;
  bool anyCompleted(String date) => completed[date]?.isNotEmpty ?? false;
  bool bothCompleted(String date) => (completed[date]?.length ?? 0) >= 2;

  /// Whether [date] keeps a streak alive (a completion or a freeze).
  bool countsForStreak(String date) => anyCompleted(date) || frozenDates.contains(date);

  DailyHistory markCompleted(String date, DailyVariant v) {
    final next = {for (final e in completed.entries) e.key: Set<DailyVariant>.from(e.value)};
    (next[date] ??= {}).add(v);
    return DailyHistory(completed: next, frozenDates: frozenDates, lastLoginDate: lastLoginDate);
  }

  DailyHistory freeze(String date) =>
      DailyHistory(completed: completed, frozenDates: {...frozenDates, date}, lastLoginDate: lastLoginDate);

  DailyHistory withLoginDate(String date) => DailyHistory(completed: completed, frozenDates: frozenDates, lastLoginDate: date);

  /// Current streak as of [today]. Counts consecutive days ending today, or
  /// ending yesterday when today has no completion yet (the streak is then
  /// "at risk" but still alive).
  int currentStreak(DateTime today) {
    var day = dateOnly(today);
    if (!countsForStreak(dateKey(day))) {
      day = day.subtract(const Duration(days: 1));
      if (!countsForStreak(dateKey(day))) return 0;
    }
    var n = 0;
    while (countsForStreak(dateKey(day))) {
      n++;
      day = day.subtract(const Duration(days: 1));
    }
    return n;
  }

  /// Whether the streak is alive only thanks to yesterday.
  bool isAtRisk(DateTime today) => currentStreak(today) > 0 && !countsForStreak(dateKey(dateOnly(today)));

  int bestStreak() {
    final dates = {...completed.keys.where(anyCompleted), ...frozenDates}.map(parseDateKey).toList()..sort();
    var best = 0;
    var run = 0;
    DateTime? prev;
    for (final d in dates) {
      run = (prev != null && daysBetween(prev, d) == 1) ? run + 1 : 1;
      if (run > best) best = run;
      prev = d;
    }
    return best;
  }

  int get totalCompleted => completed.values.fold(0, (s, v) => s + v.length);

  Map<String, dynamic> toJson() => {
        'completed': {for (final e in completed.entries) e.key: e.value.map((v) => v.code).toList()},
        'frozen': frozenDates.toList(),
        if (lastLoginDate != null) 'lastLoginDate': lastLoginDate,
      };

  static DailyHistory fromJson(Map<String, dynamic> j) {
    final completed = <String, Set<DailyVariant>>{};
    final raw = j['completed'];
    if (raw is Map) {
      for (final e in raw.entries) {
        completed[e.key.toString()] = {
          for (final v in (e.value as List)) DailyVariant.fromCode(v.toString()),
        };
      }
    }
    return DailyHistory(
      completed: completed,
      frozenDates: ((j['frozen'] as List?) ?? const []).map((e) => e.toString()).toSet(),
      lastLoginDate: j['lastLoginDate'] as String?,
    );
  }
}

abstract class DailyRepository {
  Future<DailyHistory> load();
  Future<void> save(DailyHistory history);
}

class JsonDailyRepository implements DailyRepository {
  JsonDailyRepository(this.store, {this.key = 'daily/history'});

  final JsonStore store;
  final String key;

  @override
  Future<DailyHistory> load() async {
    final j = await store.read(key);
    return j == null ? DailyHistory() : DailyHistory.fromJson(j);
  }

  @override
  Future<void> save(DailyHistory history) => store.write(key, history.toJson());
}
