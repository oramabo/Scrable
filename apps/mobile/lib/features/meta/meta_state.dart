import 'package:chetz_core/meta.dart';

import '../../core/storage/json_store.dart';

/// Persisted meta-game state: lifetime stats, per-period mission counters,
/// claimed missions and credited achievements, plus progression (XP, season
/// points per season, claimed season tiers, trophies). Pending unlocks are
/// transient (consumed by the UI toast).
class MetaState {
  const MetaState({
    this.stats = const PlayerStats(),
    this.counters = const {},
    this.claimedMissions = const {},
    this.creditedAchievements = const {},
    this.pendingUnlocks = const [],
    this.unlockSeq = 0,
    this.xp = 0,
    this.seasonPoints = const {},
    this.claimedSeasonTiers = const {},
    this.trophies = 0,
    this.serverSynced = false,
  });

  final PlayerStats stats;

  /// `d:<ISO date>` and `w:<ISO week>` → counters for that period.
  final Map<String, MissionCounters> counters;
  final Set<String> claimedMissions;
  final Set<String> creditedAchievements;
  final List<Achievement> pendingUnlocks;
  final int unlockSeq;

  /// Lifetime experience ([XpCurve]).
  final int xp;

  /// Season id (`2026-S1`) → points earned in that season.
  final Map<String, int> seasonPoints;

  /// `season:<id>:tier:<n>` of every claimed tier reward.
  final Set<String> claimedSeasonTiers;

  /// Versus rating (mirrors `users/{uid}.trophies`; local only without cloud).
  final int trophies;

  /// True once xp/trophies/season points were replaced by server values.
  final bool serverSynced;

  static String dailyKey(String isoDate) => 'd:$isoDate';
  static String weeklyKey(String isoDate) => 'w:${MissionEngine.weekKey(isoDate)}';
  static String keyFor(Mission m) => m.period == MissionPeriod.daily ? 'd:${m.periodKey}' : 'w:${m.periodKey}';
  static String seasonTierKey(String seasonId, int tier) => 'season:$seasonId:tier:$tier';

  MissionCounters countersFor(Mission m) => counters[keyFor(m)] ?? const MissionCounters();
  bool isClaimed(Mission m) => claimedMissions.contains(m.id);
  bool canClaim(Mission m) => !isClaimed(m) && countersFor(m).isDone(m);

  int pointsOf(String seasonId) => seasonPoints[seasonId] ?? 0;
  bool isTierClaimed(String seasonId, int tier) => claimedSeasonTiers.contains(seasonTierKey(seasonId, tier));

  int get level => XpCurve.levelForXp(xp);

  MetaState copyWith({
    PlayerStats? stats,
    Map<String, MissionCounters>? counters,
    Set<String>? claimedMissions,
    Set<String>? creditedAchievements,
    List<Achievement>? pendingUnlocks,
    int? unlockSeq,
    int? xp,
    Map<String, int>? seasonPoints,
    Set<String>? claimedSeasonTiers,
    int? trophies,
    bool? serverSynced,
  }) =>
      MetaState(
        stats: stats ?? this.stats,
        counters: counters ?? this.counters,
        claimedMissions: claimedMissions ?? this.claimedMissions,
        creditedAchievements: creditedAchievements ?? this.creditedAchievements,
        pendingUnlocks: pendingUnlocks ?? this.pendingUnlocks,
        unlockSeq: unlockSeq ?? this.unlockSeq,
        xp: xp ?? this.xp,
        seasonPoints: seasonPoints ?? this.seasonPoints,
        claimedSeasonTiers: claimedSeasonTiers ?? this.claimedSeasonTiers,
        trophies: trophies ?? this.trophies,
        serverSynced: serverSynced ?? this.serverSynced,
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
        'xp': xp,
        'seasonPoints': seasonPoints,
        'claimedSeasonTiers': claimedSeasonTiers.toList()..sort(),
        'trophies': trophies,
        'serverSynced': serverSynced,
      };

  static MetaState fromJson(Map<String, dynamic> j) {
    final counters = <String, MissionCounters>{};
    final raw = j['counters'];
    if (raw is Map) {
      for (final e in raw.entries) {
        counters[e.key.toString()] = MissionCounters.fromJson(e.value as Map<String, dynamic>);
      }
    }
    final season = <String, int>{};
    final rawSeason = j['seasonPoints'];
    if (rawSeason is Map) {
      for (final e in rawSeason.entries) {
        if (e.value is num) season[e.key.toString()] = (e.value as num).toInt();
      }
    }
    return MetaState(
      stats: j['stats'] is Map ? PlayerStats.fromJson(j['stats'] as Map<String, dynamic>) : const PlayerStats(),
      counters: counters,
      claimedMissions: ((j['claimedMissions'] as List?) ?? const []).map((e) => e.toString()).toSet(),
      creditedAchievements: ((j['creditedAchievements'] as List?) ?? const []).map((e) => e.toString()).toSet(),
      xp: (j['xp'] as num?)?.toInt() ?? 0,
      seasonPoints: season,
      claimedSeasonTiers: ((j['claimedSeasonTiers'] as List?) ?? const []).map((e) => e.toString()).toSet(),
      trophies: (j['trophies'] as num?)?.toInt() ?? 0,
      serverSynced: (j['serverSynced'] as bool?) ?? false,
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
