import 'package:chetz_app/core/content/content_source.dart';
import 'package:chetz_app/core/util/clock.dart';
import 'package:chetz_app/features/meta/game_events_controller.dart';
import 'package:chetz_app/features/meta/meta_state.dart';
import 'package:chetz_app/features/season/season_info.dart';
import 'package:chetz_app/features/sync/cloud_sync.dart';
import 'package:chetz_app/features/wallet/ledger.dart';
import 'package:chetz_app/features/wallet/wallet_controller.dart';
import 'package:chetz_core/chetz_core.dart';
import 'package:chetz_core/meta.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/harness.dart';

void main() {
  group('SeasonInfo', () {
    test('before the epoch season 1 is shown as upcoming', () {
      final info = SeasonInfo.forDate(DateTime(2026, 10, 28, 12));
      expect(info.number, 1);
      expect(info.id, '2026-S1');
      expect(info.started, isFalse);
      expect(info.startsIn, 5);
    });

    test('inside a season the id and days left match the engine', () {
      final info = SeasonInfo.forDate(DateTime(2026, 11, 2, 9));
      expect(info.number, 1);
      expect(info.started, isTrue);
      expect(info.daysLeft, SeasonPass.daysLeft('2026-11-02'));
      final s2 = SeasonInfo.forDate(DateTime(2026, 12, 14, 9));
      expect(s2.id, '2026-S2');
    });
  });

  group('MetaState progression', () {
    test('json round trip keeps xp, season points, claims and trophies', () {
      const m = MetaState(xp: 123, seasonPoints: {'2026-S1': 45}, claimedSeasonTiers: {'season:2026-S1:tier:1'}, trophies: 130);
      final back = MetaState.fromJson(m.toJson());
      expect(back.xp, 123);
      expect(back.pointsOf('2026-S1'), 45);
      expect(back.isTierClaimed('2026-S1', 1), isTrue);
      expect(back.trophies, 130);
      expect(back.level, XpCurve.levelForXp(123));
    });
  });

  group('GameEventsController progression', () {
    late ProviderContainer container;
    final clock = FixedClock(DateTime(2026, 11, 3, 12));

    setUp(() {
      container = ProviderContainer(overrides: testOverrides(content: MapContentSource(), clock: clock));
    });
    tearDown(() => container.dispose());

    GameEvent completed({required int level, bool daily = false, String variant = 'easy', int hints = 0, int elapsed = 60000}) =>
        GameEvent.puzzleCompleted(
          timestampMs: clock.nowMs,
          lang: 'he',
          puzzleId: 'p',
          level: level,
          mode: PlayMode.normal,
          elapsedMs: elapsed,
          parMs: 300000,
          hintsUsed: hints,
          wordsSolved: 10,
          isDaily: daily,
          dailyVariant: daily ? variant : null,
          dailyDate: daily ? '2026-11-03' : null,
        );

    test('puzzle completions earn XP; dailies and perfect solves earn season points', () {
      final events = container.read(metaProvider.notifier);
      events.record(completed(level: 1, hints: 2));
      expect(container.read(xpProvider), XpCurve.puzzleXp(1, underPar: true));
      expect(container.read(seasonPointsProvider), 0, reason: 'a plain puzzle with hints earns no season points');

      events.record(completed(level: 2, daily: true));
      expect(container.read(seasonPointsProvider), SeasonPass.pointsDaily + SeasonPass.pointsPerfectPuzzle);
      events.record(completed(level: 3, daily: true, variant: 'hard', hints: 1));
      expect(container.read(seasonPointsProvider), SeasonPass.pointsDaily + SeasonPass.pointsPerfectPuzzle + SeasonPass.pointsHardDaily);
      expect(container.read(metaProvider).seasonPoints.keys.single, '2026-S1');
    });

    test('multiplayer completions skip local progression', () {
      final events = container.read(metaProvider.notifier);
      events.record(completed(level: 1), progression: false);
      expect(container.read(xpProvider), 0);
      expect(container.read(playerStatsProvider).puzzlesCompleted, 1);
    });

    test('mission claim pays coins, XP and season points once', () {
      final events = container.read(metaProvider.notifier);
      final mission = container.read(missionsProvider).daily.first;
      // Drive the mission to completion with events of its kind.
      for (var i = 0; i < 40 && !container.read(metaProvider).countersFor(mission).isDone(mission); i++) {
        switch (mission.template.kind) {
          case MissionKind.useAlphabetCycler:
            events.recordCyclerUsed();
          case MissionKind.shareResult:
            events.recordShared();
          case MissionKind.earnCoins:
            events.recordCoinsEarned(100);
          case MissionKind.solveWords:
            events.recordWordSolved('he');
          default:
            events.record(GameEvent.puzzleCompleted(
              timestampMs: clock.nowMs,
              lang: 'he',
              puzzleId: 'p$i',
              level: 4,
              mode: PlayMode.newspaper,
              elapsedMs: 1000,
              parMs: 5 * 60000,
              hintsUsed: 0,
              wordsSolved: 0,
              isDaily: true,
              dailyVariant: i.isEven ? 'easy' : 'hard',
              dailyDate: '2026-11-03',
            ));
        }
      }
      final xpBefore = container.read(xpProvider);
      final pointsBefore = container.read(seasonPointsProvider);
      final balance = container.read(balanceProvider);
      expect(events.claim(mission), isTrue);
      expect(container.read(xpProvider), xpBefore + XpCurve.missionXp);
      expect(container.read(seasonPointsProvider), pointsBefore + SeasonPass.pointsMission);
      expect(container.read(balanceProvider), greaterThan(balance));
      expect(events.claim(mission), isFalse);
    });

    test('season tiers are claimed once as earn_season', () {
      final events = container.read(metaProvider.notifier);
      const season = '2026-S1';
      expect(events.claimSeasonTier(season, 1), 0, reason: 'locked at 0 points');
      // 220 points: tiers 1 and 2 reached.
      for (var i = 0; i < 11; i++) {
        events.record(completed(level: 1, daily: true, variant: 'hard'));
      }
      expect(container.read(seasonPointsProvider), 11 * (SeasonPass.pointsHardDaily + SeasonPass.pointsPerfectPuzzle));
      final balance = container.read(balanceProvider);
      final coins = events.claimSeasonTier(season, 1);
      expect(coins, SeasonPass.tiers[0].coins);
      expect(container.read(balanceProvider), balance + coins);
      expect(events.claimSeasonTier(season, 1), 0, reason: 'idempotent');
      expect(container.read(walletProvider).hasEntry(LedgerEntryType.earnSeason, 'season:$season:tier:1'), isTrue);
      expect(events.claimSeasonTier(season, 2), SeasonPass.tiers[1].coins);
      expect(events.claimSeasonTier(season, 3), 0, reason: 'tier 3 needs 300 points');
      expect(events.claimSeasonTier(season, 31), 0);
    });

    test('server values are preferred when cloud sync is on', () {
      final events = container.read(metaProvider.notifier);
      events.record(completed(level: 1));
      events.applyServerMeta(const ServerMeta(xp: 999, trophies: 310, seasonPoints: {'2026-S1': 150}));
      final m = container.read(metaProvider);
      expect(m.xp, 999);
      expect(m.trophies, 310);
      expect(m.pointsOf('2026-S1'), 150);
      expect(m.serverSynced, isTrue);
      expect(ServerMeta.fromUserDoc({'xp': 5, 'season': {'2026-S1': {'points': 7}}}).seasonPoints, {'2026-S1': 7});
    });

    test('match and co-op results move XP, season points and trophies once', () {
      final events = container.read(metaProvider.notifier);
      events.recordMatchResult(matchId: 'm1', won: true, draw: false, trophyDelta: 30);
      events.recordMatchResult(matchId: 'm1', won: true, draw: false, trophyDelta: 30);
      expect(container.read(xpProvider), XpCurve.matchWinXp);
      expect(container.read(seasonPointsProvider), SeasonPass.pointsMatchWin);
      expect(container.read(metaTrophiesProvider), 30);
      events.recordMatchResult(matchId: 'm2', won: false, draw: false, trophyDelta: -15);
      expect(container.read(metaTrophiesProvider), 15);
      expect(container.read(xpProvider), XpCurve.matchWinXp + XpCurve.matchLossXp);
      events.recordCoopFinished('r1');
      events.recordCoopFinished('r1');
      expect(container.read(xpProvider), XpCurve.matchWinXp + XpCurve.matchLossXp + XpCurve.coopXp);
    });
  });
}
