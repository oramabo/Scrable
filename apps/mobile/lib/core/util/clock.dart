/// Injectable time source so dailies, streaks and ledger timestamps are
/// testable.
abstract class Clock {
  const Clock();
  DateTime now();
  int get nowMs => now().millisecondsSinceEpoch;
}

class SystemClock extends Clock {
  const SystemClock();
  @override
  DateTime now() => DateTime.now();
}

class FixedClock extends Clock {
  FixedClock(this.current);
  DateTime current;
  @override
  DateTime now() => current;
  void advance(Duration d) => current = current.add(d);
}

/// Local calendar date as `YYYY-MM-DD`.
String dateKey(DateTime d) {
  String two(int n) => n < 10 ? '0$n' : '$n';
  return '${d.year}-${two(d.month)}-${two(d.day)}';
}

/// Parses `YYYY-MM-DD` as a local date (midnight).
DateTime parseDateKey(String key) {
  final parts = key.split('-');
  return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
}

DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Whole days from [a] to [b] ignoring time of day (b − a).
int daysBetween(DateTime a, DateTime b) => dateOnly(b).difference(dateOnly(a)).inDays;

/// `m:ss` or `h:mm:ss`.
String formatDuration(int ms) {
  final totalSec = ms ~/ 1000;
  final h = totalSec ~/ 3600;
  final m = (totalSec % 3600) ~/ 60;
  final s = totalSec % 60;
  String two(int n) => n < 10 ? '0$n' : '$n';
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}
