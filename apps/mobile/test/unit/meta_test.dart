import 'package:chetz_app/core/content/content_source.dart';
import 'package:chetz_app/core/storage/json_store.dart';
import 'package:chetz_app/core/util/clock.dart';
import 'package:chetz_app/features/daily/daily_controller.dart';
import 'package:chetz_app/features/meta/game_events_controller.dart';
import 'package:chetz_app/features/meta/meta_state.dart';
import 'package:chetz_app/features/wallet/ledger.dart';
import 'package:chetz_app/features/wallet/wallet_controller.dart';
import 'package:chetz_core/chetz_core.dart';
import 'package:chetz_core/meta.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

GameEvent completed(FixedClock clock, {int level = 1, PlayMode mode = PlayMode.normal, int hints = 0, bool daily = false, String variant = 'easy', int elapsedMs = 60000}) =>
    GameEvent.puzzleCompleted(
      timestampMs: clock.nowMs,
      lang: 'he',
      puzzleId: 'p-${clock.nowMs}',
      level: level,
      mode: mode,
      elapsedMs: elapsedMs,
      parMs: 5 * 60 * 1000,
      hintsUsed: hints,
      wordsSolved: 0,
      isDaily: daily,
      dailyVariant: daily ? variant : null,
      dailyDate: daily ? dateKey(clock.now()) : null,
      localHour: clock.now().hour,
    );

void main() {
  late FixedClock clock;
  late MemoryJsonStore store;
  late ProviderContainer container;

  setUp(() {
    clock = FixedClock(DateTime(2026, 10, 29, 12)); // Thursday, ISO week 2026-W44
    store = MemoryJsonStore();
    container = ProviderContainer(overrides: testOverrides(content: MapContentSource(), clock: clock, store: store));
    addTearDown(container.dispose);
  });

  group('GameEventsController', () {
    test('events update lifetime stats and persist', () async {
      final events = container.read(metaProvider.notifier);
      events.record(completed(clock));
      events.recordWordSolved('he');
      events.recordHintUsed(coins: 15);
      final stats = container.read(playerStatsProvider);
      expect(stats.puzzlesCompleted, 1);
      expect(stats.wordsSolved, 1);
      expect(stats.hintsUsed, 1);
      expect(stats.coinsSpent, 15);
      expect(stats.languages, {'he'});
      final saved = await store.read('meta/state');
      expect(MetaState.fromJson(saved!).stats.puzzlesCompleted, 1);
    });

    test('unlocking an achievement credits coins once', () {
      final events = container.read(metaProvider.notifier);
      final before = container.read(balanceProvider);
      events.record(completed(clock, elapsedMs: 10000)); // first_solve, perfect_1, speed_1
      final ledger = container.read(walletProvider);
      expect(ledger.hasEntry(LedgerEntryType.earnAchievement, 'achievement:first_solve'), isTrue);
      expect(ledger.hasEntry(LedgerEntryType.earnAchievement, 'achievement:perfect_1'), isTrue);
      expect(ledger.hasEntry(LedgerEntryType.earnAchievement, 'achievement:speed_1'), isTrue);
      final reward = Achievements.byId['first_solve']!.rewardCoins +
          Achievements.byId['perfect_1']!.rewardCoins +
          Achievements.byId['speed_1']!.rewardCoins;
      expect(container.read(balanceProvider), before + reward);
      expect(container.read(metaProvider).pendingUnlocks.map((a) => a.id), containsAll(['first_solve', 'perfect_1', 'speed_1']));
      // The coinsEarned events from the credits were recorded too.
      expect(container.read(playerStatsProvider).coinsEarned, reward);
      // A second identical completion does not re-credit.
      events.record(completed(clock, elapsedMs: 10000));
      expect(container.read(walletProvider).entries.where((e) => e.type == LedgerEntryType.earnAchievement).length, 3);
      events.consumeUnlocks();
      expect(container.read(metaProvider).pendingUnlocks, isEmpty);
    });

    test('wallet earn/spend record coin events (hints excluded)', () {
      final wallet = container.read(walletProvider.notifier);
      wallet.earn(LedgerEntryType.earnDaily, 40, refId: 'daily:x');
      wallet.spend(LedgerEntryType.spendItem, 150, refId: 'freeze:1');
      wallet.spend(LedgerEntryType.spendLetter, 15, refId: 'hint:1', trackEvent: false);
      final stats = container.read(playerStatsProvider);
      expect(stats.coinsEarned, 40);
      expect(stats.coinsSpent, 150);
    });

    test('login day is counted once per date', () {
      final events = container.read(metaProvider.notifier);
      events.recordLoginDay('2026-10-29');
      events.recordLoginDay('2026-10-29');
      events.recordLoginDay('2026-10-30');
      expect(container.read(playerStatsProvider).loginDays, 2);
    });
  });

  group('missions', () {
    test('progress follows events; claim is idempotent and pays once', () {
      final events = container.read(metaProvider.notifier);
      final set = container.read(missionsProvider);
      expect(set.daily.length, 3);
      expect(set.weekly.length, 3);
      final mission = set.daily.first;
      final target = mission.target;
      for (var i = 0; i < 400 && !container.read(metaProvider).countersFor(mission).isDone(mission); i++) {
        switch (mission.template.kind) {
          case MissionKind.useAlphabetCycler:
            events.recordCyclerUsed();
          case MissionKind.shareResult:
            events.recordShared();
          case MissionKind.earnCoins:
            events.recordCoinsEarned(50);
          case MissionKind.solveWords:
            events.recordWordSolved('he');
          default:
            events.record(completed(clock, level: 4, mode: PlayMode.newspaper, daily: true, variant: i.isEven ? 'easy' : 'hard', elapsedMs: 1000));
        }
      }
      final meta = container.read(metaProvider);
      expect(meta.countersFor(mission).progressOf(mission), greaterThanOrEqualTo(target));
      expect(meta.canClaim(mission), isTrue);

      final before = container.read(balanceProvider);
      expect(events.claim(mission), isTrue);
      expect(container.read(balanceProvider), before + mission.reward);
      expect(events.claim(mission), isFalse, reason: 'already claimed');
      expect(container.read(balanceProvider), before + mission.reward);
      expect(container.read(walletProvider).entries.where((e) => e.type == LedgerEntryType.earnMission).length, 1);
      expect(container.read(metaProvider).isClaimed(mission), isTrue);
    });

    test('cannot claim an unfinished mission', () {
      final set = container.read(missionsProvider);
      expect(container.read(metaProvider.notifier).claim(set.daily.first), isFalse);
    });

    test('daily counters reset at local midnight; weekly at Monday', () async {
      final events = container.read(metaProvider.notifier);
      events.record(completed(clock));
      final day1 = container.read(missionsProvider);
      final m1 = day1.daily.first;
      final w1 = day1.weekly.first;
      expect(container.read(metaProvider).countersFor(m1).puzzlesCompleted, 1);
      expect(container.read(metaProvider).countersFor(w1).puzzlesCompleted, 1);

      // Friday: new daily period, same ISO week.
      clock.advance(const Duration(days: 1));
      container.read(refreshTodayProvider.notifier).bump();
      final day2 = container.read(missionsProvider);
      expect(day2.date, '2026-10-30');
      expect(day2.daily.first.periodKey, '2026-10-30');
      expect(container.read(metaProvider).countersFor(day2.daily.first).puzzlesCompleted, 0);
      expect(day2.weekly.first.periodKey, w1.periodKey);
      expect(container.read(metaProvider).countersFor(day2.weekly.first).puzzlesCompleted, 1);

      // Monday 2026-11-02: new week.
      clock.advance(const Duration(days: 3));
      container.read(refreshTodayProvider.notifier).bump();
      final week2 = container.read(missionsProvider);
      expect(MissionEngine.weekKey('2026-11-02'), '2026-W45');
      expect(week2.weekly.first.periodKey, '2026-W45');
      expect(container.read(metaProvider).countersFor(week2.weekly.first).puzzlesCompleted, 0);
      // Pruning drops old periods from the persisted state.
      events.record(completed(clock));
      final saved = MetaState.fromJson((await store.read('meta/state'))!);
      expect(saved.counters.keys, unorderedEquals(['d:2026-11-02', 'w:2026-W45']));
    });
  });

  group('MetaState json', () {
    test('round trip', () {
      final state = MetaState(
        stats: const PlayerStats(puzzlesCompleted: 3),
        counters: {'d:2026-10-29': const MissionCounters(puzzlesCompleted: 2)},
        claimedMissions: {'daily:2026-10-29:solve_puzzles'},
        creditedAchievements: {'first_solve'},
      );
      final back = MetaState.fromJson(state.toJson());
      expect(back.stats.puzzlesCompleted, 3);
      expect(back.counters['d:2026-10-29']!.puzzlesCompleted, 2);
      expect(back.claimedMissions, {'daily:2026-10-29:solve_puzzles'});
      expect(back.creditedAchievements, {'first_solve'});
    });

    test('pruned keeps only the current day and week', () {
      final state = MetaState(
        counters: {'d:2026-10-28': const MissionCounters(), 'd:2026-10-29': const MissionCounters(), 'w:2026-W43': const MissionCounters(), 'w:2026-W44': const MissionCounters()},
        claimedMissions: {'daily:2026-10-28:x', 'daily:2026-10-29:y', 'weekly:2026-W44:z', 'weekly:2026-W43:q'},
      );
      final p = state.pruned('2026-10-29');
      expect(p.counters.keys, unorderedEquals(['d:2026-10-29', 'w:2026-W44']));
      expect(p.claimedMissions, unorderedEquals(['daily:2026-10-29:y', 'weekly:2026-W44:z']));
    });
  });

  group('countdowns', () {
    test('until next day / next week', () {
      final now = DateTime(2026, 10, 29, 22, 30); // Thursday
      expect(untilNextDay(now), const Duration(hours: 1, minutes: 30));
      expect(untilNextWeek(now), const Duration(days: 3, hours: 1, minutes: 30));
      expect(untilNextWeek(DateTime(2026, 11, 1, 23)), const Duration(hours: 1)); // Sunday
    });
  });
}
