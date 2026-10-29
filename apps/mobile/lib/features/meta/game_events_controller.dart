import 'package:chetz_core/meta.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/util/clock.dart';
import '../daily/daily_controller.dart';
import '../season/season_info.dart';
import '../settings/settings_controller.dart';
import '../sync/cloud_sync.dart';
import '../wallet/ledger.dart';
import '../wallet/wallet_controller.dart';
import 'meta_state.dart';

/// Single entry point for gameplay events. Every event updates the lifetime
/// [PlayerStats] and the current day/week [MissionCounters]; newly unlocked
/// achievements are credited to the wallet (idempotent per achievement id)
/// and queued for the UI toast. Puzzle completions and mission claims also
/// move XP ([XpCurve]) and season points ([SeasonPass]). State is persisted
/// after each change.
class GameEventsController extends Notifier<MetaState> {
  @override
  MetaState build() => ref.read(bootstrapProvider).meta;

  Clock get _clock => ref.read(clockProvider);
  int get _now => _clock.nowMs;
  String get _seasonId => SeasonInfo.forDate(_clock.now()).id;

  void _set(MetaState next, {bool persist = true}) {
    state = next;
    if (persist) ref.read(metaRepositoryProvider).save(next.pruned(dateKey(_clock.now()))).ignore();
  }

  /// Records an event, updates stats and mission counters, credits unlocks.
  /// A completed puzzle also earns XP and season points unless [progression]
  /// is false (multiplayer sessions, where the server pays).
  void record(GameEvent e, {bool progression = true}) {
    final before = state.stats;
    final after = before.apply(e);
    final date = dateKey(DateTime.fromMillisecondsSinceEpoch(e.timestampMs));
    final counters = Map<String, MissionCounters>.from(state.counters);
    for (final key in [MetaState.dailyKey(date), MetaState.weeklyKey(date)]) {
      counters[key] = (counters[key] ?? const MissionCounters()).apply(e);
    }
    var next = state.copyWith(stats: after, counters: counters);
    if (progression && e.type == GameEventType.puzzleCompleted) {
      final xp = XpCurve.puzzleXp(e.level ?? 1, perfect: e.perfect, underPar: e.underPar, daily: e.isDaily);
      var points = 0;
      if (e.isDaily) points += e.dailyVariant == 'hard' ? SeasonPass.pointsHardDaily : SeasonPass.pointsDaily;
      if (e.perfect) points += SeasonPass.pointsPerfectPuzzle;
      next = _withProgress(next, xp: xp, seasonPoints: points);
    }
    _set(next);

    final unlocked = AchievementEngine.newlyUnlocked(before, after)
        .where((a) => !state.creditedAchievements.contains(a.id))
        .toList();
    for (final a in unlocked) {
      _set(state.copyWith(
        creditedAchievements: {...state.creditedAchievements, a.id},
        pendingUnlocks: [...state.pendingUnlocks, a],
        unlockSeq: state.unlockSeq + 1,
      ));
      ref.read(analyticsProvider).track('achievement_unlocked', {'id': a.id, 'coins': a.rewardCoins});
      // Re-enters record() with a coinsEarned event; terminates because each
      // achievement is credited at most once.
      ref.read(walletProvider.notifier).earn(LedgerEntryType.earnAchievement, a.rewardCoins, refId: 'achievement:${a.id}');
    }
  }

  MetaState _withProgress(MetaState s, {int xp = 0, int seasonPoints = 0}) {
    if (xp == 0 && seasonPoints == 0) return s;
    final id = _seasonId;
    return s.copyWith(
      xp: s.xp + xp,
      seasonPoints: seasonPoints == 0 ? null : {...s.seasonPoints, id: s.pointsOf(id) + seasonPoints},
    );
  }

  // ------------------------------------------------------------ convenience

  void recordWordSolved(String lang) => record(GameEvent.wordSolved(timestampMs: _now, lang: lang));
  void recordHintUsed({required int coins}) => record(GameEvent.hintUsed(timestampMs: _now, coins: coins));
  void recordCoinsEarned(int coins) {
    if (coins > 0) record(GameEvent.coinsEarned(timestampMs: _now, coins: coins));
  }

  void recordCoinsSpent(int coins) {
    if (coins > 0) record(GameEvent.coinsSpent(timestampMs: _now, coins: coins));
  }

  void recordCyclerUsed() => record(GameEvent.alphabetCyclerUsed(timestampMs: _now));
  void recordShared() => record(GameEvent.resultShared(timestampMs: _now));
  void recordLoginDay(String date) => record(GameEvent.loginDay(timestampMs: _now, date: date));

  // ----------------------------------------------------------- multiplayer

  /// A finished versus match: XP and season points per [SeasonPass] /
  /// [XpCurve]; [trophyDelta] mirrors the server's rating change. Idempotent
  /// per match id.
  void recordMatchResult({required String matchId, required bool won, required bool draw, int trophyDelta = 0}) {
    final key = 'match:$matchId';
    if (state.claimedSeasonTiers.contains(key)) return;
    final xp = draw ? 0 : (won ? XpCurve.matchWinXp : XpCurve.matchLossXp);
    final points = draw ? 0 : (won ? SeasonPass.pointsMatchWin : SeasonPass.pointsMatchLoss);
    var next = _withProgress(state, xp: xp, seasonPoints: points);
    next = next.copyWith(
      trophies: (next.trophies + trophyDelta).clamp(0, 1 << 30),
      claimedSeasonTiers: {...next.claimedSeasonTiers, key},
    );
    _set(next);
    ref.read(analyticsProvider).track('match_finished', {'id': matchId, 'won': won, 'draw': draw, 'trophyDelta': trophyDelta});
  }

  /// A finished co-op room (XP only, like the server). Idempotent per room.
  void recordCoopFinished(String roomId) {
    final key = 'coop:$roomId';
    if (state.claimedSeasonTiers.contains(key)) return;
    _set(_withProgress(state, xp: XpCurve.coopXp).copyWith(claimedSeasonTiers: {...state.claimedSeasonTiers, key}));
    ref.read(analyticsProvider).track('coop_finished', {'id': roomId});
  }

  // --------------------------------------------------------------- missions

  /// Claims a completed mission's reward once (coins, XP, season points).
  /// Returns false when not done or already claimed.
  bool claim(Mission m) {
    if (!state.canClaim(m)) return false;
    _set(_withProgress(state, xp: XpCurve.missionXp, seasonPoints: SeasonPass.pointsMission)
        .copyWith(claimedMissions: {...state.claimedMissions, m.id}));
    ref.read(analyticsProvider).track('mission_claimed', {'id': m.id, 'coins': m.reward});
    ref.read(walletProvider.notifier).earn(LedgerEntryType.earnMission, m.reward, refId: 'mission:${m.id}');
    return true;
  }

  // ----------------------------------------------------------------- season

  /// Claims the coins of a reached season tier once (`earn_season`,
  /// `season:<id>:tier:<n>`). Returns the coins credited, 0 when the tier is
  /// locked or already claimed.
  int claimSeasonTier(String seasonId, int tier) {
    if (tier < 1 || tier > SeasonPass.tierCount) return 0;
    final key = MetaState.seasonTierKey(seasonId, tier);
    if (state.claimedSeasonTiers.contains(key)) return 0;
    if (SeasonPass.tierFor(state.pointsOf(seasonId)) < tier) return 0;
    final coins = SeasonPass.tiers[tier - 1].coins;
    _set(state.copyWith(claimedSeasonTiers: {...state.claimedSeasonTiers, key}));
    ref.read(analyticsProvider).track('season_tier_claimed', {'season': seasonId, 'tier': tier, 'coins': coins});
    ref.read(walletProvider.notifier).earn(LedgerEntryType.earnSeason, coins, refId: key);
    return coins;
  }

  /// Prefers the server's authoritative progression (`users/{uid}.xp`,
  /// `.trophies`, `.season.<id>.points`) over the local mirror.
  void applyServerMeta(ServerMeta meta) {
    var next = state.copyWith(serverSynced: true);
    if (meta.xp != null) next = next.copyWith(xp: meta.xp);
    if (meta.trophies != null) next = next.copyWith(trophies: meta.trophies);
    if (meta.seasonPoints.isNotEmpty) next = next.copyWith(seasonPoints: {...next.seasonPoints, ...meta.seasonPoints});
    _set(next);
  }

  /// UI consumed the unlock toasts.
  void consumeUnlocks() {
    if (state.pendingUnlocks.isNotEmpty) _set(state.copyWith(pendingUnlocks: const []), persist: false);
  }

  void reset() => _set(const MetaState());
}

final metaProvider = NotifierProvider<GameEventsController, MetaState>(GameEventsController.new);

final playerStatsProvider = Provider<PlayerStats>((ref) => ref.watch(metaProvider).stats);

/// Lifetime XP and the derived level / rank ([XpCurve]).
final xpProvider = Provider<int>((ref) => ref.watch(metaProvider).xp);
final playerLevelProvider = Provider<int>((ref) => XpCurve.levelForXp(ref.watch(xpProvider)));
final rankIndexProvider = Provider<int>((ref) => XpCurve.rankIndex(ref.watch(playerLevelProvider)));

String rankTitle(int index, String lang) =>
    (lang == 'he' ? XpCurve.rankTitlesHe : XpCurve.rankTitlesEn)[index.clamp(0, XpCurve.rankTitlesHe.length - 1)];

/// The season shown now (local date).
final seasonInfoProvider = Provider<SeasonInfo>((ref) {
  ref.watch(todayProvider);
  return SeasonInfo.forDate(ref.watch(clockProvider).now());
});

final seasonPointsProvider = Provider<int>((ref) => ref.watch(metaProvider).pointsOf(ref.watch(seasonInfoProvider).id));

/// Versus trophies (server value when synced, local mirror otherwise).
final metaTrophiesProvider = Provider<int>((ref) => ref.watch(metaProvider).trophies);

/// Today's three daily and this week's three weekly missions for the active
/// puzzle language.
class MissionSet {
  const MissionSet({required this.daily, required this.weekly, required this.date});
  final List<Mission> daily;
  final List<Mission> weekly;
  final String date;
}

final missionsProvider = Provider<MissionSet>((ref) {
  final today = ref.watch(todayProvider);
  final lang = ref.watch(settingsProvider.select((s) => s.puzzleLang));
  return MissionSet(
    daily: MissionEngine.daily(today, lang: lang),
    weekly: MissionEngine.weekly(today, lang: lang),
    date: today,
  );
});

/// Progress of a mission in its own period.
final missionProgressProvider = Provider.family<int, Mission>((ref, m) => ref.watch(metaProvider).countersFor(m).progressOf(m));

/// Achievements the player has unlocked (by stats), not by credit bookkeeping.
final unlockedAchievementsProvider = Provider<List<Achievement>>(
  (ref) => AchievementEngine.unlocked(ref.watch(playerStatsProvider)),
);

/// Time until the local midnight / next Monday 00:00.
Duration untilNextDay(DateTime now) => DateTime(now.year, now.month, now.day + 1).difference(now);

Duration untilNextWeek(DateTime now) {
  final daysToMonday = 8 - now.weekday; // weekday: Mon=1 … Sun=7
  return DateTime(now.year, now.month, now.day + daysToMonday).difference(now);
}
