import 'package:chetz_core/meta.dart';

import '../../core/util/clock.dart';

/// The season shown in the app for a local date. Before the first season
/// (epoch 2026-11-02) season 1 is shown as "upcoming" and local points
/// already accrue to it, so the pass is never empty.
class SeasonInfo {
  const SeasonInfo({required this.number, required this.id, required this.daysLeft, required this.startsIn});

  /// 1-based season number (never 0).
  final int number;

  /// `2026-S1`-style id, identical to the server's.
  final String id;

  /// Days left in the season (0 on its last day).
  final int daysLeft;

  /// Days until the season starts; 0 once it is running.
  final int startsIn;

  bool get started => startsIn == 0;

  static String idOf(int number) => '${SeasonPass.seasonStart(number).year}-S$number';

  static SeasonInfo forDate(DateTime localNow) {
    final iso = dateKey(localNow);
    final day = DateTime.utc(localNow.year, localNow.month, localNow.day);
    final n = SeasonPass.seasonNumber(iso);
    if (n <= 0) {
      final start = SeasonPass.seasonStart(1);
      final untilStart = start.difference(day).inDays;
      return SeasonInfo(number: 1, id: idOf(1), daysLeft: SeasonPass.seasonDays - 1, startsIn: untilStart < 0 ? 0 : untilStart);
    }
    return SeasonInfo(number: n, id: idOf(n), daysLeft: SeasonPass.daysLeft(iso), startsIn: 0);
  }

  List<SeasonTier> get tiers => SeasonPass.tiers;
}
