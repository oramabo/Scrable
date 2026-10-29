import 'package:chetz_core/meta.dart';

import '../../core/storage/json_store.dart';

/// Persisted meta-game state: lifetime stats, per-period mission counters,
/// claimed missions and credited achievements. Pending unlocks are transient
/// (consumed by the UI toast).
class MetaState {
  const MetaState({
    this.stats = const PlayerStats(),
    this.counters = const {},
    this.claimedMissions = const {},
    this.creditedAchievements = const {},
    this.pendingUnlocks = const [],
    this.unlockSeq = 0,
  });

  final PlayerStats stats;

  /// `d:<ISO date>` and `w:<ISO week>` → counters for that period.
  final Map<String, MissionCounters> counters;
  final Set<String> claimedMissions;
  final Set<String> creditedAchievements;
  final List<Achievement> pendingUnlocks;
  final int unlockSeq;

  static String dailyKey(String isoDate) => 'd:$isoDate';
  static String weeklyKey(String isoDate) => 'w:${MissionEngine.weekKey(isoDate)}';
  static String keyFor(Mission m) => m.period == MissionPeriod.daily ? 'd:${m.periodKey}' : 'w:${m.periodKey}';

  MissionCounters countersFor(Mission m) => counters[keyFor(m)] ?? const MissionCounters();
  bool isClaimed(Mission m) => claimedMissions.contains(m.id);
  bool canClaim(Mission m) => !isClaimed(m) && countersFor(m).isDone(m);

  MetaState copyWith({
    PlayerStats? stats,
    Map<String, MissionCounters>? counters,
    Set<String>? claimedMissions,
    Set<String>? creditedAchievements,
    List<Achievement>? pendingUnlocks,
    int? unlockSeq,
  }) =>
      MetaState(
        stats: stats ?? this.stats,
        counters: counters ?? this.counters,
        claimedMissions: claimedMissions ?? this.claimedMissions,
        creditedAchievements: creditedAchievements ?? this.creditedAchievements,
        pendingUnlocks: pendingUnlocks ?? this.pendingUnlocks,
        unlockSeq: unlockSeq ?? this.unlockSeq,
      );

  /// Drops counters of periods other than the current day/week and claimed
  /// mission ids of past periods.
  MetaState pruned(String today) {
    final keep = {dailyKey(today), weeklyKey(today)};
    final counters = {for (final e in this.counters.entries) if (keep.contains(e.key)) e.key: e.value};
    final claimed = claimedMissions.where((id) {
      final parts = id.split(':');
      if (parts.length < 2) return false;
      return parts[0] == 'daily' ? parts[1] == today : parts[1] == MissionEngine.weekKey(today);
    }).toSet();
    return copyWith(counters: counters, claimedMissions: claimed);
  }

  Map<String, dynamic> toJson() => {
        'stats': stats.toJson(),
        'counters': {for (final e in counters.entries) e.key: e.value.toJson()},
        'claimedMissions': claimedMissions.toList()..sort(),
        'creditedAchievements': creditedAchievements.toList()..sort(),
      };

  static MetaState fromJson(Map<String, dynamic> j) {
    final counters = <String, MissionCounters>{};
    final raw = j['counters'];
    if (raw is Map) {
      for (final e in raw.entries) {
        counters[e.key.toString()] = MissionCounters.fromJson(e.value as Map<String, dynamic>);
      }
    }
    return MetaState(
      stats: j['stats'] is Map ? PlayerStats.fromJson(j['stats'] as Map<String, dynamic>) : const PlayerStats(),
      counters: counters,
      claimedMissions: ((j['claimedMissions'] as List?) ?? const []).map((e) => e.toString()).toSet(),
      creditedAchievements: ((j['creditedAchievements'] as List?) ?? const []).map((e) => e.toString()).toSet(),
    );
  }
}

abstract class MetaRepository {
  Future<MetaState> load();
  Future<void> save(MetaState state);
}

class JsonMetaRepository implements MetaRepository {
  JsonMetaRepository(this.store, {this.key = 'meta/state'});

  final JsonStore store;
  final String key;

  @override
  Future<MetaState> load() async {
    final j = await store.read(key);
    if (j == null) return const MetaState();
    try {
      return MetaState.fromJson(j);
    } catch (_) {
      return const MetaState();
    }
  }

  @override
  Future<void> save(MetaState state) => store.write(key, state.toJson());
}
