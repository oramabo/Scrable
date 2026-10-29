import 'package:chetz_core/meta.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/util/clock.dart';
import '../daily/daily_controller.dart';
import '../settings/settings_controller.dart';
import '../wallet/ledger.dart';
import '../wallet/wallet_controller.dart';
import 'meta_state.dart';

/// Single entry point for gameplay events. Every event updates the lifetime
/// [PlayerStats] and the current day/week [MissionCounters]; newly unlocked
/// achievements are credited to the wallet (idempotent per achievement id)
/// and queued for the UI toast. State is persisted after each change.
class GameEventsController extends Notifier<MetaState> {
  @override
  MetaState build() => ref.read(bootstrapProvider).meta;

  Clock get _clock => ref.read(clockProvider);
  int get _now => _clock.nowMs;

  void _set(MetaState next, {bool persist = true}) {
    state = next;
    if (persist) ref.read(metaRepositoryProvider).save(next.pruned(dateKey(_clock.now()))).ignore();
  }

  /// Records an event, updates stats and mission counters, credits unlocks.
  void record(GameEvent e) {
    final before = state.stats;
    final after = before.apply(e);
    final date = dateKey(DateTime.fromMillisecondsSinceEpoch(e.timestampMs));
    final counters = Map<String, MissionCounters>.from(state.counters);
    for (final key in [MetaState.dailyKey(date), MetaState.weeklyKey(date)]) {
      counters[key] = (counters[key] ?? const MissionCounters()).apply(e);
    }
    _set(state.copyWith(stats: after, counters: counters));

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

  // --------------------------------------------------------------- missions

  /// Claims a completed mission's reward once. Returns false when not done or
  /// already claimed.
  bool claim(Mission m) {
    if (!state.canClaim(m)) return false;
    _set(state.copyWith(claimedMissions: {...state.claimedMissions, m.id}));
    ref.read(analyticsProvider).track('mission_claimed', {'id': m.id, 'coins': m.reward});
    ref.read(walletProvider.notifier).earn(LedgerEntryType.earnMission, m.reward, refId: 'mission:${m.id}');
    return true;
  }

  /// UI consumed the unlock toasts.
  void consumeUnlocks() {
    if (state.pendingUnlocks.isNotEmpty) _set(state.copyWith(pendingUnlocks: const []), persist: false);
  }

  void reset() => _set(const MetaState());
}

final metaProvider = NotifierProvider<GameEventsController, MetaState>(GameEventsController.new);

final playerStatsProvider = Provider<PlayerStats>((ref) => ref.watch(metaProvider).stats);

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
